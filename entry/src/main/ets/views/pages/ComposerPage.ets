import webview from '@ohos.web.webview';
import { curves, KeyboardAvoidMode } from '@kit.ArkUI';
import window from '@ohos.window';
import { inputMethod } from '@kit.IMEKit';
import { Log } from '../../services/logging/Log';
import { SYS_BOTTOM_INSET_KEY, SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { JsonNetworkClient } from '../../services/network/NetworkTypes';
import { UploadService, UploadedImage } from '../../services/upload/UploadService';
import { MarkdownRenderService } from '../../services/content/MarkdownRenderService';
import { MarkdownToolbar } from '../components/MarkdownToolbar';
import { PostRichContent } from '../components/PostRichContent';
import { applyAction, EditState, MdAction } from '../../utils/markdownInsert';

const LOG_TAG: string = '[ArkDO][Composer]';
// 一次最多选图张数(对齐 Discourse composer 手感)。
const MAX_PICK: number = 9;
// 编辑区焦点 id:内联挂载时 defaultFocus 不可靠(展开前内联输入条卸载会收键盘),挂载后
// 主动 requestFocus 把键盘弹回来,焦点无缝落到全屏编辑区。
const EDIT_FOCUS_ID: string = 'arkdoComposerInput';
// 一镜到底共享元素 id:详情页底部输入条(源)与本页主面板(目标)标同一 id,展开时由同一
// animateTo 插值——输入条几何生长铺满全屏(对齐首页搜索的 geometryTransition 手法)。
export const COMPOSER_GEOMETRY_ID: string = 'arkdo-composer-surface';
// 一镜到底转场时长(ms):展开/回落 + 主面板淡入统一用它,详情页的 openFullComposer/
// closeFullComposer 也读它。调试想看慢动作把这个数临时调大(如 1200),看完改回 280。
export const COMPOSER_ANIM_MS: number = 280;
// 全屏编辑器浮层可见态镜像 + 系统返回键信号:浮层内联挂在详情页根 Stack,不进 Navigation 栈,
// 返回键须由详情页所在 NavDestination.onBackPressed 拦截——可见时 bump BACK_TICK,详情页监听后关闭。
export const COMPOSER_OVERLAY_VISIBLE_KEY: string = 'composerOverlayVisible';
export const COMPOSER_OVERLAY_BACK_TICK_KEY: string = 'composerOverlayBackTick';

// 编辑器两种模式:源码编辑 / 只读预览。切换走同页 animateTo 交叉过渡(不跳路由)。
enum ComposerMode {
  Edit = 'edit',
  Preview = 'preview'
}

// 全屏 Markdown 编辑页:TextArea 源码 + 工具栏 + 图片上传 + 编辑/预览「一境到底」切换 + 发送。
// 只产出 markdown 文本经 onSubmit 交回上层提交(复用详情页现有 createReply 链路);
// 图片上传与预览编译各自内聚在本页(隐藏 Web 跑 markdown-it、UploadService 走 host webview 传图)。
@Component
export struct ComposerPage {
  // 窗口常驻全屏:根列自行避让状态栏 + 底部手势条(统一读 ImmersiveWindow 冻结的 inset,
  // 沉浸式全屏下 TYPE_SYSTEM 底部为 0,须用按 TYPE_NAVIGATION_INDICATOR 算的底部 inset)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  @StorageProp(SYS_BOTTOM_INSET_KEY) private sysBottomInset: number = 0;
  bridge: JsonNetworkClient | undefined = undefined;
  isArkWebReady: boolean = false;
  // 顶栏标题(回复/发帖)。
  headerTitle: string = '回复';
  placeholder: string = '写下你的回复…';
  // 初始正文(草稿恢复/编辑已发帖时带入)。
  initialText: string = '';
  // 最短字数(回帖 16;发帖可更小)。低于则发送置灰。
  minChars: number = 1;
  // 展开瞬间的键盘高度(vp):由内联输入条经详情页传入,做 keyboardHeight 初值,让首帧就按
  // 「有键盘」布局(工具栏直接在键盘上方),避免从 0 起跳的二次布局跳变(观感「回缩一下」)。
  initialKeyboardHeight: number = 0;
  onBack: () => void = () => {};
  // 返回 true 表示提交成功(随即返回);false 保留内容供重试。typing/composer 时长对齐官方遥测。
  onSubmit: (raw: string, typingMs: number, composerMs: number) => Promise<boolean> =
    (raw: string, typingMs: number, composerMs: number) => Promise.resolve(false);

  @State private text: string = '';
  @State private mode: ComposerMode = ComposerMode.Edit;
  @State private previewHtml: string = '';
  @State private isPreviewLoading: boolean = false;
  @State private isSubmitting: boolean = false;
  @State private isUploading: boolean = false;
  // 上传进度:本批总张数 / 已完成张数,驱动上传中浮层的「上传中 x/N」。
  @State private uploadTotal: number = 0;
  @State private uploadDone: number = 0;
  // 编辑内容区透明度:编辑↔预览切换时做交叉淡入(配合 animateTo)。
  @State private contentOpacity: number = 1;
  // 当前键盘高度(vp);0=键盘收起。窗口常驻全屏,不能用 RESIZE(避让区与 expandSafeArea 打架、
  // 工具栏被键盘盖住),改手动监听 avoidAreaChange 把底部按键盘高度上移(同 CommentInputBar)。
  @State private keyboardHeight: number = 0;
  private winClass?: window.Window = undefined;
  // 绑定 this 便于 off 注销。键盘避让区变化即键盘高度(本项目已验证有效)。
  private onAvoidAreaChange: (data: window.AvoidAreaOptions) => void = (data: window.AvoidAreaOptions) => {
    if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      const height: number = px2vp(data.area.bottomRect.height);
      // 用系统输入法面板同款弹簧曲线驱动上移,与键盘逐帧同步(不挂 .animation 于图标父容器)。
      this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 342, 38) }, () => {
        this.keyboardHeight = height;
      });
    }
  };

  // 当前选区(不驱动 UI,故非 @State);onTextSelectionChange 实时更新,工具栏插入据此包裹/定位。
  private selStart: number = 0;
  private selEnd: number = 0;
  private textController: TextAreaController = new TextAreaController();
  // 隐藏的 markdown-it 渲染 Web 控制器。
  private mdWebController: webview.WebviewController = new webview.WebviewController();
  private mdService: MarkdownRenderService = new MarkdownRenderService();
  private uploadService?: UploadService;
  // 遥测:入页时刻 / 首次输入时刻。
  private appearTimeMs: number = 0;
  private firstTypeTimeMs: number = 0;

  aboutToAppear(): void {
    this.appearTimeMs = Date.now();
    this.text = this.initialText;
    // 首帧就按「有键盘」布局:用展开瞬间传入的键盘高度做初值,工具栏直接落在键盘上方,
    // 不再从 0 起跳后被 avoidAreaChange 二次上移(消除「回缩一下」)。
    this.keyboardHeight = this.initialKeyboardHeight;
    if (this.bridge) {
      this.uploadService = new UploadService(this.bridge);
    }
    // 关掉系统整页避让,自己按键盘高度上移底部工具栏(内容区随之收缩),背后不整页跳动。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.winClass = win;
      win.on('avoidAreaChange', this.onAvoidAreaChange);
    }).catch(() => {
      // 拿不到 window 时退化为不上移(工具栏仍在底部),不影响编辑本身。
    });
    // 焦点抓取不在这里做:aboutToAppear 时 TextArea 尚未挂载,requestFocus 会落空、键盘先收后弹
    // (出现"收起键盘"的多余动作)。改到编辑区 TextArea 的 onAppear 里挂载即抢焦点,让焦点从
    // 内联输入条无缝转到全屏编辑区,输入法会话不断开、键盘全程不收。
  }

  aboutToDisappear(): void {
    this.mdService.detach();
    // 关闭前主动收键盘:否则键盘残留 + 还原 OFFSET 会把背后详情页整页顶起(实测"整个页面往上跑")。
    try {
      inputMethod.getController().stopInputSession();
    } catch (err) {
      // 收键盘失败不影响关闭。
    }
    if (this.winClass) {
      this.winClass.off('avoidAreaChange', this.onAvoidAreaChange);
      this.winClass = undefined;
    }
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
  }

  private trimmedLength(): number {
    return this.text.trim().length;
  }

  private canSubmit(): boolean {
    return !this.isSubmitting && this.trimmedLength() >= this.minChars;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (error) {
      // Toast 失败不影响主流程。
    }
  }

  // 应用一次工具栏格式动作:纯函数算出新文本与选区,回写并把光标/选区还原到期望位置。
  private applyToolbarAction(action: MdAction): void {
    const current: EditState = { text: this.text, selectionStart: this.selStart, selectionEnd: this.selEnd };
    const next: EditState = applyAction(current, action);
    this.text = next.text;
    this.selStart = next.selectionStart;
    this.selEnd = next.selectionEnd;
    // 下一帧再定位(等 TextArea 收到新文本),避免旧长度下 setTextSelection 越界。
    setTimeout(() => {
      this.textController.setTextSelection(next.selectionStart, next.selectionEnd);
    }, 0);
  }

  // 选图并逐张上传:成功即在光标处插入图片 markdown 短码。上传中置灰图片按钮。
  private async pickAndUpload(): Promise<void> {
    if (!this.uploadService || this.isUploading) {
      return;
    }
    const uris: string[] = await this.uploadService.pickImages(MAX_PICK);
    if (uris.length === 0) {
      return;
    }
    this.isUploading = true;
    this.uploadTotal = uris.length;
    this.uploadDone = 0;
    for (let i: number = 0; i < uris.length; i++) {
      const img: UploadedImage | undefined = await this.uploadService.uploadUri(uris[i]);
      if (img) {
        // 图片是纯插入:在当前光标处插入图片 markdown 短码,光标移到其后。
        const snippet: string = `\n${UploadService.buildImageMarkdown(img)}\n`;
        const head: string = this.text.substring(0, this.selStart);
        const tail: string = this.text.substring(this.selEnd);
        this.text = head + snippet + tail;
        const caret: number = head.length + snippet.length;
        this.selStart = caret;
        this.selEnd = caret;
      } else {
        this.showToast('有图片上传失败');
      }
      this.uploadDone = i + 1;
    }
    this.isUploading = false;
    this.uploadTotal = 0;
    this.uploadDone = 0;
  }

  // 切到预览:先离屏编译 markdown→HTML→替换 upload:// 短码为真实直链,再 animateTo 交叉淡入切模式(无白屏)。
  private async enterPreview(): Promise<void> {
    if (this.mode === ComposerMode.Preview) {
      return;
    }
    this.isPreviewLoading = true;
    let html: string = '';
    try {
      const raw: string = await this.mdService.render(this.text);
      html = this.uploadService ? this.uploadService.resolvePreviewHtml(raw) : raw;
    } catch (error) {
      Log.i(`${LOG_TAG} preview render failed`);
      html = '';
    }
    this.previewHtml = html;
    this.isPreviewLoading = false;
    this.crossFadeTo(ComposerMode.Preview);
  }

  private enterEdit(): void {
    if (this.mode === ComposerMode.Edit) {
      return;
    }
    this.crossFadeTo(ComposerMode.Edit);
  }

  // 内容区交叉淡入:淡出→切模式→淡入,一次连续过渡(不跳路由)。
  private crossFadeTo(target: ComposerMode): void {
    this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseIn }, () => {
      this.contentOpacity = 0;
    });
    setTimeout(() => {
      this.mode = target;
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
        this.contentOpacity = 1;
      });
    }, 120);
  }

  private async submit(): Promise<void> {
    if (!this.canSubmit()) {
      if (this.trimmedLength() < this.minChars) {
        this.showToast(`至少还需 ${this.minChars - this.trimmedLength()} 个字`);
      }
      return;
    }
    this.isSubmitting = true;
    const typingMs: number = this.firstTypeTimeMs > 0 ? Date.now() - this.firstTypeTimeMs : 0;
    const composerMs: number = this.appearTimeMs > 0 ? Date.now() - this.appearTimeMs : 0;
    let ok: boolean = false;
    try {
      ok = await this.onSubmit(this.text.trim(), typingMs, composerMs);
    } catch (error) {
      ok = false;
    }
    this.isSubmitting = false;
    if (ok) {
      this.onBack();
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.Header()
        this.ContentArea()
        if (this.mode === ComposerMode.Edit) {
          MarkdownToolbar({
            disabled: this.isUploading,
            onAction: (action: MdAction): void => {
              this.applyToolbarAction(action);
            },
            onPickImage: (): void => {
              this.pickAndUpload();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      // 键盘弹起:底部留键盘高度让工具栏贴键盘上沿;收起:留底部安全区贴 Home 条之上。
      .padding({ top: this.sysTopInset, bottom: this.keyboardHeight > 0 ? this.keyboardHeight : this.sysBottomInset })
      .backgroundColor($r('app.color.page_bg'))
      // 一镜到底主体:与详情页底部输入条同 id,展开时从输入条几何生长铺满全屏;clip 裁掉
      // 生长中溢出的子内容;OPACITY 让配对元素交叉淡入(对齐搜索浮层手法)。
      .geometryTransition(COMPOSER_GEOMETRY_ID, { follow: true })
      .clip(true)
      .transition(TransitionEffect.OPACITY.animation({ duration: COMPOSER_ANIM_MS, curve: Curve.EaseOut }))

      // 隐藏的 markdown-it 渲染 Web:1×1、透明、不响应点击。只做 raw→HTML 编译。
      Web({ src: $rawfile('markdown/render.html'), controller: this.mdWebController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy(this.mdService.createProxy(this.mdWebController))
        .onPageEnd(() => {
          this.mdService.attachController(this.mdWebController);
        })
        .width(1)
        .height(1)
        .opacity(0)
        .hitTestBehavior(HitTestMode.None)

      // 图片上传中浮层:半透明遮罩 + 居中「上传中 x/N」胶囊。Block 拦截交互,避免上传期间移动光标
      // 打乱插入位置(短码在 await 后按 selStart 插入)。多张时显示进度。
      if (this.isUploading) {
        Column() {
          Row({ space: 10 }) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color($r('app.color.brand'))
            Text(this.uploadTotal > 1 ? `图片上传中 ${this.uploadDone}/${this.uploadTotal}` : '图片上传中…')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          }
          .padding({ left: 20, right: 20, top: 14, bottom: 14 })
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius(12)
          .shadow({ radius: 16, color: '#26000000', offsetY: 4 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#33000000')
        .hitTestBehavior(HitTestMode.Block)
      }
    }
    .width('100%')
    .height('100%')
    // 根 Stack 透明:一镜到底期间生长面板之外露出背后详情页(面板全开时自身 page_bg 盖满)。
  }

  @Builder
  private Header() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.surface_muted'))
      .onClick(() => {
        this.onBack();
      })

      // 中部:编辑/预览分段切换。
      Row() {
        this.SegmentTab('编辑', ComposerMode.Edit)
        this.SegmentTab('预览', ComposerMode.Preview)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      // 发送按钮:与左侧关闭按钮同款圆形系统按钮(SymbolGlyph 纸飞机),但保留蓝底白图标突出主操作。
      // 达标可点,提交中转圈。
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        if (this.isSubmitting) {
          LoadingProgress().width(20).height(20).color('#FFFFFF')
        } else {
          // paperplane_fill 朝正北(上):纸飞机头朝上。
          SymbolGlyph($r('sys.symbol.paperplane_fill'))
            .fontSize(19)
            .fontColor(['#FFFFFF'])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
      }
      .width(40)
      .height(40)
      .backgroundColor('#0088CC')
      .opacity(this.canSubmit() ? 1 : 0.5)
      .onClick(() => {
        this.submit();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SegmentTab(label: string, target: ComposerMode) {
    Text(label)
      .fontSize(15)
      .fontColor(this.mode === target ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
      .fontWeight(this.mode === target ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .onClick(() => {
        if (target === ComposerMode.Preview) {
          this.enterPreview();
        } else {
          this.enterEdit();
        }
      })
  }

  @Builder
  private ContentArea() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.mode === ComposerMode.Edit) {
        TextArea({ text: $$this.text, placeholder: this.placeholder, controller: this.textController })
          .id(EDIT_FOCUS_ID)
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .fontSize(16)
          .lineHeight(24)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .defaultFocus(true)
          .enterKeyType(EnterKeyType.NEW_LINE)
          .onChange((value: string) => {
            if (this.firstTypeTimeMs === 0 && value.length > 0) {
              this.firstTypeTimeMs = Date.now();
            }
          })
          .onTextSelectionChange((start: number, end: number) => {
            this.selStart = start;
            this.selEnd = end;
          })
          // 挂载即抢焦点:与内联输入条卸载几乎同帧,焦点无缝转移,键盘不收(消除"收起再弹起")。
          .onAppear(() => {
            // 再拨回 NONE:内联输入条 aboutToDisappear 可能刚把避让模式还原成 OFFSET,交接错位会让
            // 系统整页避让把全屏内容顶一下(观感"回缩一点再弹回")。这里盖掉它,统一走手动 margin 避让。
            this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
            this.getUIContext().getFocusController().requestFocus(EDIT_FOCUS_ID);
            // 抢焦点后立即请求显示软键盘保活:尽量抵消内联输入框失焦触发的收起动画,压平"收一点再弹"。
            // 失败无害(requestFocus 本身也会弹键盘)。
            try {
              inputMethod.getController().showSoftKeyboard().catch(() => {});
            } catch (err) {
            }
          })
      } else {
        Scroll() {
          Column() {
            if (this.previewHtml.length > 0) {
              PostRichContent({
                cookedHtml: this.previewHtml,
                fallbackText: this.text
              })
            } else {
              Text('（无内容可预览）')
                .fontSize(15)
                .fontColor($r('app.color.text_tertiary'))
                .padding(16)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .opacity(this.contentOpacity)
  }
}
