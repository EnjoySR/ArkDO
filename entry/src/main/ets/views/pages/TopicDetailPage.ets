import { pasteboard } from '@kit.BasicServicesKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { TopicDetailRouteParam } from '../../navigation/AppRoutes';
import { Poll, PollVoteResult, PostBoost, TopicDetail, TopicPost } from '../../models/TopicDetail';
import { TopicCategory, TopicTag } from '../../models/Topic';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { TopicReadController } from '../../services/reading/TopicReadController';
import { ReactionMutation, ReactionSnapshot } from '../../services/topic/ReactionMutation';
import { PollMutation, PollSnapshot } from '../../services/topic/PollMutation';
import { CreateReplyOutcome, TopicService } from '../../services/topic/TopicService';
import { PostStreamPager } from '../../services/topic/PostStreamPager';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { TopicMetadataBadges } from '../components/TopicBadges';
import { TopicDetailHeader } from '../components/TopicDetailHeader';
import { TopicPostItem } from '../components/TopicPostItem';
import { ImageViewer, ViewerImage } from '../components/ImageViewer';
import { CommentInputBar, REPLY_BLUE } from '../components/CommentInputBar';
import { ComposerWindowGuard } from '../components/ComposerWindowGuard';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';

const LOG_TAG: string = '[ArkDO][TopicDetail]';
const POSTS_PAGE_SIZE: number = 20;
// 提交成功的 toast 延后到浮层完全收场(遮罩淡出 220ms、退全屏 240ms、键盘收起约 270ms)之后再弹,
// 否则 toast 存活期横跨键盘收起与退全屏两次布局变化,会被重新锚定而在屏幕上跳一下。
const SUCCESS_TOAST_DELAY_MS: number = 350;

@Component
export struct TopicDetailPage {
  @State private detail: TopicDetail | undefined = undefined;
  @State private posts: TopicPost[] = [];
  @State private isLoading: boolean = false;
  @State private message: string = '正在准备 ArkWeb 请求环境';
  @State private requiresChallenge: boolean = false;
  @State private categories: TopicCategory[] = [];
  @State private isLoadingMore: boolean = false;
  @State private hasMorePosts: boolean = false;
  @State private loadMoreMessage: string = '上拉加载更多';
  // 图片浏览器在页面级渲染（放在页面根 Stack 顶层，避免被 List 裁剪、且响应式正常）
  @State private showImageViewer: boolean = false;
  @State private viewerImages: ViewerImage[] = [];
  @State private viewerStartIndex: number = 0;
  // 顶部摘要(标题/分类/标签)是否可见:滑出视口后,头部由"帖子详情"切换为显示帖子标题与分类标签行。
  @State private summaryVisible: boolean = true;
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
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  onBack: () => void = () => {};
  // 正文链接 / onebox 卡片点击上抛给根导航:站内帖子链接跳原生详情,其余打开通用 WebView。
  onOpenLink: (url: string) => void = () => {};
  private categoryIndex: CategoryIndex = new CategoryIndex();
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;
  // 已读追踪控制器:计时上报、已读水位、错峰翻已读、离开时回传列表页,全部由它托管。
  // 用闭包读取 @State 的 detail/posts(posts 分页后会换新数组,不能捕获快照)。
  private readController: TopicReadController = new TopicReadController(
    (): TopicDetail | undefined => this.detail,
    (): TopicPost[] => this.posts
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
        onBack: () => {
          this.onBack();
        }
      })

      if (this.detail) {
        List({ scroller: this.scroller }) {
          ListItem() {
            this.TopicSummary()
          }

          ForEach(this.posts, (post: TopicPost) => {
            TopicPostItem({
              post: post,
              lastReadPostNumber: this.detail?.lastReadPostNumber ?? -1,
              onOpenImages: (images: ViewerImage[], startIndex: number) => {
                this.openImageViewer(images, startIndex);
              },
              onOpenLink: (url: string) => {
                this.onOpenLink(url);
              },
              onToggleReaction: (targetPost: TopicPost, reaction: string, snapshot: ReactionSnapshot) => {
                this.handleToggleReaction(targetPost, reaction, snapshot);
              },
              onReply: (targetPost: TopicPost) => {
                this.openComposerForPost(targetPost);
              },
              onAddBoost: (targetPost: TopicPost) => {
                this.openComposerForBoost(targetPost);
              },
              onJumpToPost: (postNumber: number) => {
                this.jumpToPostNumber(postNumber);
              },
              onLoadReplies: (targetPost: TopicPost) => {
                return this.loadPostReplies(targetPost);
              },
              onVote: (targetPost: TopicPost, poll: Poll, optionIds: string[]) => {
                return this.handleVote(targetPost, poll, optionIds);
              },
              onRemoveVote: (targetPost: TopicPost, poll: Poll) => {
                return this.handleRemoveVote(targetPost, poll);
              },
              onCopyPostLink: (targetPost: TopicPost) => {
                this.handleCopyPostLink(targetPost);
              },
              onToggleBookmark: (targetPost: TopicPost) => {
                return this.handleToggleBookmark(targetPost);
              }
            })
          }, (post: TopicPost) => post.id.toString())

          if (this.posts.length > 0) {
            ListItem() {
              Row() {
                if (this.isLoadingMore) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color('#2563EB')
                    .margin({ right: 8 })
                }

                Text(this.loadMoreMessage)
                  .fontSize(13)
                  .fontColor('#9CA3AF')
              }
              .width('100%')
              .height(54)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onScrollIndex((start: number, end: number) => {
          // List 的 index 0 是 TopicSummary,楼层从 index 1 起 → 换算成 posts 下标再交给已读控制器。
          this.readController.onVisibleRange(start - 1, end - 1);
          // 摘要 ListItem 固定为 index 0:仍在视口内(start===0)显示"帖子详情",滑出后显示帖子标题与分类标签。
          this.summaryVisible = start === 0;
        })
        .onReachEnd(() => {
          this.loadMorePosts();
        })
      } else {
        this.StateContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    // 全屏时(composerFullScreen)主内容会整体上移一个状态栏高度;补等高顶部内边距抵消,背后视觉不动。
    // 绑 composerFullScreen 而非 showComposer:关闭时全屏延后落下,补偿也随之延后,避免关闭途中背景跳。
    .padding({ top: this.composerFullScreen ? this.composerWindowGuard.statusBarHeight : 0 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

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

    if (this.showImageViewer) {
      ImageViewer({
        images: this.viewerImages,
        startIndex: this.viewerStartIndex,
        onClose: () => {
          this.showImageViewer = false;
        }
      })
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
        // 直接发布:追加到楼层末尾;用新数组触发 List 刷新。
        const appended: TopicPost[] = this.posts.slice();
        appended.push(result.data.post);
        this.posts = appended;
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
      const target: TopicPost | undefined = PostStreamPager.findById(this.posts, postId);
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
  // 仅定位已加载楼:未加载(还没上拉到)时弹 toast 提示,不自动翻页。
  private jumpToPostNumber(postNumber: number): void {
    for (let index: number = 0; index < this.posts.length; index++) {
      if (this.posts[index].postNumber === postNumber) {
        this.scroller.scrollToIndex(index + 1, true);
        return;
      }
    }
    this.showComposerToast('该楼尚未加载', 1500);
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

  private openImageViewer(images: ViewerImage[], startIndex: number): void {
    this.viewerImages = images;
    this.viewerStartIndex = startIndex;
    this.showImageViewer = true;
  }

  @Builder
  private TopicSummary() {
    Column() {
      Text(this.getTitle())
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .width('100%')

      if (this.hasBadges()) {
        TopicMetadataBadges({
          category: CategoryIndex.find(this.categories, this.detail?.categoryId),
          parentCategory: CategoryIndex.findParent(this.categories, this.detail?.categoryId),
          tags: this.getTags()
        })
        .width('100%')
        .margin({ top: 8 })
      }

      Text(this.getTopicMetaText())
        .fontSize(12)
        .fontColor('#6B7280')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ top: 20, bottom: 16 })
    .border({
      width: { bottom: 1 },
      color: '#E5E7EB'
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private StateContent() {
    Column() {
      if (this.isLoading) {
        LoadingProgress()
          .width(30)
          .height(30)
          .color('#2563EB')
          .margin({ bottom: 12 })
      }

      Text(this.message)
        .fontSize(15)
        .fontColor(this.requiresChallenge ? '#B45309' : '#6B7280')
        .textAlign(TextAlign.Center)

      if (!this.isLoading && this.isArkWebReady) {
        Button('重试')
          .fontSize(15)
          .fontColor('#2563EB')
          .backgroundColor('#F3F4F6')
          .height(38)
          .padding({ left: 18, right: 18 })
          .borderRadius(19)
          .margin({ top: 16 })
          .onClick(() => {
            this.loadTopicDetail();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24 })
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
    console.info(`${LOG_TAG} load detail start topicId=${this.param.topicId} slug=${this.getSlugLabel()}`);

    const result: NetworkResult<TopicDetail> =
      await new TopicService(this.bridge).getTopicDetail(this.param.topicId, this.param.slug);

    this.isLoading = false;
    if (result.success && result.data) {
      this.detail = result.data;
      this.posts = result.data.posts;
      this.message = result.data.posts.length > 0 ? '' : '暂无帖子内容';
      this.hasMorePosts = PostStreamPager.countUnloaded(result.data.stream ?? [], this.posts) > 0;
      this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
      console.info(`${LOG_TAG} load detail success topicId=${result.data.id} posts=${result.data.posts.length} stream=${result.data.stream ? result.data.stream.length : 0}`);
      this.startReadingTrackerIfNeeded();
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.message = result.error?.message ? result.error.message : '帖子详情加载失败';
    console.info(`${LOG_TAG} load detail failed topicId=${this.param.topicId} status=${result.statusCode}`);
  }

  private async loadMorePosts(): Promise<void> {
    if (!this.detail || this.isLoadingMore || !this.hasMorePosts) {
      return;
    }
    const stream: number[] = this.detail.stream ? this.detail.stream : [];
    const nextIds: number[] = PostStreamPager.collectNextIds(stream, this.posts, POSTS_PAGE_SIZE);
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
      this.posts = PostStreamPager.append(this.posts, result.data);
      this.hasMorePosts = PostStreamPager.countUnloaded(stream, this.posts) > 0;
      this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
      console.info(`${LOG_TAG} load more topicId=${topicId} added=${result.data.length} total=${this.posts.length}`);
      return;
    }

    this.loadMoreMessage = result.error?.message ? `${result.error.message}，上拉重试` : '加载更多失败，上拉重试';
  }

  private startReadingTrackerIfNeeded(): void {
    const service: TopicService = new TopicService(this.bridge);
    this.readController.startIfNeeded(
      (id: number, timings: Map<number, number>, topicTime: number) => service.reportTimings(id, timings, topicTime),
      LOG_TAG
    );
  }

  // 切换某楼表情回应:先乐观更新(@Observed 即时重渲染),再发 PUT;失败回滚到快照。
  private async handleToggleReaction(post: TopicPost, reaction: string, snapshot: ReactionSnapshot): Promise<void> {
    const topicId: number = post.topicId !== undefined ? post.topicId : (this.detail?.id ?? 0);
    const result: NetworkResult<string> =
      await new TopicService(this.bridge).toggleReaction(post.id, topicId, reaction);

    if (!result.success) {
      console.info(`${LOG_TAG} toggle reaction failed postId=${post.id} reaction=${reaction} status=${result.statusCode}, rollback`);
      ReactionMutation.restore(post, snapshot);
    }
  }

  // 投票:先乐观更新模型,再发 PUT;成功用服务端真实值校正模型并回传给 PollView,失败回滚并回传 null。
  private async handleVote(post: TopicPost, poll: Poll, optionIds: string[]): Promise<PollVoteResult | null> {
    const topicId: number = post.topicId !== undefined ? post.topicId : (this.detail?.id ?? 0);
    const snapshot: PollSnapshot = PollMutation.snapshot(poll);
    PollMutation.applyVote(poll, optionIds);

    const result: NetworkResult<PollVoteResult> =
      await new TopicService(this.bridge).votePoll(post.id, topicId, poll.name, optionIds);

    if (result.success && result.data) {
      PollMutation.applyServerResult(poll, result.data);
      return result.data;
    }
    console.info(`${LOG_TAG} vote failed postId=${post.id} poll=${poll.name} status=${result.statusCode}, rollback`);
    PollMutation.restore(poll, snapshot);
    return null;
  }

  // 撤销投票:先乐观更新模型,再发 DELETE;成功用服务端真实值校正模型并回传,失败回滚并回传 null。
  private async handleRemoveVote(post: TopicPost, poll: Poll): Promise<PollVoteResult | null> {
    const topicId: number = post.topicId !== undefined ? post.topicId : (this.detail?.id ?? 0);
    const snapshot: PollSnapshot = PollMutation.snapshot(poll);
    PollMutation.applyRemove(poll);

    const result: NetworkResult<PollVoteResult> =
      await new TopicService(this.bridge).removePollVote(post.id, topicId, poll.name);

    if (result.success && result.data) {
      PollMutation.applyServerResult(poll, result.data);
      return result.data;
    }
    console.info(`${LOG_TAG} remove vote failed postId=${post.id} poll=${poll.name} status=${result.statusCode}, rollback`);
    PollMutation.restore(poll, snapshot);
    return null;
  }

  // 拷贝该楼永久链接到剪贴板:优先带 slug 的规范链接,缺 slug 时用 /t/topic/<id>/<楼号>(可正常跳转)。
  private handleCopyPostLink(post: TopicPost): void {
    const topicId: number = post.topicId !== undefined ? post.topicId : (this.detail?.id ?? 0);
    const slug: string | undefined = this.detail?.slug;
    const path: string = slug !== undefined && slug.length > 0
      ? `/t/${slug}/${topicId}/${post.postNumber}`
      : `/t/topic/${topicId}/${post.postNumber}`;
    const url: string = `${AppConstants.BASE_URL}${path}`;
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: '已复制链接', duration: 1500 });
    }).catch(() => {
    });
  }

  // 书签 toggle:post.bookmarked/bookmarkId 为网络侧真源,发网络+失败回滚;返回操作后的最终收藏态,
  // 交给子组件校正本地显示 @State(子组件负责乐观翻转与重渲染)。带 [ARKDO][Bookmark] 日志便于排查。
  private async handleToggleBookmark(post: TopicPost): Promise<boolean> {
    const topicId: number = post.topicId !== undefined ? post.topicId : (this.detail?.id ?? 0);
    const service: TopicService = new TopicService(this.bridge);
    const wasBookmarked: boolean = post.bookmarked === true;
    const prevId: number | undefined = post.bookmarkId;
    console.info(`[ARKDO][Bookmark] toggle start postId=${post.id} topicId=${topicId} wasBookmarked=${wasBookmarked} prevId=${prevId}`);

    if (wasBookmarked && prevId !== undefined) {
      post.bookmarked = false;
      post.bookmarkId = undefined;
      const result: NetworkResult<string> = await service.removeBookmark(prevId, topicId);
      console.info(`[ARKDO][Bookmark] remove result postId=${post.id} success=${result.success} status=${result.statusCode} challenge=${result.challengeState}`);
      if (result.success) {
        this.getUIContext().getPromptAction().showToast({ message: '已取消收藏', duration: 1500 });
      } else {
        post.bookmarked = true;
        post.bookmarkId = prevId;
        this.getUIContext().getPromptAction().showToast({ message: '取消收藏失败', duration: 1500 });
      }
    } else {
      post.bookmarked = true;
      const result: NetworkResult<number> = await service.addBookmark(post.id, topicId);
      console.info(`[ARKDO][Bookmark] add result postId=${post.id} success=${result.success} status=${result.statusCode} challenge=${result.challengeState} id=${result.data}`);
      if (result.success && result.data !== undefined) {
        post.bookmarkId = result.data;
        this.getUIContext().getPromptAction().showToast({ message: '已收藏', duration: 1500 });
      } else {
        post.bookmarked = false;
        post.bookmarkId = undefined;
        this.getUIContext().getPromptAction().showToast({ message: '收藏失败', duration: 1500 });
      }
    }
    console.info(`[ARKDO][Bookmark] toggle end postId=${post.id} finalBookmarked=${post.bookmarked} bookmarkId=${post.bookmarkId}`);
    return post.bookmarked === true;
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

    const postsCount: number = this.detail.postsCount ? this.detail.postsCount : this.posts.length;
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
