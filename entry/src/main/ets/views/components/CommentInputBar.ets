import { curves, KeyboardAvoidMode } from '@kit.ArkUI';
import window from '@ohos.window';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { COMPOSER_GEOMETRY_ID } from '../pages/ComposerPage';
import { showToast as promptToast } from '../../common/utils/Toast';

// Discourse 经典蓝，作回复按钮背景（rgb(0,136,204)）。页面的悬浮回复按钮也复用此色。
export const REPLY_BLUE: string = '#0088CC';
// 输入框最小/最高高度：低于最小高度不再缩，超过最高高度 TextArea 内部滚动。
// 最小高度给足竖向空间，避免光标上下被截。
const INPUT_MIN_HEIGHT: number = 44;
const INPUT_MAX_HEIGHT: number = 120;
// 输入框获取焦点用的 id：挂载后 requestFocus 弹出软键盘。
const INPUT_FOCUS_ID: string = 'arkdoCommentInput';
// maxChars 取该值表示不限字数（回复走这条）。
export const NO_MAX_CHARS: number = 0;

// 键盘上方的评论输入浮层（由 TopicDetailPage 直接内联挂在页面根 Stack 顶层）：
// - 内联渲染 → getLastWindow 拿到的就是主窗口，能稳定收到键盘事件；监听 avoidAreaChange
//   拿到 TYPE_KEYBOARD 避让高度，手动把输入条按该高度上移到键盘上方（背后列表不动）。
// - 全屏布局由页面(TopicDetailPage)在展开评论时切换（并给背后主内容补状态栏高度抵消位移），
//   全屏下遮罩能盖住状态栏、输入条按 margin=键盘高度贴到键盘上沿。
// - 键盘收起时输入条底部叠加底部安全区内边距贴 Home 条之上；键盘弹起时上移键盘高度、收掉这段内边距。
@Component
export struct CommentInputBar {
  onClose: () => void = () => {};
  // 输入框占位文字：回复话题为「回复当前话题」，回复某楼为「回复<昵称>」，由页面传入。
  placeholder: string = '写下你的评论…';
  // 正文最短字数：少于该值不允许提交。评论默认 16（对齐 Discourse 最短回复），
  // boost 这类短文本由页面传入更小的值（如 1）。
  minChars: number = 16;
  // 正文最长字数：NO_MAX_CHARS 表示不限（回复走这条）。boost 服务端上限 16，超出会被 422
  // 打回且不带原因，只能在客户端先拦住。
  maxChars: number = NO_MAX_CHARS;
  // 返回 true 表示提交成功（浮层随即清空并关闭）；false 表示失败（保留内容供重试）。
  onSubmit: (text: string, typingMs: number, composerMs: number) => Promise<boolean> =
    (text: string, typingMs: number, composerMs: number) => Promise.resolve(false);
  // 是否显示「展开到全屏编辑器」按钮：普通回复显示，boost（短文本，服务端上限 16 字）不显示。
  showExpand: boolean = false;
  // 点「展开」上抛当前已输入文本 + 当前键盘高度（vp），由页面关闭内联浮层并压入全屏编辑器
  // （ComposerPage）无缝接续。带键盘高度是为了让全屏页首帧就按「有键盘」布局，避免从 0 起跳
  // 导致工具栏先落底再上移的「回缩一下」。
  onExpand: (currentText: string, keyboardHeight: number) => void = () => {};
  // 初始正文:页面把上次未发出的内容带回来(关掉输入条再点开,内容还在)。
  initialText: string = '';
  // 文本变化时上抛给页面暂存。内联条一关就卸载、@State 随之销毁,不上抛就彻底丢了。
  onTextChange: (text: string) => void = () => {};
  @State private text: string = '';
  @State private isSubmitting: boolean = false;
  // 当前键盘高度（vp）；0 表示键盘收起。
  @State private keyboardHeight: number = 0;
  // 底部安全区高度（vp，挂载时读一次，用于键盘收起时的底部内边距）。
  @State private bottomInset: number = 0;
  private winClass?: window.Window = undefined;
  private focusTimer: number = -1;
  // 浮层出现的时刻 / 首次输入的时刻，用于回填 composer_open / typing 时长（对齐官方遥测字段）。
  private appearTimeMs: number = 0;
  private firstTypeTimeMs: number = 0;
  // 上一次 onChange 时是否已超上限：用于只在「刚超出」的那一下弹提示。
  private wasOverMaxChars: boolean = false;
  // 绑定 this，方便 off 时传入同一引用注销。监听键盘避让区变化拿键盘高度（本机已验证有效）。
  private onAvoidAreaChange: (data: window.AvoidAreaOptions) => void = (data: window.AvoidAreaOptions) => {
    if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      // 键盘避让矩形高度 = 键盘顶到屏幕底的遮挡高度；收起时为 0。
      const height: number = px2vp(data.area.bottomRect.height);
      // 用显式 animateTo 驱动上移动画（不在输入条/图标的父容器上挂 .animation，避免图标不渲染）。
      // 曲线取系统输入法面板同款弹簧曲线(输入法框架统一驱动面板动画,与具体输入法 App 无关),
      // 让输入条与键盘几乎逐帧同步;弹簧曲线时长由物理参数决定,不需要 duration。
      this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 342, 38) }, () => {
        this.keyboardHeight = height;
      });
    }
  };

  aboutToAppear(): void {
    this.appearTimeMs = Date.now();
    // 带回上次未发出的内容(页面暂存的)。
    this.text = this.initialText;
    // 关闭系统默认整页键盘避让，改为自己按键盘高度上移输入条（背后页面不动）。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);

    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.winClass = win;
      const sysArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.bottomInset = px2vp(sysArea.bottomRect.height);
      // 内联挂载时 getLastWindow 即主窗口，键盘避让事件能稳定收到。
      win.on('avoidAreaChange', this.onAvoidAreaChange);
    }).catch(() => {
      // 拿不到 window 时退化为不偏移（输入条仍在底部），不影响输入本身。
    });
  }

  aboutToDisappear(): void {
    if (this.focusTimer >= 0) {
      clearTimeout(this.focusTimer);
      this.focusTimer = -1;
    }
    if (this.winClass) {
      this.winClass.off('avoidAreaChange', this.onAvoidAreaChange);
      this.winClass = undefined;
    }
    // 还原默认避让模式，避免影响后续其它页面的输入场景。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
  }

  private focusInput(): void {
    // 挂载后主动请求焦点弹出软键盘。
    this.focusTimer = setTimeout(() => {
      this.getUIContext().getFocusController().requestFocus(INPUT_FOCUS_ID);
    }, 200);
  }

  private showToast(message: string, duration: number): void {
    promptToast(this.getUIContext(), message, duration);
  }

  private trimmedLength(): number {
    return this.text.trim().length;
  }

  private overMaxChars(): boolean {
    return this.maxChars > NO_MAX_CHARS && this.trimmedLength() > this.maxChars;
  }

  // 超出上限时提示。不硬顶输入（硬顶会静默吞字，用户不知道发生了什么），改为让字打进来再告知，
  // 由发送按钮置灰 + submit() 兜底拦住提交。每次「由未超变超」才弹一次，连着多打不会刷屏。
  private warnIfOverMaxChars(): void {
    const over: boolean = this.overMaxChars();
    if (over && !this.wasOverMaxChars) {
      this.showToast(`最多 ${this.maxChars} 个字`, 1500);
    }
    this.wasOverMaxChars = over;
  }

  private canSubmit(): boolean {
    return !this.isSubmitting && this.trimmedLength() >= this.minChars && !this.overMaxChars();
  }

  private async submit(): Promise<void> {
    if (this.isSubmitting) {
      return;
    }
    const trimmed: string = this.text.trim();
    if (trimmed.length < this.minChars) {
      // 少于最短字数：提示还差多少字，不提交。
      const need: number = this.minChars - trimmed.length;
      this.showToast(`至少还需 ${need} 个字`, 1500);
      return;
    }
    if (this.overMaxChars()) {
      // 超出最长字数：提示需删掉多少字，不提交（服务端只会回不带原因的 422）。
      const over: number = trimmed.length - this.maxChars;
      this.showToast(`超出 ${over} 个字，最多 ${this.maxChars} 字`, 1500);
      return;
    }
    this.isSubmitting = true;
    const typingMs: number = this.firstTypeTimeMs > 0 ? Date.now() - this.firstTypeTimeMs : 0;
    const composerMs: number = this.appearTimeMs > 0 ? Date.now() - this.appearTimeMs : 0;
    let ok: boolean = false;
    try {
      ok = await this.onSubmit(trimmed, typingMs, composerMs);
    } catch (error) {
      ok = false;
    }
    this.isSubmitting = false;
    if (ok) {
      this.text = '';
      this.onClose();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 遮罩层：点输入条以外区域收起键盘并关闭浮层。淡入淡出统一挂在根 Stack 上（见下方），
      // 这里不单独设 transition —— 组件被 if 移除时只有最外层节点的退出动画会播放。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.onClose();
        })

      // 底部输入条：按键盘高度手动上移到键盘上方。
      Row({ space: 8 }) {
        // 圆角输入容器：内放多行输入框。内边距全部放到 TextArea 上，让光标离圆角足够远、
        // 竖向留足空间；clip(false) 杜绝子内容被圆角裁切。
        Column() {
          TextArea({ text: $$this.text, placeholder: this.placeholder })
            .id(INPUT_FOCUS_ID)
            .width('100%')
            .backgroundColor(Color.Transparent)
            // 光标离左侧圆角 12vp、上下各留 10vp，且 minHeight 44 让行盒明显大于光标高度。
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .fontSize(16)
            // 行高 24 + 上下 padding 各 10 = 44，正好等于 minHeight：
            // 单行时自然高度撑满最小高度，文字垂直居中（否则被 minHeight 拉高后文字贴顶）。
            .lineHeight(24)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .defaultFocus(true)
            .enterKeyType(EnterKeyType.NEW_LINE)
            .constraintSize({ minHeight: INPUT_MIN_HEIGHT, maxHeight: INPUT_MAX_HEIGHT })
            .onChange((value: string) => {
              if (this.firstTypeTimeMs === 0 && value.length > 0) {
                this.firstTypeTimeMs = Date.now();
              }
              // 实时上抛给页面暂存:关掉输入条时组件卸载,不上抛内容就没了。
              this.onTextChange(value);
              this.warnIfOverMaxChars();
            })
        }
        .layoutWeight(1)
        .backgroundColor($r('app.color.fill_subtle'))
        .borderRadius(8)
        .clip(false)

        // 展开按钮：仅普通回复显示（boost 短文本无需全屏编辑）。点击上抛当前文本，
        // 由页面关闭内联浮层、压入全屏 Markdown 编辑器无缝接续。
        if (this.showExpand) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
              .fontSize(20)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(40)
          .height(40)
          .backgroundColor($r('app.color.fill_subtle'))
          .onClick(() => {
            this.onExpand(this.text, this.keyboardHeight);
          })
        }

        // 回复按钮：圆形、蓝底。提交中显示白色 loading 转圈，否则显示白色 reply 图标。
        // 未达最短字数或提交中时降透明度提示不可用，重复点击由 submit() 内部拦截。
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          if (this.isSubmitting) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color('#FFFFFF')
          } else {
            FaIconView({
              icon: this.replyIcon(),
              color: '#FFFFFF',
              iconSize: 18
            })
          }
        }
        .width(40)
        .height(40)
        .backgroundColor(REPLY_BLUE)
        .opacity(this.canSubmit() ? 1 : 0.5)
        .onClick(() => {
          this.submit();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      // 键盘弹起：底部内边距只留 8（安全区被键盘遮住）；键盘收起：叠加底部安全区贴 Home 条之上。
      .padding({ left: 12, right: 12, top: 8, bottom: this.keyboardHeight > 0 ? 8 : 8 + this.bottomInset })
      .backgroundColor($r('app.color.surface_card'))
      .border({
        width: { top: 1 },
        color: $r('app.color.border')
      })
      // 一镜到底的源：整条底部输入栏（全宽）与全屏编辑器主面板同 id。放在整条 Row 而非左侧
      // 窄输入框上——宽度本就是满的，生长基本只有竖直方向（从底部整条向上长满全屏），不再从
      // 左下角斜着放大。boost 模式无目标，该 id 无配对、退化为普通渲染，无副作用。
      .geometryTransition(COMPOSER_GEOMETRY_ID, { follow: true })
      // 键盘弹起：整条上移键盘高度，正好贴到键盘上沿；键盘收起：回落到底部。
      // 上移动画由 onAvoidAreaChange 里的 animateTo 驱动（此处不挂 .animation，避免影响图标渲染）。
      .margin({ bottom: this.keyboardHeight })
      // 进场时从底部滑入（淡入淡出由根节点统一负责，这里只做位移，避免透明度叠加）。
      .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
        .animation({ duration: 220, curve: Curve.EaseOut }))
      .onAppear(() => {
        this.focusInput();
      })
    }
    .width('100%')
    .height('100%')
    // 整层淡入淡出：挂在根节点上，保证组件被 if 挂载/移除时进场与退场都播放动画（遮罩不再突兀）。
    .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
    // 扩展到全屏：配合页面切全屏布局，遮罩盖住状态栏、输入条贴到屏幕真实底部。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private replyIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('reply');
    return def ? def : { id: 'reply', rawfilePath: 'fa_icons/reply.svg' };
  }
}
