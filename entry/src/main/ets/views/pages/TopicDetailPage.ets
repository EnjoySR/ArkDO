import { Log } from '../../services/logging/Log';
import { TopicDetailRouteParam } from '../../navigation/AppRoutes';
import { Poll, PollVoteResult, PostBoost, TopicDetail, TopicPost } from '../../models/TopicDetail';
import { TopicCategory, TopicTag } from '../../models/Topic';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { TopicReadController } from '../../services/reading/TopicReadController';
import { CreateReplyOutcome, TopicService } from '../../services/topic/TopicService';
import { PostActions } from '../../services/topic/PostActions';
import { PostDataSource } from '../../services/topic/PostDataSource';
import { PostStreamPager } from '../../services/topic/PostStreamPager';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { LoadStateView } from '../components/LoadStateView';
import { TopicDetailHeader } from '../components/TopicDetailHeader';
import { TopicSummaryCard } from '../components/TopicSummaryCard';
import { TopicPostItem } from '../components/TopicPostItem';
import { ImageViewer, ViewerImage } from '../components/ImageViewer';
import { CommentInputBar, REPLY_BLUE } from '../components/CommentInputBar';
import { ComposerWindowGuard } from '../components/ComposerWindowGuard';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { TopicScrubber } from '../components/TopicScrubber';

const LOG_TAG: string = '[ArkDO][TopicDetail]';
const POSTS_PAGE_SIZE: number = 20;
// 楼层预创建数(视口外上下各 N 条)。注意:maintainVisibleContentPosition 只补偿"布局范围外"的
// 头插,插入点落进预创建范围内则不补偿——向上预取阈值必须显著大于本值。
const POSTS_CACHED_COUNT: number = 4;
// 向上预取阈值(posts 下标):离已加载区间顶部还剩这么多楼就开始补。取远大于 cachedCount 的值,
// 让网络响应回来时插入点仍在布局范围外,走框架补偿(零跳动);太小会复现"视口瞬移"BUG。
const EARLIER_PREFETCH_INDEX: number = 10;
// 顶部"正在加载/定位"悬浮胶囊开关:暂时隐藏(产品观感待定),置 true 即恢复。
const SHOW_LOADING_CAPSULE: boolean = false;
// 提交成功的 toast 延后到浮层完全收场(遮罩淡出 220ms、退全屏 240ms、键盘收起约 270ms)之后再弹,
// 否则 toast 存活期横跨键盘收起与退全屏两次布局变化,会被重新锚定而在屏幕上跳一下。
const SUCCESS_TOAST_DELAY_MS: number = 350;

@Component
export struct TopicDetailPage {
  @State private detail: TopicDetail | undefined = undefined;
  // 楼层真源:LazyForEach 数据源,增删经精准通知(maintainVisibleContentPosition 依赖)。
  // postCount 镜像总数驱动条件 UI(@State 观测不到 dataSource 内部变化),变更后须手动同步。
  private dataSource: PostDataSource = new PostDataSource();
  @State private postCount: number = 0;
  @State private isLoading: boolean = false;
  @State private message: string = '正在准备 ArkWeb 请求环境';
  @State private requiresChallenge: boolean = false;
  @State private categories: TopicCategory[] = [];
  @State private isLoadingMore: boolean = false;
  @State private hasMorePosts: boolean = false;
  @State private loadMoreMessage: string = '上拉加载更多';
  // 窗口式加载(从任意楼号进入)的向上分页:已加载区间之前是否还有更早楼层/是否正在补。
  @State private hasEarlier: boolean = false;
  @State private isLoadingEarlier: boolean = false;
  // 首帧定位的 List 下标(目标楼 + summary 占位偏移)。List 创建时读取一次,无需 @State。
  private initialListIndex: number = 0;
  // "上次访问"红线:进入时快照的已读水位(只取一次,页内重开窗口/本次阅读推高水位都不重取,
  // 否则线会消失);锚楼 = 快照后第一条已加载未读楼的 post.id,楼层创建前确定,不再变化。
  private lastVisitedSnapshot: number = 0;
  private lastVisitedAnchorPostId: number = 0;
  // 落地高亮的目标楼 post.id(通知/引用跳转):@State 经 @Prop 下发给各楼,已在组件树上的楼
  // 靠 @Watch 就地起播(已加载路径的楼内跳转)。短暂生效后清零,避免楼层销毁重建时重播。
  @State private flashTargetPostId: number = 0;
  private flashClearTimerId: number = -1;
  // 当前视口首/末项的 List 下标(onScrollIndex 持续更新):头插落在布局范围内时据此手动重锚;
  // 跳楼时据此判断目标楼是否已在屏内(在屏内则不滚动)。
  private currentStartListIndex: number = 0;
  private currentEndListIndex: number = 0;
  // 跳未加载楼的重开窗口请求进行中(防重入 + 顶部悬浮胶囊提示)。请求期间旧列表原样保留,不白屏。
  @State private isRewindowing: boolean = false;
  // List 重建开关:翻转值使 build 里的 if/else 换分支,同一帧销毁旧 List、全新重建
  // (新 List 挂新 PostDataSource 实例 + initialIndex 生效)。这是原地换窗不经过加载页的关键。
  @State private listEpochEven: boolean = true;
  // 图片浏览器在页面级渲染（放在页面根 Stack 顶层，避免被 List 裁剪、且响应式正常）
  @State private showImageViewer: boolean = false;
  @State private viewerImages: ViewerImage[] = [];
  @State private viewerStartIndex: number = 0;
  // 顶部摘要(标题/分类/标签)是否可见:滑出视口后,头部由"帖子详情"切换为显示帖子标题与分类标签行。
  @State private summaryVisible: boolean = true;
  // 当前视口首楼的楼号:驱动右缘 scrubber 的滑块位置(onScrollIndex 持续更新)。
  @State private currentPostNumber: number = 1;
  // 视口是否可滚动(摘要与末尾项同时可见 = 一屏放得下):不可滚动时隐藏 scrubber(滑块位置无意义,
  // 顺带解决"只有两楼滑块该放哪"的歧义)。
  @State private listScrollable: boolean = true;
  // "钉到底"闩:真正滚到话题结尾(onReachEnd 且无更多可加载=末楼已加载)时置位,让 scrubber 到底,
  // 补上短楼场景下"首楼映射够不到底"的末段行程;末尾项滚出视口即撤销。用 onReachEnd 而非"末楼可见"
  // 作触发——后者末楼冒出 1px 就误判到底,超长末楼会翻车;onReachEnd 是与楼高无关的真·触底信号。
  @State private atListEnd: boolean = false;
  // 评论输入浮层是否展开(点右下角悬浮回复按钮打开)。展开时由 ComposerWindowGuard 切全屏布局
  // (让浮层遮罩盖住状态栏、输入条贴键盘上沿),并给主内容补一个状态栏高度的顶部内边距抵消整体上移。
  @State @Watch('onComposerToggle') private showComposer: boolean = false;
  // 全屏布局标志:与 showComposer 分开,关闭时守卫延迟到淡出动画结束再落下,避免状态栏先露白。
  // 主内容的顶部补偿内边距也绑定它,始终与全屏同步,免得关闭途中背景跳动。
  @State private composerFullScreen: boolean = false;
  // 定向回复目标楼号:0 = 回复整个话题(顶层);>0 = 回复该楼(带 reply_to_post_number)。
  @State private replyTargetPostNumber: number = 0;
  // 输入框占位文字:回复话题「回复当前话题」/回复某楼「回复<昵称>」/发 boost「发一个 boost…」。
  @State private composerPlaceholder: string = '回复当前话题';
  // boost 输入目标楼 id:0 = 当前浮层是普通回复;>0 = 当前浮层是给该楼发 boost。
  @State private boostTargetPostId: number = 0;
  // 评论浮层的全屏窗口守卫:全屏开关经回调同步回 @State composerFullScreen。
  private composerWindowGuard: ComposerWindowGuard = new ComposerWindowGuard((on: boolean) => {
    this.composerFullScreen = on;
  });
  // 帖子列表滚动控制器:供「回复别人」指示器 / 被回复列表「跳到帖子」按 postNumber 定位楼层。
  private scroller: Scroller = new Scroller();
  param: TopicDetailRouteParam = {
    topicId: 0,
    title: ''
  };
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  // 楼层动作胶水(表情/投票/拷链/书签):乐观回滚与 toast 闭环全在服务类里,页面只接线。
  // bridge 必须经闭包惰性读取:字段初始化此刻父组件注入的 bridge prop 还没覆盖默认值,
  // 按值传会捕获未连接宿主的空壳实例(所有请求被拒,表情/书签全挂,实测翻车)。
  private postActions: PostActions = new PostActions(
    (): ArkWebNetworkBridge => this.bridge,
    (message: string, duration: number): void => this.showComposerToast(message, duration),
    (): number => this.detail?.id ?? 0,
    (): string | undefined => this.detail?.slug
  );
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  onBack: () => void = () => {};
  // 正文链接 / onebox 卡片点击上抛给根导航:站内帖子链接跳原生详情,其余打开通用 WebView。
  onOpenLink: (url: string) => void = () => {};
  private categoryIndex: CategoryIndex = new CategoryIndex();
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;
  // 已读追踪控制器:计时上报、已读水位、错峰翻已读、离开时回传列表页,全部由它托管。
  // 用闭包读取 detail 与数据源当前楼层数组(分页后数组会变,不能捕获快照)。
  private readController: TopicReadController = new TopicReadController(
    (): TopicDetail | undefined => this.detail,
    (): TopicPost[] => this.dataSource.getAll()
  );

  aboutToAppear(): void {
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }

    this.readController.attach();

    if (this.isArkWebReady && !this.detail) {
      this.loadSiteMetadataIfNeeded();
      this.loadTopicDetail();
    }

    // 读主窗口与状态栏高度,供评论浮层展开时切全屏 + 补偿背后位移。
    this.composerWindowGuard.init(getContext(this));
  }

  private onComposerToggle(): void {
    this.composerWindowGuard.toggle(this.showComposer);
  }

  aboutToDisappear(): void {
    // 先把当前已读状态回传列表页(消蓝点、更新真实剩余未读数),再结算停止计时、清理订阅。
    this.readController.detach();

    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }

    // 清掉待触发的退出全屏计时器;若仍处于全屏(评论浮层未正常关闭),兜底还原布局。
    this.composerWindowGuard.dispose();

    if (this.flashClearTimerId >= 0) {
      clearTimeout(this.flashClearTimerId);
      this.flashClearTimerId = -1;
    }
  }

  // 楼层列表区。抽成 Builder 是为了原地换窗:build 里用 listEpochEven 翻转 if/else 分支,
  // 同一帧销毁旧 List、按当前 dataSource/initialListIndex 全新重建。
  @Builder
  private PostListSection() {
    List({ scroller: this.scroller, initialIndex: this.initialListIndex }) {
      ListItem() {
        TopicSummaryCard({
          title: this.getTitle(),
          category: CategoryIndex.find(this.categories, this.detail?.categoryId),
          parentCategory: CategoryIndex.findParent(this.categories, this.detail?.categoryId),
          tags: this.getTags(),
          metaText: this.getTopicMetaText(),
          solved: (this.detail?.acceptedAnswers?.length ?? 0) > 0
        })
      }

      LazyForEach(this.dataSource, (post: TopicPost) => {
        TopicPostItem({
          post: post,
          topicCreatedById: this.detail?.createdById ?? -1,
          lastReadPostNumber: this.detail?.lastReadPostNumber ?? -1,
          showLastVisitedLine: post.id === this.lastVisitedAnchorPostId && this.lastVisitedAnchorPostId > 0,
          flashTargetPostId: this.flashTargetPostId,
          // 采纳答案面板只挂一楼:非一楼下发空数组,免得每个 item 都持有整份数据。
          acceptedAnswers: post.postNumber === 1 ? (this.detail?.acceptedAnswers ?? []) : [],
          onOpenImages: (images: ViewerImage[], startIndex: number) => {
            this.openImageViewer(images, startIndex);
          },
          onOpenLink: (url: string) => {
            this.onOpenLink(url);
          },
          onJumpToQuote: (topicId: number, postNumber: number, fallbackUrl: string) => {
            this.jumpToQuote(topicId, postNumber, fallbackUrl);
          },
          onResolveQuotedPost: (topicId: number, postNumber: number): Promise<string> => {
            return this.resolveQuotedPost(topicId, postNumber);
          },
          onResolveMedia: (url: string): Promise<string> => {
            return this.bridge.downloadMedia(url);
          },
          onToggleReaction: (targetPost: TopicPost, reaction: string): Promise<boolean> => {
            return this.postActions.toggleReaction(targetPost, reaction);
          },
          onReply: (targetPost: TopicPost) => {
            this.openComposerForPost(targetPost);
          },
          onAddBoost: (targetPost: TopicPost) => {
            this.openComposerForBoost(targetPost);
          },
          onJumpToPost: (postNumber: number): Promise<void> => {
            return this.jumpToPostNumber(postNumber);
          },
          onLoadReplies: (targetPost: TopicPost) => {
            return this.loadPostReplies(targetPost);
          },
          onVote: (targetPost: TopicPost, poll: Poll, optionIds: string[]) => {
            return this.postActions.vote(targetPost, poll, optionIds);
          },
          onRemoveVote: (targetPost: TopicPost, poll: Poll) => {
            return this.postActions.removeVote(targetPost, poll);
          },
          onCopyPostLink: (targetPost: TopicPost) => {
            this.postActions.copyPostLink(targetPost);
          },
          onToggleBookmark: (targetPost: TopicPost) => {
            return this.postActions.toggleBookmark(targetPost);
          }
        })
      }, (post: TopicPost) => post.id.toString())

      if (this.postCount > 0) {
        ListItem() {
          Row() {
            if (this.isLoadingMore) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.brand'))
                .margin({ right: 8 })
            }

            Text(this.loadMoreMessage)
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .height(54)
          .justifyContent(FlexAlign.Center)
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    // 关掉系统默认滚动条:右缘已有楼层 scrubber,两者并存会视觉打架。
    .scrollBar(BarState.Off)
    // 左右留白下放到各 item 内部(楼层高亮背景要通栏),List 不再统一内缩。
    // 头部插入更早楼层时保持可视内容不动。重要:只在"List 创建后从未吃过 onDataReloaded"时可靠
    // ——对活 List 做 reset 会让后续补偿全部失效(实测),原地换窗必须走 epoch 翻转重建。
    .maintainVisibleContentPosition(true)
    // 楼层含富文本/图片偏重,预创建数平衡快滑白块与内存(与向上预取阈值联动,见常量注释)。
    .cachedCount(POSTS_CACHED_COUNT)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onScrollIndex((start: number, end: number) => {
      this.currentStartListIndex = start;
      this.currentEndListIndex = end;
      // List 的 index 0 是 TopicSummary,楼层从 index 1 起 → 换算成 posts 下标再交给已读控制器。
      this.readController.onVisibleRange(start - 1, end - 1);
      // 摘要 ListItem 固定为 index 0:仍在视口内(start===0)显示"帖子详情",滑出后显示帖子标题与分类标签。
      this.summaryVisible = start === 0;
      // 右缘 scrubber:维护可滚动性、钉底闩、当前楼号(见 updateScrubberFromScroll)。
      this.updateScrubberFromScroll(start, end);
      // 快到已加载区间顶部时预取更早楼层:响应回来时插入点须仍在布局范围外才有框架补偿,
      // 阈值要给"网络期间用户继续上滑"留够余量(实测 3 太小,必现视口瞬移)。
      if (this.hasEarlier && start - 1 <= EARLIER_PREFETCH_INDEX) {
        this.loadEarlierPosts();
      }
    })
    .onReachStart(() => {
      // 兜底:飞速甩到顶、预取没来得及触发时。
      this.loadEarlierPosts();
    })
    .onReachEnd(() => {
      this.loadMorePosts();
      // 真正滚到话题结尾(无更多可加载 → 末楼已加载)才钉滑块到底;loadMorePosts 在 !hasMorePosts 时
      // 自身 no-op,故此处同步判定即当前状态。有更多待加载时不钉,交给分页继续拉。
      if (!this.hasMorePosts) {
        this.atListEnd = true;
        this.currentPostNumber = this.getHighestPostNumber();
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
    Column() {
      TopicDetailHeader({
        summaryVisible: this.summaryVisible,
        title: this.getTitle(),
        showBadges: this.hasBadges(),
        category: CategoryIndex.find(this.categories, this.detail?.categoryId),
        parentCategory: CategoryIndex.findParent(this.categories, this.detail?.categoryId),
        tags: this.getTags(),
        solved: (this.detail?.acceptedAnswers?.length ?? 0) > 0,
        onBack: () => {
          this.onBack();
        }
      })

      if (this.detail) {
        // 相同的两个分支:翻转 listEpochEven 强制销毁重建 List(原地换窗用),平时恒走其一。
        if (this.listEpochEven) {
          this.PostListSection()
        } else {
          this.PostListSection()
        }
      } else {
        LoadStateView({
          isLoading: this.isLoading,
          message: this.message,
          requiresChallenge: this.requiresChallenge,
          showRetry: !this.isLoading && this.isArkWebReady,
          onRetry: () => {
            this.loadTopicDetail();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    // 全屏时(composerFullScreen)主内容会整体上移一个状态栏高度;补等高顶部内边距抵消,背后视觉不动。
    // 绑 composerFullScreen 而非 showComposer:关闭时全屏延后落下,补偿也随之延后,避免关闭途中背景跳。
    .padding({ top: this.composerFullScreen ? this.composerWindowGuard.statusBarHeight : 0 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

    // 右缘楼层 scrubber:话题够长(最高楼 > 1)且浮层未展开时挂载,拖动直接跳楼。
    // 覆盖层自身透明、只在右缘 Slider 处拦截触摸,不影响正文滚动。
    if (this.detail && this.getHighestPostNumber() > 1 && this.listScrollable
      && !this.showComposer && !this.composerFullScreen) {
      TopicScrubber({
        currentPostNumber: this.currentPostNumber,
        highestPostNumber: this.getHighestPostNumber(),
        onJump: (postNumber: number): Promise<void> => {
          return this.jumpToPostNumber(postNumber);
        }
      })
    }

    // 右下角悬浮回复按钮:仅在帖子已加载、浮层未展开且全屏布局已还原时显示。
    // 必须一并绑定 composerFullScreen:关闭浮层时退全屏延迟 240ms,期间根 Stack 底边仍延伸到
    // 导航条区域,锚在底边的按钮会先出现在偏下位置、退全屏后再跳回(用户反馈的"闪回" BUG)。
    if (this.detail && !this.showComposer && !this.composerFullScreen) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        FaIconView({
          icon: this.replyFabIcon(),
          color: '#FFFFFF',
          iconSize: 22
        })
      }
      .width(52)
      .height(52)
      .backgroundColor(REPLY_BLUE)
      .shadow({ radius: 8, color: '#33000000', offsetX: 0, offsetY: 2 })
      .margin({ right: 16, bottom: 24 })
      // 不对称过渡:出现(关闭浮层后)淡入;消失(打开浮层时)立即移除。
      // 消失不能加动画——退场中的节点不参与布局、也没有全屏补偿,会被同帧的全屏切换
      // 拖着上移一个状态栏高度再淡掉;瞬间移除则被同时淡入的遮罩盖住,毫无痕迹。
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }),
        TransitionEffect.IDENTITY
      ))
      .onClick(() => {
        this.openComposerForTopic();
      })
    }

    // 向上补楼 / 跳楼定位的加载指示:悬浮小胶囊,不参与 List 布局(头插时列表零跳动的前提)。
    if (SHOW_LOADING_CAPSULE && (this.isLoadingEarlier || this.isRewindowing)) {
      Row() {
        LoadingProgress()
          .width(14)
          .height(14)
          .color($r('app.color.brand'))
          .margin({ right: 6 })
        Text(this.isRewindowing ? '正在定位楼层' : '正在加载更早的回复')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.surface_card'))
      .borderRadius(15)
      .shadow({ radius: 6, color: '#22000000', offsetX: 0, offsetY: 1 })
      .position({ x: '50%', y: 72 })
      .markAnchor({ x: '50%', y: 0 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
    }

    if (this.showImageViewer) {
      ImageViewer({
        images: this.viewerImages,
        startIndex: this.viewerStartIndex,
        onClose: () => {
          this.closeImageViewer();
        }
      })
        // 入场/退场：纯淡入淡出（不缩放，黑底不变小，只是颜色渐显/渐隐）；由 open/close 的 animateTo 驱动
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
        )
    }

    // 评论输入浮层:内联挂在根 Stack 顶层(而非 contentCover),这样组件 getLastWindow 拿到主窗口、
    // 能稳定收到键盘高度事件把输入条顶到键盘上方;组件内部临时切全屏布局让遮罩盖住状态栏。
    if (this.showComposer) {
      CommentInputBar({
        placeholder: this.composerPlaceholder,
        // boost 是「起飞」「感谢佬」这类短文本,放开最短字数下限;普通回复仍用默认 16。
        minChars: this.boostTargetPostId > 0 ? 1 : 16,
        onClose: () => {
          this.showComposer = false;
          this.replyTargetPostNumber = 0;
          this.boostTargetPostId = 0;
        },
        onSubmit: (text: string, typingMs: number, composerMs: number): Promise<boolean> => {
          // boost 模式走 createBoost;否则走普通回复。
          if (this.boostTargetPostId > 0) {
            return this.submitBoost(text);
          }
          return this.submitReply(text, typingMs, composerMs);
        }
      })
    }

    }
    .width('100%')
    .height('100%')
  }

  // 点 FAB:回复整个话题(顶层回复)。
  private openComposerForTopic(): void {
    this.boostTargetPostId = 0;
    this.replyTargetPostNumber = 0;
    this.composerPlaceholder = '回复当前话题';
    this.showComposer = true;
  }

  // 点某楼回复按钮:定向回复该楼,占位文字「回复<作者昵称>」。
  private openComposerForPost(post: TopicPost): void {
    this.boostTargetPostId = 0;
    this.replyTargetPostNumber = post.postNumber;
    this.composerPlaceholder = `回复${this.resolveAuthorName(post)}`;
    this.showComposer = true;
  }

  // 点火箭:给该楼发 boost,占位文字「发一个 boost…」。
  private openComposerForBoost(post: TopicPost): void {
    this.replyTargetPostNumber = 0;
    this.boostTargetPostId = post.id;
    this.composerPlaceholder = '发一个 boost…';
    this.showComposer = true;
  }

  // 作者昵称:displayName(来自 API name)优先,回退 username,再回退占位。
  private resolveAuthorName(post: TopicPost): string {
    const displayName: string | undefined = post.author?.displayName;
    if (displayName && displayName.length > 0) {
      return displayName;
    }
    const username: string | undefined = post.author?.username;
    if (username && username.length > 0) {
      return username;
    }
    return '该用户';
  }

  // 发表评论:POST /posts。成功后把新楼层追加到列表底部,返回 true 令浮层关闭。
  // replyTargetPostNumber>0 时定向回复该楼(带 reply_to_post_number),否则回复整个话题。
  private async submitReply(text: string, typingMs: number, composerMs: number): Promise<boolean> {
    if (!this.detail) {
      return false;
    }
    const topicId: number = this.detail.id;
    const categoryId: number | undefined = this.detail.categoryId;
    const replyToPostNumber: number | undefined =
      this.replyTargetPostNumber > 0 ? this.replyTargetPostNumber : undefined;
    const result: NetworkResult<CreateReplyOutcome> = await new TopicService(this.bridge)
      .createReply(topicId, categoryId, text, typingMs, composerMs, replyToPostNumber);

    if (result.success && result.data) {
      this.replyTargetPostNumber = 0;
      if (result.data.pending) {
        // 进入审核队列:提交成功但不会立刻出现在列表里。
        this.showToastAfterComposerClose('评论已提交，等待审核', 2000);
      } else if (result.data.post) {
        // 直接发布:追加到楼层末尾(数据源精准通知,列表只新建这一条)。
        this.dataSource.appendPosts([result.data.post]);
        this.postCount = this.dataSource.totalCount();
        this.showToastAfterComposerClose('评论已发表', 1500);
      }
      return true;
    }

    const reason: string = result.error ? result.error.message : '发表失败，请稍后重试。';
    this.showComposerToast(reason, 2000);
    return false;
  }

  // 发送 boost:POST /discourse-boosts/posts/{id}/boosts。成功后把返回的 boost 乐观追加到该楼,
  // 返回 true 令浮层关闭;失败保留输入内容(返回 false)。
  private async submitBoost(text: string): Promise<boolean> {
    if (!this.detail || this.boostTargetPostId <= 0) {
      return false;
    }
    const postId: number = this.boostTargetPostId;
    const topicId: number = this.detail.id;
    const result: NetworkResult<PostBoost> = await new TopicService(this.bridge).createBoost(postId, topicId, text);

    if (result.success && result.data) {
      const target: TopicPost | undefined = PostStreamPager.findById(this.dataSource.getAll(), postId);
      if (target) {
        // 用新数组赋值触发 @ObjectLink 精准重渲染(直接 push 现有数组不会被观测)。
        const next: PostBoost[] = target.boosts ? target.boosts.slice() : [];
        next.push(result.data);
        target.boosts = next;
        // 一个人对一楼只能 boost 一次:提交后本地即置 canBoost=false,火箭立即对我隐藏
        // (与服务端重新返回 can_boost=false 一致,无需退出重进)。
        target.canBoost = false;
      }
      this.boostTargetPostId = 0;
      this.showToastAfterComposerClose('Boost 已发送', 1500);
      return true;
    }

    const reason: string = result.error ? result.error.message : 'Boost 发送失败，请稍后重试。';
    this.showComposerToast(reason, 2000);
    return false;
  }

  // 按 postNumber 滚动定位到对应楼层。List index 0 是 TopicSummary,楼层从 index 1 起 → 目标 index = 楼序 + 1。
  // 已加载直接平滑滚动;未加载原地重开窗口(先卸载 List 再以新窗口重建,见 rewindowToPost)。
  private async jumpToPostNumber(postNumber: number): Promise<void> {
    const index: number = this.dataSource.findIndexByPostNumber(postNumber);
    Log.i(`${LOG_TAG} jump request post=${postNumber} loadedIndex=${index}`);
    if (index >= 0) {
      // 已加载:落地高亮(与重开窗口路径观感一致)。
      const targetListIndex: number = index + 1;
      this.armTargetFlash(this.dataSource.getData(index).id);
      // 目标楼已在视口范围内:用 AUTO 对齐——完全可见就原地不动(不把它无谓拽到屏顶,仅靠高亮提示),
      // 只在顶/底被裁只露一半时,按最短距离滑动把它完整带进视口。
      if (targetListIndex >= this.currentStartListIndex && targetListIndex <= this.currentEndListIndex) {
        this.scroller.scrollToIndex(targetListIndex, true, ScrollAlign.AUTO);
        return;
      }
      // 完全在屏外:对齐到视口顶部(导航栏下)定位。
      this.scroller.scrollToIndex(targetListIndex, true);
      return;
    }
    await this.rewindowToPost(postNumber);
  }

  // 引用卡 arrow-up:被引用楼在本帖 → 滚动定位;跨帖 → 走 fallbackUrl 开详情(经 LinkRouter)。
  private jumpToQuote(topicId: number, postNumber: number, fallbackUrl: string): void {
    if (topicId === this.param.topicId && postNumber > 0) {
      this.jumpToPostNumber(postNumber);
      return;
    }
    if (fallbackUrl.length > 0) {
      this.onOpenLink(fallbackUrl);
    }
  }

  // 引用卡取被引用楼层全文:先遍历已加载楼层(本帖),没有再按需 GET /posts/by_number/{topicId}/{postNumber}。
  // 拉不到返回 ''(→ 引用卡隐藏展开、只显示预览)。
  private async resolveQuotedPost(topicId: number, postNumber: number): Promise<string> {
    if (topicId <= 0 || postNumber <= 0) {
      return '';
    }
    // 1. 已加载楼层直接取(仅本帖流里有)。
    if (topicId === this.param.topicId) {
      const index: number = this.dataSource.findIndexByPostNumber(postNumber);
      if (index >= 0) {
        const html: string = this.dataSource.getData(index).cookedHtml;
        if (html.length > 0) {
          return html;
        }
      }
    }
    // 2. 未加载:按需拉取单楼 cooked。
    const result: NetworkResult<string> = await new TopicService(this.bridge).getPostByNumber(topicId, postNumber);
    if (result.success && result.data !== undefined) {
      return result.data;
    }
    return '';
  }

  // 目标楼未加载:以该楼为锚重新拉一窗详情,原地换窗。
  // 网络期间旧列表原样保留(不白屏,顶部胶囊提示"正在定位");数据就位后换一个全新的
  // PostDataSource 实例并翻转 listEpochEven,同一帧销毁旧 List、按 initialIndex 全新重建。
  // 绝不对活 List 发 onDataReloaded——那会让 maintainVisibleContentPosition 的头插补偿
  // 永久失效(实测),这正是"新建 List 没问题、原地 reset 有问题"的根因;旧 List 至死只持有
  // 旧数据源实例,新数据源的任何通知都到不了它。
  private async rewindowToPost(postNumber: number): Promise<void> {
    if (!this.detail || this.isRewindowing) {
      return;
    }
    this.isRewindowing = true;
    const topicId: number = this.detail.id;
    const slug: string | undefined = this.detail.slug ?? this.param.slug;

    const result: NetworkResult<TopicDetail> =
      await new TopicService(this.bridge).getTopicDetail(topicId, slug, postNumber);
    this.isRewindowing = false;

    if (!result.success || !result.data || result.data.posts.length === 0) {
      // 失败:旧列表还在原位,只提示。
      Log.i(`${LOG_TAG} rewindow failed post=${postNumber} status=${result.statusCode}`);
      this.showComposerToast('楼层定位失败，请稍后重试', 1500);
      return;
    }

    const stream: number[] = result.data.stream ?? [];
    const nextSource: PostDataSource = new PostDataSource();
    nextSource.reset(result.data.posts);
    this.dataSource = nextSource;
    this.postCount = nextSource.totalCount();
    this.hasEarlier = PostStreamPager.countEarlier(stream, nextSource.getAll()) > 0;
    this.hasMorePosts = PostStreamPager.countLater(stream, nextSource.getAll()) > 0;
    this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
    this.updateLastVisitedAnchor();

    const targetIndex: number = Math.max(0, nextSource.findIndexAtOrAfterPostNumber(postNumber));
    this.initialListIndex = targetIndex + 1;
    this.armTargetFlash(nextSource.getData(targetIndex).id);
    this.detail = result.data;
    // 翻转分支 → 旧 List 销毁、新 List 以新数据源 + initialIndex 重建,同帧完成,无加载页。
    this.listEpochEven = !this.listEpochEven;
    const posts: TopicPost[] = nextSource.getAll();
    Log.i(`${LOG_TAG} rewindow ok post=${postNumber} targetIndex=${targetIndex} stream=${stream.length} window=[${posts[0]?.postNumber}..${posts[posts.length - 1]?.postNumber}] hasEarlier=${this.hasEarlier} hasMore=${this.hasMorePosts}`);
  }

  // 武装目标楼落地高亮:短暂生效后清零,免得该楼被 LazyForEach 销毁重建时重播。
  private armTargetFlash(postId: number): void {
    this.flashTargetPostId = postId;
    if (this.flashClearTimerId >= 0) {
      clearTimeout(this.flashClearTimerId);
    }
    this.flashClearTimerId = setTimeout(() => {
      this.flashTargetPostId = 0;
      this.flashClearTimerId = -1;
    }, 3000);
  }

  // 加载某楼的「被回复」列表(供 TopicPostItem 展开时调用)。成功返回楼层数组;失败弹 toast 并返回 null。
  private async loadPostReplies(post: TopicPost): Promise<TopicPost[] | null> {
    const result: NetworkResult<TopicPost[]> = await new TopicService(this.bridge).getPostReplies(post.id);
    if (result.success && result.data) {
      return result.data;
    }
    const reason: string = result.error ? result.error.message : '加载回复失败，请稍后重试。';
    this.showComposerToast(reason, 2000);
    return null;
  }

  private showComposerToast(message: string, duration: number): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: duration });
    } catch (error) {
      // Toast 失败不影响主流程。
    }
  }

  // 提交成功后浮层随即关闭(键盘收起+退全屏),提示延后到收场结束再弹,避免 toast 被重新锚定而跳动。
  // 失败提示不延迟:浮层保持展开、键盘不收,不存在布局变化。
  private showToastAfterComposerClose(message: string, duration: number): void {
    setTimeout(() => {
      this.showComposerToast(message, duration);
    }, SUCCESS_TOAST_DELAY_MS);
  }

  private replyFabIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('reply');
    return def ? def : { id: 'reply', rawfilePath: 'fa_icons/reply.svg' };
  }

  // 依据视口首/末项下标维护 scrubber 状态:可滚动性、钉底闩、当前楼号。
  // 列表项布局:index 0 = 摘要卡,1..postCount = 楼层,postCount+1 = 底部加载态行(有楼层时恒存在)。
  private updateScrubberFromScroll(start: number, end: number): void {
    const lastIndex: number = this.postCount + 1;
    // 摘要(index 0)与末尾项同时可见 = 整屏放得下、不可滚动 → 隐藏 scrubber。
    this.listScrollable = !(start === 0 && end >= lastIndex);
    // 末尾项滚出视口即离开底部,撤销钉底(短楼:滑块回落到首楼映射;长末楼:首楼本就是 max,无影响)。
    if (this.atListEnd && end < lastIndex) {
      this.atListEnd = false;
    }
    // 钉底优先 → 顶部(摘要可见)记 1 楼 → 否则取视口首楼楼号。
    if (this.atListEnd) {
      this.currentPostNumber = this.getHighestPostNumber();
      return;
    }
    if (start === 0) {
      this.currentPostNumber = 1;
      return;
    }
    const firstPostIndex: number = start - 1;
    if (firstPostIndex >= 0 && firstPostIndex < this.dataSource.totalCount()) {
      this.currentPostNumber = this.dataSource.getData(firstPostIndex).postNumber;
    }
  }

  // scrubber 上限:优先话题最高楼号;缺失时回退到已加载末楼 / 楼层数。
  private getHighestPostNumber(): number {
    const highest: number = this.detail?.highestPostNumber ?? 0;
    if (highest > 0) {
      return highest;
    }
    const posts: TopicPost[] = this.dataSource.getAll();
    if (posts.length > 0) {
      return posts[posts.length - 1].postNumber;
    }
    return this.postCount;
  }

  private openImageViewer(images: ViewerImage[], startIndex: number): void {
    this.viewerImages = images;
    this.viewerStartIndex = startIndex;
    // animateTo 驱动 .transition 播放淡入入场
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.showImageViewer = true;
    });
  }

  private closeImageViewer(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.showImageViewer = false;
    });
  }

  private async loadTopicDetail(): Promise<void> {
    if (!this.isArkWebReady) {
      this.message = '正在准备 ArkWeb 请求环境';
      return;
    }

    if (this.isLoading) {
      return;
    }

    if (this.param.topicId <= 0) {
      this.message = '帖子参数无效';
      return;
    }

    this.isLoading = true;
    this.requiresChallenge = false;
    this.message = '正在加载帖子详情';
    this.loadSiteMetadataIfNeeded();
    Log.i(`${LOG_TAG} load detail start topicId=${this.param.topicId} slug=${this.getSlugLabel()}`);

    const result: NetworkResult<TopicDetail> =
      await new TopicService(this.bridge).getTopicDetail(this.param.topicId, this.param.slug, this.param.targetPostNumber);

    this.isLoading = false;
    if (result.success && result.data) {
      const stream: number[] = result.data.stream ?? [];
      this.detail = result.data;
      this.dataSource.reset(result.data.posts);
      this.postCount = this.dataSource.totalCount();
      this.message = this.postCount > 0 ? '' : '暂无帖子内容';
      this.hasEarlier = PostStreamPager.countEarlier(stream, this.dataSource.getAll()) > 0;
      this.hasMorePosts = PostStreamPager.countLater(stream, this.dataSource.getAll()) > 0;
      this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
      // 带目标楼进入:List 尚未创建(detail 刚就位),首帧直接定位到目标楼(+1 为 summary 占位)。
      const target: number | undefined = this.param.targetPostNumber;
      if (target !== undefined && target > 1 && this.postCount > 0) {
        const targetIndex: number = Math.max(0, this.dataSource.findIndexAtOrAfterPostNumber(target));
        this.initialListIndex = targetIndex + 1;
        if (this.param.highlightTarget === true) {
          this.armTargetFlash(this.dataSource.getData(targetIndex).id);
        }
      }
      // "上次访问"红线只属于"未读徽标跳转"入口:带目标楼号且不高亮(通知=带楼号+高亮、
      // 普通打开=无楼号,都不画线;官网是所有入口都画,这里按产品偏好收窄)。
      const isUnreadBadgeEntry: boolean =
        this.param.targetPostNumber !== undefined && this.param.highlightTarget !== true;
      // 水位只在首次加载快照;已读完(水位>=最高楼)或匿名(无水位)不设线。
      if (isUnreadBadgeEntry && this.lastVisitedSnapshot === 0) {
        const watermark: number = result.data.lastReadPostNumber ?? 0;
        const highest: number = result.data.highestPostNumber ?? 0;
        if (watermark > 0 && watermark < highest) {
          this.lastVisitedSnapshot = watermark;
        }
      }
      this.updateLastVisitedAnchor();
      // 定位与红线对齐:红线锚楼取自详情接口的真实水位(result.data.lastReadPostNumber → lastVisitedSnapshot),
      // 而入口楼号 param.targetPostNumber 来自列表页水位(可能陈旧/估算,见 HomePage.openTopic),两者不一致
      // 会造成"定位到 50 楼、红线却画在 43 楼"。锚楼一旦确定,改用真实水位把首帧落点重算成第一条真实未读楼
      // (锚楼的下一楼),与红线严格对齐;未读楼顶格,红线自然落在其顶边(导航栏下方),无需额外偏移。
      if (isUnreadBadgeEntry && this.lastVisitedAnchorPostId > 0) {
        const firstUnreadIndex: number = Math.max(0, this.dataSource.findIndexAtOrAfterPostNumber(this.lastVisitedSnapshot + 1));
        this.initialListIndex = firstUnreadIndex + 1;
      }
      Log.i(`${LOG_TAG} load detail success topicId=${result.data.id} posts=${result.data.posts.length} stream=${result.data.stream ? result.data.stream.length : 0}`);
      this.startReadingTrackerIfNeeded();
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.message = result.error?.message ? result.error.message : '帖子详情加载失败';
    Log.i(`${LOG_TAG} load detail failed topicId=${this.param.topicId} status=${result.statusCode}`);
  }

  private async loadMorePosts(): Promise<void> {
    if (!this.detail || this.isLoadingMore || !this.hasMorePosts) {
      return;
    }
    const stream: number[] = this.detail.stream ? this.detail.stream : [];
    const nextIds: number[] = PostStreamPager.collectNextIds(stream, this.dataSource.getAll(), POSTS_PAGE_SIZE);
    if (nextIds.length === 0) {
      this.hasMorePosts = false;
      this.loadMoreMessage = '没有更多了';
      return;
    }

    this.isLoadingMore = true;
    this.loadMoreMessage = '正在加载更多';
    const topicId: number = this.detail.id;
    const result: NetworkResult<TopicPost[]> = await new TopicService(this.bridge).loadMorePosts(topicId, nextIds);
    this.isLoadingMore = false;

    if (result.success && result.data) {
      const added: number = this.dataSource.appendPosts(result.data);
      this.postCount = this.dataSource.totalCount();
      this.hasMorePosts = PostStreamPager.countLater(stream, this.dataSource.getAll()) > 0;
      this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
      this.updateLastVisitedAnchor();
      Log.i(`${LOG_TAG} load more topicId=${topicId} added=${added} total=${this.postCount}`);
      return;
    }

    this.loadMoreMessage = result.error?.message ? `${result.error.message}，上拉重试` : '加载更多失败，上拉重试';
  }

  // 确定"上次访问"红线锚楼:快照水位后第一条未读楼的**上一楼**(最后一条已读)。
  // 红线画在锚楼底边,替代该处灰色分割线 → 楼间只此一条,恰是"已读|未读"边界。
  // 上一楼须已加载(index>0)才能锚;首条已加载楼即未读时,已读侧还在未加载区,留待 prepend 补楼后重试。
  // 锚一旦确定不再变化。
  private updateLastVisitedAnchor(): void {
    if (this.lastVisitedSnapshot <= 0 || this.lastVisitedAnchorPostId > 0 || !this.detail) {
      return;
    }
    const posts: TopicPost[] = this.dataSource.getAll();
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].postNumber <= this.lastVisitedSnapshot) {
        continue;
      }
      if (index > 0) {
        this.lastVisitedAnchorPostId = posts[index - 1].id;
      }
      return;
    }
  }

  // 向上补更早楼层(窗口式进入后往回看):取已加载区间之前的一页 id,头插进数据源。
  // 插入若发生在视口上方,由 maintainVisibleContentPosition 保持可视内容不动。
  private async loadEarlierPosts(): Promise<void> {
    if (!this.detail || this.isLoadingEarlier || !this.hasEarlier) {
      return;
    }
    const stream: number[] = this.detail.stream ? this.detail.stream : [];
    const loaded: TopicPost[] = this.dataSource.getAll();
    const prevIds: number[] = PostStreamPager.collectPrevIds(stream, loaded, POSTS_PAGE_SIZE);
    Log.i(`${LOG_TAG} loadEarlier begin stream=${stream.length} loaded=${loaded.length} window=[${loaded[0]?.postNumber}..${loaded[loaded.length - 1]?.postNumber}] prevIds=${prevIds.length}`);
    if (prevIds.length === 0) {
      this.hasEarlier = false;
      return;
    }

    this.isLoadingEarlier = true;
    const topicId: number = this.detail.id;
    const result: NetworkResult<TopicPost[]> = await new TopicService(this.bridge).loadMorePosts(topicId, prevIds);
    this.isLoadingEarlier = false;

    if (result.success && result.data) {
      const startBefore: number = this.currentStartListIndex;
      const added: number = this.dataSource.prependPosts(result.data);
      this.postCount = this.dataSource.totalCount();
      this.hasEarlier = PostStreamPager.countEarlier(stream, this.dataSource.getAll()) > 0;
      this.updateLastVisitedAnchor();
      // 兜底重锚:插入点落在 List 已布局范围内(视口上方剩余楼层 ≤ cachedCount)时框架不补偿,
      // 视口内容会瞬移到新插入的楼——手动按"原下标 + 插入数"无动画锚回。范围外则框架已补偿,勿重复。
      if (added > 0 && startBefore - 1 <= POSTS_CACHED_COUNT) {
        this.scroller.scrollToIndex(startBefore + added, false);
        Log.i(`${LOG_TAG} manual re-anchor startBefore=${startBefore} added=${added} -> ${startBefore + added}`);
      }
      Log.i(`${LOG_TAG} loadEarlier ok added=${added} total=${this.postCount} hasEarlier=${this.hasEarlier} startBefore=${startBefore}`);
      return;
    }

    Log.i(`${LOG_TAG} loadEarlier failed topicId=${topicId} status=${result.statusCode} err=${result.error?.message ?? ''}`);
    this.showComposerToast(result.error?.message ? result.error.message : '加载更早楼层失败', 1500);
  }

  private startReadingTrackerIfNeeded(): void {
    const service: TopicService = new TopicService(this.bridge);
    this.readController.startIfNeeded(
      (id: number, timings: Map<number, number>, topicTime: number) => service.reportTimings(id, timings, topicTime),
      LOG_TAG
    );
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady && !this.detail && !this.isLoading) {
      this.loadSiteMetadataIfNeeded();
      this.loadTopicDetail();
    }
  }

  private handleSessionChanged(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    this.handledSessionVersion = version;
    if (!this.detail && !this.isLoading) {
      this.message = '会话已更新，正在重试';
      this.loadTopicDetail();
    }
  }

  private getTitle(): string {
    const title: string | undefined = this.detail?.title;
    if (title && title.length > 0) {
      return title;
    }
    return this.param.title;
  }

  private getTopicMetaText(): string {
    if (!this.detail) {
      return `Topic ID：${this.param.topicId}`;
    }

    const postsCount: number = this.detail.postsCount ? this.detail.postsCount : this.postCount;
    const replyCount: number = this.detail.replyCount ? this.detail.replyCount : 0;
    const likeCount: number = this.detail.likeCount ? this.detail.likeCount : 0;
    const viewCount: number = this.detail.viewCount ? this.detail.viewCount : 0;
    return `${postsCount} 帖 · ${replyCount} 回复 · ${likeCount} 赞 · ${viewCount} 浏览`;
  }

  private async loadSiteMetadataIfNeeded(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  private hasBadges(): boolean {
    return CategoryIndex.find(this.categories, this.detail?.categoryId) !== undefined || this.getTags().length > 0;
  }

  private getTags(): TopicTag[] {
    return this.detail?.tags ? this.detail.tags : [];
  }

  private getSlugLabel(): string {
    if (!this.param.slug || this.param.slug.length === 0) {
      return '无';
    }
    return this.param.slug;
  }
}
