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
import { TopicCategory } from '../../models/Topic';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { getCategoryColor, getCategoryIcon, getCategoryLogo, getTagColor, getTagIcon, resolveBadgeAssetUrl } from '../components/TopicBadgeUtils';
import { FaIconDefinition, FaIconView } from '../components/FaIcon';
import { TagSuggestion, TopicService } from '../../services/topic/TopicService';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { DraftService, SaveTopicDraftInput } from '../../services/draft/DraftService';
import { DraftTagRef } from '../../models/Draft';
import { PostRichContent } from '../components/PostRichContent';
import { applyAction, EditState, MdAction } from '../../utils/markdownInsert';

const LOG_TAG: string = '[ArkDO][Composer]';
// 一次最多选图张数(对齐 Discourse composer 手感)。
const MAX_PICK: number = 9;
// 发帖最多可选标签数(对齐站点 max_tags_per_topic)。
const MAX_TAGS: number = 8;
// 自动存草稿防抖:停止输入这么久才真发一次(对齐官方 composer 的「边写边存」节奏)。
const DRAFT_SAVE_DEBOUNCE_MS: number = 2000;
// 编辑区焦点 id:内联挂载时 defaultFocus 不可靠(展开前内联输入条卸载会收键盘),挂载后
// 主动 requestFocus 把键盘弹回来,焦点无缝落到全屏编辑区。
const EDIT_FOCUS_ID: string = 'arkdoComposerInput';
// 标题输入焦点 id(仅发帖模式):发帖从标题写起,键盘首帧就弹给它。
const TITLE_FOCUS_ID: string = 'arkdoComposerTitle';
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

// 分类选择器一行的入参(@Builder 单对象约束)。
interface PickerRowParams {
  category: TopicCategory;
  parent: TopicCategory;
  isChild: boolean;
}

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
  // 正文变化时上抛(回帖模式用):详情页据此暂存未发出的内容并存服务端草稿——
  // 本页一关就卸载,不上抛内容就没了。发帖模式自己存草稿,不需要它。
  onTextChange: (text: string) => void = () => {};
  // 返回 true 表示提交成功(随即返回);false 保留内容供重试。typing/composer 时长对齐官方遥测。
  onSubmit: (raw: string, typingMs: number, composerMs: number) => Promise<boolean> =
    (raw: string, typingMs: number, composerMs: number) => Promise.resolve(false);

  // ===== 发新主题模式 =====
  // true=发新帖(多出标题输入 + 分类选择,走 onSubmitTopic);false=回帖(原样走 onSubmit)。
  // 用开关而非改 onSubmit 签名:回帖没有标题/分类,硬塞进同一个回调会让详情页那条链路凭空
  // 多两个恒为空的参数。
  composeTopic: boolean = false;
  // 全量分类(未筛)。选择器内部走 CategoryIndex 与侧边栏共用筛选/树,不在外部预筛。
  categories: TopicCategory[] = [];
  onSubmitTopic: (title: string, categoryId: number, raw: string, tags: string[], typingMs: number, composerMs: number) => Promise<boolean> =
    (title: string, categoryId: number, raw: string, tags: string[], typingMs: number, composerMs: number) => Promise.resolve(false);

  // ===== 草稿续写(从草稿页点进来时带入) =====
  // 非空=续写该草稿(自动存沿用同一 key/序号);空=新开一篇,首次保存时现生成 new_topic_<ts>。
  initialDraftKey: string = '';
  initialDraftSequence: number = 0;
  initialTitle: string = '';
  initialCategoryId: number = -1;
  initialTags: TagSuggestion[] = [];

  @State private title: string = '';
  // 已选分类 id;-1=未选(发送置灰)。
  @State private categoryId: number = -1;
  // 分类选择器(底部弹窗)开关。
  @State private categoryPickerVisible: boolean = false;
  // 树形选择器里当前展开的父版块 id;-1=全收起。单展开,与侧边栏手感一致。
  @State private expandedParentId: number = -1;
  // 底部浮层向下拖拽位移(vp);自绘浮层没有 bindSheet 的下拉关闭,靠这个跟手 + 松手判阈值。
  // 同时只开一个浮层,故两个面板共用此值。
  @State private sheetDragY: number = 0;

  // 选中分类的前导图标三件套,存 @State 直接驱动 chip 渲染。
  // 图标不用 FaIconView 而是内联 Image:FaIconView 是自定义组件、icon 是普通属性,chip 里复用同一
  // 实例时普通属性不随父级更新(只有 @Prop/@Link 才同步),换分类图标刷不上屏。内置 Image 直接读
  // @State 字符串则可靠重绘。selCatIconPath 空=无图标,退到 logo→兜底色点。
  @State private selCatIconPath: string = '';
  @State private selCatLogo: string = '';
  @State private selCatColor: string = '#999999';

  // 已选标签(发帖必选≥1)。标签隶属分类:换分类后清空重选。
  @State private selectedTags: TagSuggestion[] = [];
  // 标签选择器(底部弹窗)开关 + 搜索词 + 联想结果 + 加载态。
  @State private tagPickerVisible: boolean = false;
  @State private tagQuery: string = '';
  @State private tagResults: TagSuggestion[] = [];
  @State private tagLoading: boolean = false;
  // 联想请求防抖计时器句柄;输入停顿后才发一次,避免逐字打字狂发请求。
  private tagDebounceTimer: number = -1;
  // 本轮联想请求的序号:异步返回乱序时只认最后一发,防旧结果盖新结果。
  private tagQuerySeq: number = 0;

  // ===== 自动存草稿运行态 =====
  private draftService?: DraftService = undefined;
  // 当前草稿 key/序号。key 首次保存时惰性生成(new_topic_<ts>),续写时用带入的。
  private draftKey: string = '';
  private draftSequence: number = 0;
  private draftDebounceTimer: number = -1;
  // 有未落盘的改动。关闭时据此决定要不要补存一次。
  private draftDirty: boolean = false;
  // 一次只允许一个保存在途,避免并发把 sequence 写乱。
  private draftSaving: boolean = false;
  // 发表成功后置真:阻止收尾的补存把已删的草稿又写回来。
  private draftPublished: boolean = false;

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
      this.draftService = new DraftService(this.bridge);
    }
    // 草稿续写:把带入的标题/分类/标签灌进 @State,并沿用原草稿的 key/序号继续自动存。
    if (this.composeTopic) {
      this.title = this.initialTitle;
      this.categoryId = this.initialCategoryId;
      this.selectedTags = this.initialTags.slice();
      this.draftKey = this.initialDraftKey;
      this.draftSequence = this.initialDraftSequence;
      if (this.categoryId >= 0) {
        this.refreshSelectedCategoryVisual();
      }
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
    // 卸载时清掉未触发的防抖计时器,免得回调在页面已销毁后触碰 @State。
    if (this.tagDebounceTimer !== -1) {
      clearTimeout(this.tagDebounceTimer);
      this.tagDebounceTimer = -1;
    }
    // 关闭时补存一次:防抖还没到点就被关掉的话,这一下把内容兜住(「点左上角内容没了」的根治点)。
    // 已发表则不补(草稿刚被删,补存会把它又写回来)。请求不 await——页面这就销毁了,发出去即可。
    if (this.draftDebounceTimer !== -1) {
      clearTimeout(this.draftDebounceTimer);
      this.draftDebounceTimer = -1;
    }
    if (this.composeTopic && this.draftDirty && !this.draftPublished) {
      this.saveDraftNow();
    }
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
    if (this.isSubmitting || this.trimmedLength() < this.minChars) {
      return false;
    }
    // 发帖还得有标题、选了分类、至少一个标签。标题的长度下限不在本地猜(站点 min_topic_title_length
    // 未知,猜严了会误伤合法标题),只拦空;真不够长由服务端报错原文告知。
    if (this.composeTopic) {
      return this.title.trim().length > 0 && this.categoryId >= 0 && this.selectedTags.length > 0;
    }
    return true;
  }

  // 发送按钮置灰时点它:说清楚缺什么,而不是毫无反应。
  private explainBlockedSubmit(): void {
    if (this.composeTopic && this.title.trim().length === 0) {
      this.showToast('还没写标题');
      return;
    }
    if (this.composeTopic && this.categoryId < 0) {
      this.showToast('还没选分类');
      return;
    }
    if (this.composeTopic && this.selectedTags.length === 0) {
      this.showToast('至少选一个标签');
      return;
    }
    if (this.trimmedLength() < this.minChars) {
      this.showToast(`至少还需 ${this.minChars - this.trimmedLength()} 个字`);
    }
  }

  private selectedCategoryName(): string {
    const hit: TopicCategory | undefined = this.categories.find((c: TopicCategory) => c.id === this.categoryId);
    return hit ? hit.name : '选择分类';
  }

  // 选中分类变化后,把前导图标三件套算好写进 @State(与选择器/侧边栏同一套 TopicBadgeUtils)。
  // 走 @State 而非 chip 里方法调用:见 selCatIcon 字段处注释(方法调用藏依赖,图标不更新)。
  private refreshSelectedCategoryVisual(): void {
    const cat: TopicCategory | undefined = this.categories.find((c: TopicCategory) => c.id === this.categoryId);
    if (!cat) {
      this.selCatIconPath = '';
      this.selCatLogo = '';
      this.selCatColor = '#999999';
      return;
    }
    const parent: TopicCategory | undefined = cat.parentCategoryId !== undefined
      ? this.categories.find((c: TopicCategory) => c.id === cat.parentCategoryId)
      : undefined;
    const icon: FaIconDefinition | undefined = getCategoryIcon(cat, parent);
    this.selCatIconPath = icon ? icon.rawfilePath : '';
    this.selCatLogo = getCategoryLogo(cat, parent);
    this.selCatColor = getCategoryColor(cat);
  }

  private isTagSelected(id: number): boolean {
    return this.selectedTags.some((t: TagSuggestion) => t.id === id);
  }

  // ==================== 自动存草稿 ====================
  // 对齐官方 composer:边写边存,关闭不提示也不丢;下次从「我的草稿」点回来继续写。

  // 内容有实质东西才值得存,免得开一下就关也留一条空草稿。
  private draftHasContent(): boolean {
    return this.title.trim().length > 0 || this.text.trim().length > 0;
  }

  // 任一可存字段变化时调用:标脏 + 防抖排一次保存(停止输入 DRAFT_SAVE_DEBOUNCE_MS 后才真发)。
  private scheduleDraftSave(): void {
    if (!this.composeTopic || this.draftPublished) {
      return;
    }
    this.draftDirty = true;
    if (this.draftDebounceTimer !== -1) {
      clearTimeout(this.draftDebounceTimer);
    }
    this.draftDebounceTimer = setTimeout(() => {
      this.draftDebounceTimer = -1;
      this.saveDraftNow();
    }, DRAFT_SAVE_DEBOUNCE_MS);
  }

  private async saveDraftNow(): Promise<void> {
    if (!this.draftService || !this.composeTopic || this.draftPublished) {
      return;
    }
    if (!this.draftHasContent()) {
      return;
    }
    // 已有保存在途:标记仍脏,等它回来后由收尾逻辑或下次输入再补。
    if (this.draftSaving) {
      return;
    }
    // 首次保存现生成 key(对齐官方 new_topic_<毫秒时间戳>)。
    if (this.draftKey.length === 0) {
      this.draftKey = `new_topic_${Date.now()}`;
    }
    this.draftSaving = true;
    this.draftDirty = false;

    const tags: DraftTagRef[] = this.selectedTags.map((t: TagSuggestion): DraftTagRef => {
      const ref: DraftTagRef = { id: t.id, name: t.name };
      return ref;
    });
    const input: SaveTopicDraftInput = {
      draftKey: this.draftKey,
      sequence: this.draftSequence,
      title: this.title.trim(),
      categoryId: this.categoryId,
      tags: tags,
      reply: this.text,
      composerTimeMs: this.appearTimeMs > 0 ? Date.now() - this.appearTimeMs : 0,
      typingTimeMs: this.firstTypeTimeMs > 0 ? Date.now() - this.firstTypeTimeMs : 0
    };
    const result: NetworkResult<number> = await this.draftService.saveTopicDraft(input);
    this.draftSaving = false;
    if (result.success && result.data !== undefined) {
      // 服务端回的序号是下次该带的,存回去,否则下次保存会因序号过期被拒。
      this.draftSequence = result.data;
      Log.i(`${LOG_TAG} draft saved key=${this.draftKey} seq=${this.draftSequence}`);
    } else {
      // 存失败不打扰用户(草稿是兜底能力),标回脏,下次输入或关闭时再试。
      this.draftDirty = true;
      Log.i(`${LOG_TAG} draft save failed status=${result.statusCode}`);
    }
  }

  // 发表成功后删掉对应草稿,否则已发出的帖子还会在草稿列表里挂着。
  private async deleteDraftAfterPublish(): Promise<void> {
    this.draftPublished = true;
    if (this.draftDebounceTimer !== -1) {
      clearTimeout(this.draftDebounceTimer);
      this.draftDebounceTimer = -1;
    }
    if (!this.draftService || this.draftKey.length === 0) {
      return;
    }
    await this.draftService.deleteDraft(this.draftKey, this.draftSequence);
    Log.i(`${LOG_TAG} draft deleted after publish key=${this.draftKey}`);
  }

  // 打开标签选择器:清空搜索词,立刻拉一遍热门标签(q 为空)。
  private openTagPicker(): void {
    this.tagQuery = '';
    this.tagResults = [];
    this.sheetDragY = 0;
    this.tagPickerVisible = true;
    this.fetchTags('');
  }

  // 搜索词变化:防抖 250ms 再查(输入停顿才发一次,避免逐字狂发)。
  private onTagQueryChanged(value: string): void {
    if (this.tagDebounceTimer !== -1) {
      clearTimeout(this.tagDebounceTimer);
    }
    this.tagDebounceTimer = setTimeout(() => {
      this.tagDebounceTimer = -1;
      this.fetchTags(value.trim());
    }, 250);
  }

  private async fetchTags(query: string): Promise<void> {
    if (!this.bridge || this.categoryId < 0) {
      return;
    }
    const seq: number = ++this.tagQuerySeq;
    this.tagLoading = true;
    const selectedIds: number[] = this.selectedTags.map((t: TagSuggestion) => t.id);
    const result: NetworkResult<TagSuggestion[]> = await new TopicService(this.bridge)
      .searchTags(this.categoryId, query, selectedIds);
    // 只认最后一发:防慢请求的旧结果盖掉新结果。
    if (seq !== this.tagQuerySeq) {
      return;
    }
    this.tagLoading = false;
    this.tagResults = result.success && result.data ? result.data : [];
  }

  // 选/取消一个标签。选中后重查(带上新 selected_tag_ids,把已选项从联想里排除并 refine)。
  private toggleTag(tag: TagSuggestion): void {
    if (this.isTagSelected(tag.id)) {
      this.selectedTags = this.selectedTags.filter((t: TagSuggestion) => t.id !== tag.id);
    } else {
      // 已达上限:不再加,提示。取消已选不受限,故只在新增分支拦。
      if (this.selectedTags.length >= MAX_TAGS) {
        this.showToast(`最多选 ${MAX_TAGS} 个标签`);
        return;
      }
      this.selectedTags = this.selectedTags.concat(tag);
    }
    this.scheduleDraftSave();
    this.fetchTags(this.tagQuery.trim());
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
      // 先补齐「本会话没上传过」的 upload:// 短码映射(草稿续写/编辑旧帖里的老图片),
      // 否则它们在预览里换不出真实直链、图片显示不出来。
      if (this.uploadService) {
        await this.uploadService.prefetchShortUrls(this.text);
      }
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
      this.explainBlockedSubmit();
      return;
    }
    this.isSubmitting = true;
    const typingMs: number = this.firstTypeTimeMs > 0 ? Date.now() - this.firstTypeTimeMs : 0;
    const composerMs: number = this.appearTimeMs > 0 ? Date.now() - this.appearTimeMs : 0;
    let ok: boolean = false;
    try {
      ok = this.composeTopic
        ? await this.onSubmitTopic(this.title.trim(), this.categoryId, this.text.trim(), this.selectedTags.map((t: TagSuggestion) => t.name), typingMs, composerMs)
        : await this.onSubmit(this.text.trim(), typingMs, composerMs);
    } catch (error) {
      ok = false;
    }
    this.isSubmitting = false;
    if (ok) {
      // 已发出:删掉对应草稿,免得草稿列表里留一条已发布的。失败不拦关闭(草稿残留可手动删)。
      if (this.composeTopic) {
        await this.deleteDraftAfterPublish();
      }
      this.onBack();
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.Header()
        // 发帖模式:标题 + 分类。预览态藏起来——预览是看正文成品的,标题栏杵在那儿只是干扰。
        if (this.composeTopic && this.mode === ComposerMode.Edit) {
          this.TopicMetaBar()
        }
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

      // 分类 / 标签选择器:自绘底部浮层,不用 bindSheet。
      // 原因:bindSheet 的入场动画会被本页手动键盘避让触发的全局 animateTo 打断(收键盘那一下),
      // 表现为「弹窗一闪就没、键盘收了又弹」。自绘浮层由 if + transition 驱动,不吃这套竞态。
      // 内容必须直接调用无参 @Builder(读 this.xxx)——@Builder 按值参数传 content 不随 @State 重绘,
      // 标签联想结果会刷不上屏,故两个浮层各自展开写,不抽 content 参数。
      if (this.categoryPickerVisible) {
        Stack({ alignContent: Alignment.Bottom }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#66000000')
            .onClick(() => { this.closeSheet(1); })

          Column() {
            this.SheetHeader('选择分类', 1)
            Column() {
              this.CategoryPickerSheet()
            }
            .layoutWeight(1)
            .width('100%')
          }
          .width('100%')
          .height('66%')
          .backgroundColor($r('app.color.page_bg'))
          .borderRadius({ topLeft: 20, topRight: 20 })
          .padding({ bottom: this.sysBottomInset })
          .clip(true)
          .translate({ y: this.sheetDragY })
          .transition(TransitionEffect.move(TransitionEdge.BOTTOM).combine(TransitionEffect.OPACITY)
            .animation({ duration: 240, curve: Curve.EaseOut }))
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      }

      if (this.tagPickerVisible) {
        Stack({ alignContent: Alignment.Bottom }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#66000000')
            .onClick(() => { this.closeSheet(2); })

          Column() {
            this.SheetHeader('选择标签', 2)
            Column() {
              this.TagPickerSheet()
            }
            .layoutWeight(1)
            .width('100%')
          }
          .width('100%')
          .height('80%')
          .backgroundColor($r('app.color.page_bg'))
          .borderRadius({ topLeft: 20, topRight: 20 })
          .padding({ bottom: this.sysBottomInset })
          .clip(true)
          .translate({ y: this.sheetDragY })
          .transition(TransitionEffect.move(TransitionEdge.BOTTOM).combine(TransitionEffect.OPACITY)
            .animation({ duration: 240, curve: Curve.EaseOut }))
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    // 根 Stack 透明:一镜到底期间生长面板之外露出背后详情页(面板全开时自身 page_bg 盖满)。
  }

  // 关闭指定浮层并复位拖拽位移。which:1=分类 2=标签。
  private closeSheet(which: number): void {
    if (which === 1) {
      this.categoryPickerVisible = false;
    } else {
      this.tagPickerVisible = false;
    }
    this.sheetDragY = 0;
  }

  // 浮层顶部:抓手条 + 标题 + 关闭按钮。which:1=分类 2=标签(值参数静态,不涉重绘)。
  // 整个头部区域可竖向拖拽关闭(bindSheet 自带的下拉关闭在自绘浮层里没有,手动补):
  // 手势只挂头部、不挂内容,避免跟内部列表滚动抢竖向手势。
  @Builder
  private SheetHeader(title: string, which: number) {
    Column() {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.border'))
        .margin({ top: 8, bottom: 4 })

      Row() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
        .width(32)
        .height(32)
        .backgroundColor($r('app.color.surface_muted'))
        .onClick(() => {
          this.closeSheet(which);
        })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 4, bottom: 8 })
    }
    .width('100%')
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 5 })
        .onActionUpdate((event: GestureEvent) => {
          // 只跟向下拖(≥0),向上不拉伸。
          this.sheetDragY = Math.max(0, event.offsetY);
        })
        .onActionEnd((event: GestureEvent) => {
          // 拖过 90vp 或向下甩得够快就关,否则弹回原位。
          if (this.sheetDragY > 90 || event.velocityY > 800) {
            this.closeSheet(which);
          } else {
            this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
              this.sheetDragY = 0;
            });
          }
        })
        .onActionCancel(() => {
          this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
            this.sheetDragY = 0;
          });
        })
    )
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

  // 发帖专属:标题输入 + 分类选择,通栏发丝线与正文分组(对齐项目的鸿蒙清爽风,不套卡片)。
  @Builder
  private TopicMetaBar() {
    Column() {
      // 不硬设 height:TextInput 自身 padding 被外层固定高压死会把光标上下切掉(项目既有坑),
      // 故只给上下 padding 撑开。
      TextInput({ text: $$this.title, placeholder: '标题' })
        .id(TITLE_FOCUS_ID)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .enterKeyType(EnterKeyType.Next)
        .onChange((value: string) => {
          // 标题也算"开始写了":遥测的 typing 起点不该只认正文。
          if (this.firstTypeTimeMs === 0 && value.length > 0) {
            this.firstTypeTimeMs = Date.now();
          }
          this.scheduleDraftSave();
        })
        // 挂载即抢焦点:发帖从标题写起,键盘直接弹给标题。
        .onAppear(() => {
          this.getUIContext().getFocusController().requestFocus(TITLE_FOCUS_ID);
        })

      // 分类 chip + 已选标签 chips + 「加标签」按钮,一行放不下自动换行。
      // 间距一律用右边距+下边距(不用左边距):首列无前导边距→换行后各行左对齐;下边距→撑出行间距。
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        this.CategoryChip()

        ForEach(this.selectedTags, (tag: TagSuggestion) => {
          this.SelectedTagChip(tag)
        }, (tag: TagSuggestion) => `t${tag.id}`)

        this.AddTagChip()
      }
      .width('100%')
      // 底 padding 调小:每个 chip 自带 bottom:8,末行已有下缝,这里只补一点点。
      .padding({ left: 16, right: 16, bottom: 2 })

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))
    }
    .width('100%')
  }

  // 已选标签 chip:点 × 移除。
  @Builder
  private SelectedTagChip(tag: TagSuggestion) {
    Row() {
      // 有映射图标的标签带上图标(与首页/联想列表一致)。
      if (getTagIcon(tag.name)) {
        FaIconView({ icon: getTagIcon(tag.name) as FaIconDefinition, color: getTagColor(tag.name), iconSize: 12 })
          .margin({ right: 5 })
      }
      Text(tag.name)
        .fontSize(13)
        .fontColor($r('app.color.brand'))

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(11)
        .fontColor([$r('app.color.brand')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .margin({ left: 5 })
    }
    .padding({ left: 10, right: 9, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.info_soft_bg'))
    .borderRadius(14)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      this.selectedTags = this.selectedTags.filter((t: TagSuggestion) => t.id !== tag.id);
      this.scheduleDraftSave();
    })
  }

  // 「加标签」按钮:未选分类时禁用(标签隶属分类,没分类无从查起)。
  @Builder
  private AddTagChip() {
    Row() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(12)
        .fontColor([this.categoryId >= 0 ? $r('app.color.text_body') : $r('app.color.text_tertiary')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      Text(this.selectedTags.length > 0 ? '标签' : '添加标签')
        .fontSize(13)
        .fontColor(this.categoryId >= 0 ? $r('app.color.text_body') : $r('app.color.text_tertiary'))
        .margin({ left: 4 })
    }
    .padding({ left: 10, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(14)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      if (this.categoryId < 0) {
        this.showToast('请先选择分类');
        return;
      }
      if (this.selectedTags.length >= MAX_TAGS) {
        this.showToast(`最多选 ${MAX_TAGS} 个标签`);
        return;
      }
      try {
        inputMethod.getController().stopInputSession();
      } catch (err) {
      }
      this.openTagPicker();
    })
  }

  @Builder
  private CategoryChip() {
    Row() {
      // 选中后带上该分类图标(图标→上传 logo→兜底色点),与选择器/侧边栏一致。
      // 图标内联 Image(而非 FaIconView),内置组件直接读 @State 才会随换分类重绘,见字段处注释。
      if (this.categoryId >= 0) {
        if (this.selCatIconPath.length > 0) {
          Image($rawfile(this.selCatIconPath))
            .objectFit(ImageFit.Contain)
            .renderMode(ImageRenderMode.Template)
            .fillColor(this.selCatColor)
            .draggable(false)
            .width(13)
            .height(13)
            .margin({ right: 6 })
        } else if (this.selCatLogo.length > 0) {
          Image(resolveBadgeAssetUrl(this.selCatLogo))
            .width(13)
            .height(13)
            .objectFit(ImageFit.Contain)
            .margin({ right: 6 })
        } else {
          Circle()
            .width(9)
            .height(9)
            .fill(this.selCatColor)
            .margin({ right: 6 })
        }
      }

      Text(this.selectedCategoryName())
        .fontSize(13)
        .fontColor(this.categoryId >= 0 ? $r('app.color.text_body') : $r('app.color.text_tertiary'))

      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(11)
        .fontColor([$r('app.color.icon_secondary')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .margin({ left: 5 })
    }
    .padding({ left: 12, right: 10, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(14)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      // 开选择器前先收键盘:底部弹窗与键盘抢占底部空间,不收会打架。
      try {
        inputMethod.getController().stopInputSession();
      } catch (err) {
      }
      // 弹窗一开就展开相关父级:选中的是子版块→展开其父;选中的是有子版块的父→展开它自身
      // (方便直接改选到它的子版块);否则收起。
      const selected: TopicCategory | undefined = this.categories.find((c: TopicCategory) => c.id === this.categoryId);
      if (selected && selected.parentCategoryId !== undefined) {
        this.expandedParentId = selected.parentCategoryId;
      } else if (selected && CategoryIndex.hasChildren(this.categories, selected.id)) {
        this.expandedParentId = selected.id;
      } else {
        this.expandedParentId = -1;
      }
      this.sheetDragY = 0;
      this.categoryPickerVisible = true;
    })
  }

  // 分类选择器:与侧边栏共用 CategoryIndex 的筛选与父子树,看到的版块集合、层级、图标全一致。
  // 用底部弹窗承载(发帖是全屏浮层,再嵌树用 bindSheet 最稳);选中即关。
  // 标题/关闭由外层 SheetHeader 承担,这里只出内容。
  @Builder
  private CategoryPickerSheet() {
    Column() {
      Scroll() {
        Column() {
          ForEach(CategoryIndex.topLevelCategories(this.categories), (top: TopicCategory) => {
            this.PickerRow({ category: top, parent: top, isChild: false })
            if (this.expandedParentId === top.id) {
              ForEach(CategoryIndex.childrenOf(this.categories, top.id), (child: TopicCategory) => {
                this.PickerRow({ category: child, parent: top, isChild: true })
              }, (child: TopicCategory) => `c${child.id}`)
            }
          }, (top: TopicCategory) => `p${top.id}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // Scroll 内容不足一屏时默认竖直居中——版块少时会飘到中间,强制顶对齐。
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 4, right: 4 })
  }

  // 标签选择器:搜索框 + 联想列表(多选,点行加/减)。标签隶属分类,查询必带 categoryId。
  // 逐次选择都重查(带 selected_tag_ids refine),对齐官方 composer。
  // 标题/关闭由外层 SheetHeader 承担,这里只出内容。
  @Builder
  private TagPickerSheet() {
    Column() {
      // 搜索框:输入即防抖联想。
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(15)
          .fontColor([$r('app.color.text_tertiary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .margin({ right: 8 })
        TextInput({ text: $$this.tagQuery, placeholder: '搜索标签' })
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          // TextInput 默认自带较大左内边距,会把文字推离放大镜;显式清零让文字紧贴图标。
          .padding({ left: 0, right: 0, top: 8, bottom: 8 })
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .onChange((value: string) => {
            this.onTagQueryChanged(value);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 14 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(10)
      .margin({ bottom: 8 })

      Scroll() {
        Column() {
          if (this.tagLoading && this.tagResults.length === 0) {
            Row() {
              LoadingProgress().width(20).height(20).color($r('app.color.brand'))
            }
            .width('100%')
            .height(80)
            .justifyContent(FlexAlign.Center)
          } else if (this.tagResults.length === 0) {
            Text(this.tagQuery.length > 0 ? '没有匹配的标签' : '该分类下暂无可选标签')
              .fontSize(14)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 28, bottom: 28 })
          } else {
            ForEach(this.tagResults, (tag: TagSuggestion) => {
              this.TagResultRow(tag)
            }, (tag: TagSuggestion) => `r${tag.id}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder
  private TagResultRow(tag: TagSuggestion) {
    Row() {
      // 标签图标:按标签名映射(getTagIcon,与首页帖子列表标签同一套);无映射的标签不出图标。
      if (getTagIcon(tag.name)) {
        FaIconView({ icon: getTagIcon(tag.name) as FaIconDefinition, color: getTagColor(tag.name), iconSize: 14 })
          .margin({ right: 8 })
      }
      Column() {
        Row() {
          Text(tag.name)
            .fontSize(15)
            .fontColor(this.isTagSelected(tag.id) ? $r('app.color.brand') : $r('app.color.text_primary'))
            .fontWeight(this.isTagSelected(tag.id) ? FontWeight.Medium : FontWeight.Regular)
          Text(`×${tag.count}`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 8 })
        }
        if (tag.description !== undefined && tag.description.length > 0) {
          Text(tag.description)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isTagSelected(tag.id)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([$r('app.color.brand')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 11, bottom: 11 })
    .onClick(() => {
      this.toggleTag(tag);
    })
  }

  // 选择器里的一行版块。有子版块的父行:点箭头只展开/收起,点名字才选中该父版块
  // (对齐侧边栏——父版块本身也可发帖,箭头是独立热区)。
  // @Builder 只接单个对象参数(多位置参数会报 Argument name clash),故走 PickerRowParams。
  @Builder
  private PickerRow(p: PickerRowParams) {
    Row() {
      Row() {
        if (getCategoryIcon(p.category, p.parent)) {
          FaIconView({ icon: getCategoryIcon(p.category, p.parent) as FaIconDefinition, color: getCategoryColor(p.category), iconSize: 15 })
        } else if (getCategoryLogo(p.category, p.parent).length > 0) {
          Image(resolveBadgeAssetUrl(getCategoryLogo(p.category, p.parent)))
            .width(15)
            .height(15)
            .objectFit(ImageFit.Contain)
        } else {
          Circle().width(11).height(11).fill(getCategoryColor(p.category))
        }
      }
      .width(18)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 10 })

      Text(p.category.name)
        .fontSize(p.isChild ? 14 : 15)
        .fontWeight(this.categoryId === p.category.id ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.categoryId === p.category.id ? $r('app.color.brand') : $r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 选中打勾;箭头独立于选中态——父版块被选中后仍能展开去改选它的子版块(勾与箭头可并存)。
      if (this.categoryId === p.category.id) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([$r('app.color.brand')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .margin({ left: 6, right: p.isChild || !CategoryIndex.hasChildren(this.categories, p.category.id) ? 4 : 0 })
      }
      if (!p.isChild && CategoryIndex.hasChildren(this.categories, p.category.id)) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.text_faint')])
            .rotate({ angle: this.expandedParentId === p.category.id ? 90 : 0 })
        }
        .height('100%')
        .width(52)
        .margin({ right: -12 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          // 单展开:点已展开的父收起,否则切到它。
          this.expandedParentId = this.expandedParentId === p.category.id ? -1 : p.category.id;
        })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: p.isChild ? 30 : 14, right: 14 })
    .backgroundColor(this.categoryId === p.category.id ? $r('app.color.surface_muted') : Color.Transparent)
    .onClick(() => {
      // 换了分类:已选标签隶属旧分类,清空重选(标签集随分类变)。
      if (this.categoryId !== p.category.id) {
        this.selectedTags = [];
      }
      this.categoryId = p.category.id;
      this.refreshSelectedCategoryVisual();
      this.categoryPickerVisible = false;
      this.scheduleDraftSave();
    })
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
            this.onTextChange(value);
            this.scheduleDraftSave();
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
            // 发帖模式焦点归标题(先写标题才顺),这里让开——否则正文会把标题刚抢到的焦点夺走。
            if (this.composeTopic) {
              return;
            }
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
