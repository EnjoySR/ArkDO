import { Log } from '../../services/logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { Draft, DraftAction, DraftPage, DraftTagRef } from '../../models/Draft';
import { TopicCategory } from '../../models/Topic';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { DraftService } from '../../services/draft/DraftService';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { CreateTopicOutcome, TagSuggestion, TopicService } from '../../services/topic/TopicService';
import { JsonNetworkClient, NetworkResult } from '../../services/network/NetworkTypes';
import { LoadStateView } from '../components/LoadStateView';
import { ComposerPage } from './ComposerPage';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';

const LOG_TAG: string = '[ArkDO][DraftsPage]';
const PAGE_PADDING: number = 16;
// 草稿变更后延这么久再重拉:给「卸载时补存 / 防抖保存」这类在飞的写请求留出落地时间,
// 顺带错开并发(与写请求同时打请求层容易撞出异常)。略大于关闭动画 220ms。
const DRAFT_REFRESH_DELAY_MS: number = 320;
// 草稿页续写浮层的可见态 + 返回键信号:浮层内联挂在本页根 Stack,不进 Navigation 栈,
// 返回键须由本页所在 NavDestination.onBackPressed 拦截(RootTabPage 里接)。
export const DRAFTS_COMPOSER_VISIBLE_KEY: string = 'draftsComposerVisible';
export const DRAFTS_COMPOSER_BACK_TICK_KEY: string = 'draftsComposerBackTick';
// 本页重新可见时自增(RootTabPage 在 NavDestination.onShown 里 bump),用于重新拉草稿列表:
// 从帖子详情续写并发表后草稿已在服务端删除,不重拉的话返回时列表里还挂着那条。
export const DRAFTS_REFRESH_TICK_KEY: string = 'draftsRefreshTick';

@Component
export struct DraftsPage {
  // 窗口常驻全屏布局:根列自行避让状态栏(padding 在带背景的根列上,背景填满状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: JsonNetworkClient | undefined = undefined;
  isArkWebReady: boolean = false;
  username: string = '';
  onBack: () => void = () => {};
  // 回帖草稿 → 进对应主题的原生详情页。
  onOpenTopic: (topicId: number, title: string) => void = () => {};
  // 回帖草稿续写 → 进主题详情并自动弹回复框、回填草稿正文;发表成功后详情页据 key/序号删该草稿。
  onOpenTopicWithDraft: (topicId: number, title: string, draftReply: string, draftKey: string, sequence: number) => void = () => {};
  // 新主题/私信草稿暂无原生续写 → 兜底走站内 Web 草稿页。
  onOpenWeb: (url: string, title: string) => void = () => {};

  @State private drafts: Draft[] = [];
  @State private isInitialLoading: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = true;
  @State private loadFailed: boolean = false;
  @State private message: string = '';
  private service?: DraftService = undefined;
  private pageOffset: number = 0;
  private loading: boolean = false;

  // ===== 新主题草稿续写浮层 =====
  @State private showComposer: boolean = false;
  @State private categories: TopicCategory[] = [];
  // 续写带入 ComposerPage 的初始值(点某条草稿时填好)。
  @State private resumeDraftKey: string = '';
  @State private resumeSequence: number = 0;
  @State private resumeTitle: string = '';
  @State private resumeCategoryId: number = -1;
  @State private resumeTags: TagSuggestion[] = [];
  @State private resumeText: string = '';
  // 返回键信号镜像:RootTabPage 在浮层可见时 bump,本页 @Watch 接住关闭。
  @StorageProp(DRAFTS_COMPOSER_BACK_TICK_KEY) @Watch('onComposerBackTick') private composerBackTick: number = 0;
  // 本页重新可见的信号:每次 onShown 都会 bump。首次显示要跳过(aboutToAppear 已加载过一遍)。
  @StorageProp(DRAFTS_REFRESH_TICK_KEY) @Watch('onRefreshTick') private refreshTick: number = 0;
  private shownOnce: boolean = false;
  // 延迟重拉的计时器句柄(refreshAfterDraftChange 用,重复触发只留最后一次)。
  private refreshTimer: number = -1;
  private categoryIndex: CategoryIndex = new CategoryIndex();

  aboutToAppear(): void {
    if (this.bridge) {
      this.service = new DraftService(this.bridge);
    }
    this.loadCategories();
    this.loadInitial();
  }

  aboutToDisappear(): void {
    // 清掉未触发的延迟重拉,免得回调在页面已销毁后触碰 @State。
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  build() {
    // 根 Stack:列表在底,续写浮层盖在上面(与首页发帖浮层同路子)。
    Stack({ alignContent: Alignment.TopStart }) {
      this.ListRoot()

      if (this.showComposer) {
        ComposerPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          headerTitle: '继续编辑',
          placeholder: '正文（支持 Markdown）',
          minChars: 1,
          composeTopic: true,
          categories: this.categories,
          initialText: this.resumeText,
          initialDraftKey: this.resumeDraftKey,
          initialDraftSequence: this.resumeSequence,
          initialTitle: this.resumeTitle,
          initialCategoryId: this.resumeCategoryId,
          initialTags: this.resumeTags,
          onBack: () => {
            this.closeComposer();
          },
          onSubmitTopic: (title: string, categoryId: number, raw: string, tags: string[], typingMs: number, composerMs: number): Promise<boolean> => {
            return this.submitResumedTopic(title, categoryId, raw, tags, typingMs, composerMs);
          }
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ListRoot() {
    Column() {
      // 顶栏
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(28)
            .fontColor([$r('app.color.text_primary')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.surface_muted'))
        .onClick(() => {
          this.onBack();
        })

        Text('我的草稿')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.drafts.length > 0) {
          Text(`${this.drafts.length}`)
            .fontSize(14)
            .fontColor($r('app.color.text_faint'))
            .padding({ right: 8 })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 8 })

      this.Content()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.sysTopInset })
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private Content() {
    if (this.drafts.length === 0) {
      LoadStateView({
        isLoading: this.isInitialLoading,
        loadingText: '加载中…',
        message: this.message.length > 0 ? this.message : '草稿加载失败',
        showRetry: this.loadFailed,
        emptyIcon: $r('sys.symbol.square_and_pencil'),
        emptyTitle: '还没有草稿',
        emptySubtitle: '编辑帖子时会自动存草稿，没写完也不怕丢',
        onRetry: () => {
          this.loadInitial();
        }
      })
    } else {
      Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
        List() {
          ForEach(this.drafts, (item: Draft) => {
            ListItem() {
              this.DraftRow(item)
            }
          }, (item: Draft) => `${item.draftKey}_${item.sequence}`)

          ListItem() {
            Row() {
              if (this.isLoadingMore) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color($r('app.color.ld_accent'))
                  .margin({ right: 8 })
              }
              Text(this.hasMore ? '上拉加载更多' : '没有更多了')
                .fontSize(13)
                .fontColor($r('app.color.text_faint'))
            }
            .width('100%')
            .height(54)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.border'), startMargin: 0, endMargin: 0 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onReachEnd(() => {
          this.loadMore();
        })
      }
      .layoutWeight(1)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onRefreshing(() => {
        this.loadInitial();
      })
    }
  }

  @Builder
  private DraftRow(item: Draft) {
    Column() {
      // 类型标签 + 相对时间
      Row() {
        Text(this.actionLabel(item.action))
          .fontSize(11)
          .fontColor($r('app.color.ld_accent'))
          .backgroundColor($r('app.color.info_soft_bg'))
          .borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })

        Text(RelativeTime.fromNow(item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .layoutWeight(1)
          .margin({ left: 8 })
          .maxLines(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 标题
      Text(item.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 8 })

      // 正文预览
      if (item.excerpt.length > 0) {
        Text(item.excerpt)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 12, bottom: 13 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openDraft(item);
    })
  }

  private actionLabel(action: DraftAction): string {
    if (action === DraftAction.NEW_TOPIC) {
      return '主题';
    }
    if (action === DraftAction.REPLY) {
      return '回帖';
    }
    if (action === DraftAction.PRIVATE_MESSAGE) {
      return '私信';
    }
    return '草稿';
  }

  // 点击分流:新主题草稿→原生续写浮层;回帖草稿→进对应主题;私信草稿无原生编辑器,兜底跳 Web。
  private openDraft(item: Draft): void {
    if (item.action === DraftAction.NEW_TOPIC) {
      this.openComposerForDraft(item);
      return;
    }
    if (item.action === DraftAction.REPLY && item.topicId !== undefined) {
      // 带上草稿正文:落地后详情页自动弹回复框并回填,不用用户再点一次「回复」。
      this.onOpenTopicWithDraft(item.topicId, item.title, item.reply, item.draftKey, item.sequence);
      return;
    }
    const path: string = this.username.length > 0 ? `/u/${this.username}/activity/drafts` : '/my/activity/drafts';
    this.onOpenWeb(`${AppConstants.BASE_URL}${path}`, '我的草稿');
  }

  // ==================== 续写浮层 ====================

  private openComposerForDraft(item: Draft): void {
    this.resumeDraftKey = item.draftKey;
    this.resumeSequence = item.sequence;
    this.resumeTitle = item.title;
    this.resumeCategoryId = item.categoryId !== undefined ? item.categoryId : -1;
    this.resumeText = item.reply;
    // 草稿里的标签只有 id/name;联想项还要 text/count,这里补齐够用的最小结构。
    this.resumeTags = item.tags.map((t: DraftTagRef): TagSuggestion => {
      const suggestion: TagSuggestion = { id: t.id, name: t.name, text: t.name, count: 0 };
      return suggestion;
    });
    AppStorage.setOrCreate(DRAFTS_COMPOSER_VISIBLE_KEY, true);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.showComposer = true;
    });
  }

  private closeComposer(): void {
    AppStorage.setOrCreate(DRAFTS_COMPOSER_VISIBLE_KEY, false);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.showComposer = false;
    });
    // 关闭续写浮层后刷新(草稿可能被自动存过或已发表删除)。
    this.refreshAfterDraftChange();
  }

  // 本页重新可见:重拉列表。首次显示跳过——aboutToAppear 刚加载过,不跳会白拉一次。
  // 主要为了修「从帖子续写发表后返回,已删的草稿还挂在列表里」。
  private onRefreshTick(): void {
    if (!this.shownOnce) {
      this.shownOnce = true;
      return;
    }
    this.refreshAfterDraftChange();
  }

  // 「草稿可能刚变过,重拉一次」的统一入口。两个触发点共用:
  //   ① 关闭本页的续写浮层(浮层在本页内,不产生页面可见性变化,onShown 不会触发)
  //   ② 从帖子详情 pop 回来(NavDestination.onShown)
  // 都要延一小下再拉:两条路都可能有 fire-and-forget 的草稿保存还在飞(ComposerPage 卸载补存 /
  // 详情页的防抖保存),立刻拉既与之并发,拿到的也可能是保存前的旧内容。
  // 重复触发只保留最后一次,避免连点/连续可见变化时叠着拉。
  private refreshAfterDraftChange(): void {
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer);
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1;
      // 静默:不弹下拉转圈(程序驱动 Refresh 收不回来,且关个编辑器却弹刷新动画本身也怪)。
      this.loadInitial(true);
    }, DRAFT_REFRESH_DELAY_MS);
  }

  // 系统返回键(RootTabPage 在本页 NavDestination.onBackPressed 里 bump tick)。
  private onComposerBackTick(): void {
    if (this.showComposer) {
      this.closeComposer();
    }
  }

  // 续写后发表:走与首页发帖同一条 createTopic 链路。草稿由 ComposerPage 在发表成功后自行删除。
  private async submitResumedTopic(title: string, categoryId: number, raw: string, tags: string[],
    typingMs: number, composerMs: number): Promise<boolean> {
    if (!this.bridge) {
      return false;
    }
    const result: NetworkResult<CreateTopicOutcome> = await new TopicService(this.bridge)
      .createTopic(title, categoryId, raw, tags, typingMs, composerMs);

    if (result.success && result.data) {
      const outcome: CreateTopicOutcome = result.data;
      if (outcome.pending) {
        this.getUIContext().getPromptAction().showToast({ message: '帖子已提交，等待审核', duration: 2000 });
      } else if (typeof outcome.topicId === 'number') {
        this.getUIContext().getPromptAction().showToast({ message: '帖子已发布', duration: 1500 });
        this.onOpenTopic(outcome.topicId, title);
      }
      return true;
    }
    const reason: string = result.error ? result.error.message : '发布失败，请稍后重试。';
    this.getUIContext().getPromptAction().showToast({ message: reason, duration: 2500 });
    return false;
  }

  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge as JsonNetworkClient, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  // ==================== 数据加载 ====================

  // silent=true:静默重拉,不驱动下拉刷新转圈。
  // 必须区分,因为 Refresh 的 refreshing 是单向绑定:用户手动下拉时组件自己进刷新态、我们置 false 能收住;
  // 但程序主动置 true 让它转,组件并非自己进的态,再置 false 收不回来 → 转圈停不下来。
  // 关编辑器/返回页面这类后台刷新一律走 silent,列表本就有内容,静默换掉即可。
  private async loadInitial(silent: boolean = false): Promise<void> {
    if (!this.service || this.loading) {
      if (!this.service) {
        this.message = '正在准备请求环境';
      }
      if (!silent) {
        this.isRefreshing = false;
      }
      return;
    }
    const isFirstLoad: boolean = this.drafts.length === 0;
    this.loading = true;
    // 静默模式不动任何转圈标志:列表保持旧内容直到新数据到位。
    this.isInitialLoading = silent ? this.isInitialLoading : isFirstLoad;
    this.isRefreshing = silent ? this.isRefreshing : !isFirstLoad;
    this.loadFailed = false;

    // 复位放 finally:请求层若是 reject(而非返回失败结果),异常会穿出去,
    // 写在后面的复位就一行都执行不到 → 转圈永远停不下来(关闭续写浮层时最容易撞上:
    // 列表请求与卸载时 fire-and-forget 的草稿保存并发)。
    let result: NetworkResult<DraftPage> | undefined = undefined;
    try {
      result = await this.service.getPage(0);
    } catch (error) {
      Log.i(`${LOG_TAG} initial load threw`);
    } finally {
      this.loading = false;
      this.isInitialLoading = false;
      this.isRefreshing = false;
    }

    if (result === undefined) {
      this.loadFailed = true;
      this.message = '草稿加载失败，请重试';
      return;
    }
    if (!result.success || result.data === undefined) {
      this.loadFailed = true;
      this.message = result.error?.message ? result.error.message : '草稿加载失败，请重试';
      Log.i(`${LOG_TAG} initial load failed status=${result.statusCode}`);
      return;
    }

    this.drafts = result.data.drafts;
    this.pageOffset = result.data.drafts.length;
    this.hasMore = result.data.hasMore;
    this.message = '';
    Log.i(`${LOG_TAG} initial loaded count=${this.drafts.length} hasMore=${this.hasMore}`);
  }

  private async loadMore(): Promise<void> {
    if (!this.service || this.loading || !this.hasMore) {
      return;
    }
    this.loading = true;
    this.isLoadingMore = true;

    // 同 loadInitial:复位放 finally,否则请求层抛异常会把 loading 闸永久卡住,之后再也拉不动。
    let result: NetworkResult<DraftPage> | undefined = undefined;
    try {
      result = await this.service.getPage(this.pageOffset);
    } catch (error) {
      Log.i(`${LOG_TAG} load more threw`);
    } finally {
      this.loading = false;
      this.isLoadingMore = false;
    }

    if (result === undefined || !result.success || result.data === undefined) {
      return;
    }

    if (result.data.drafts.length === 0) {
      this.hasMore = false;
      return;
    }
    this.drafts = this.drafts.concat(result.data.drafts);
    this.pageOffset += result.data.drafts.length;
    this.hasMore = result.data.hasMore;
  }
}
