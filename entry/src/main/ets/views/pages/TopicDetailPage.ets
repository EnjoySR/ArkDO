import { TopicDetailRouteParam } from '../../navigation/AppRoutes';
import { TopicDetail, TopicPost } from '../../models/TopicDetail';
import { TopicCategory, TopicTag } from '../../models/Topic';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { AppStateEventBus } from '../../services/session/AppStateEventBus';
import { TopicReadStateEventBus } from '../../services/session/TopicReadStateEventBus';
import { ReadingTracker } from '../../services/reading/ReadingTracker';
import { ReactionMutation, ReactionSnapshot } from '../../services/topic/ReactionMutation';
import { TopicService } from '../../services/topic/TopicService';
import { SiteMetadata, SiteService } from '../../services/site/SiteService';
import { TopicMetadataBadges } from '../components/TopicBadges';
import { TopicPostItem } from '../components/TopicPostItem';
import { ImageViewer, ViewerImage } from '../components/ImageViewer';

const LOG_TAG: string = '[ArkDO][TopicDetail]';
const READ_STAGGER_STEP_MS: number = 80;
const POSTS_PAGE_SIZE: number = 20;

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
  param: TopicDetailRouteParam = {
    topicId: 0,
    title: ''
  };
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  onBack: () => void = () => {};
  private isSiteMetadataLoading: boolean = false;
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;
  private readingTracker: ReadingTracker = new ReadingTracker();
  private unsubscribeAppState?: () => void = undefined;
  private trackerStarted: boolean = false;
  private readStaggerTimers: number[] = [];
  // 本次浏览进入过视口的最高楼号:作为"已读到哪"的水位,用于返回时算真实剩余未读。
  // 比依赖停留时长的 post.read 更贴合"我看过了就算读了"的预期,避免徽标卡住不更新。
  private maxSeenPostNumber: number = 0;

  aboutToAppear(): void {
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }

    if (!this.unsubscribeAppState) {
      // App 前后台驱动阅读计时的焦点(对齐 Discourse session.hasFocus)。
      this.unsubscribeAppState = AppStateEventBus.subscribe((isForeground: boolean) => {
        this.readingTracker.setFocus(isForeground);
      });
    }

    if (this.isArkWebReady && !this.detail) {
      this.loadSiteMetadataIfNeeded();
      this.loadTopicDetail();
    }
  }

  aboutToDisappear(): void {
    // 先把当前已读状态回传列表页(消蓝点、更新真实剩余未读数),再做清理。
    this.publishReadStateToList();

    // 离开页面:结算并停止阅读计时(会做最后一次 flush 上报)。
    this.readingTracker.stop();
    this.trackerStarted = false;

    // 清掉未触发的错峰淡出定时器。
    for (let index: number = 0; index < this.readStaggerTimers.length; index++) {
      clearTimeout(this.readStaggerTimers[index]);
    }
    this.readStaggerTimers = [];

    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
    if (this.unsubscribeAppState) {
      this.unsubscribeAppState();
      this.unsubscribeAppState = undefined;
    }
  }

  build() {
    Stack() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(28)
            .fontColor([Color.Black])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
        .width(40)
        .height(40)
        .backgroundColor('#E6E8E9')
        .onClick(() => {
          this.onBack();
        })

        // 两种标题内容始终挂载、叠层显示,靠 opacity+translate 随 summaryVisible 做淡入+竖向上滑切换。
        Stack({ alignContent: Alignment.Start }) {
          // 图层 A:摘要在视口内时显示的静态标题「帖子详情」。
          Text('帖子详情')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .opacity(this.summaryVisible ? 1 : 0)
            .translate({ y: this.summaryVisible ? 0 : -8 })
            .hitTestBehavior(this.summaryVisible ? HitTestMode.Default : HitTestMode.None)
            .animation({ duration: 250, curve: Curve.EaseInOut })

          // 图层 B:摘要滑出后显示的帖子标题 + 分类/标签行。
          Column({ space: 2 }) {
            Text(this.getTitle())
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            if (this.hasBadges()) {
              TopicMetadataBadges({
                category: this.findCategory(this.detail?.categoryId),
                parentCategory: this.findParentCategory(this.detail?.categoryId),
                tags: this.getTags()
              })
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
          .opacity(this.summaryVisible ? 0 : 1)
          .translate({ y: this.summaryVisible ? 8 : 0 })
          .hitTestBehavior(this.summaryVisible ? HitTestMode.None : HitTestMode.Default)
          .animation({ duration: 250, curve: Curve.EaseInOut })
        }
        .layoutWeight(1)
        .alignContent(Alignment.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')
      .border({
        width: { bottom: 1 },
        color: '#E5E7EB'
      })

      if (this.detail) {
        List() {
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
              onToggleReaction: (targetPost: TopicPost, reaction: string, snapshot: ReactionSnapshot) => {
                this.handleToggleReaction(targetPost, reaction, snapshot);
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
          this.trackMaxSeenPostNumber(end);
          this.updateOnscreenPosts(start, end);
          this.readingTracker.scrolled();
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

    if (this.showImageViewer) {
      ImageViewer({
        images: this.viewerImages,
        startIndex: this.viewerStartIndex,
        onClose: () => {
          this.showImageViewer = false;
        }
      })
    }
    }
    .width('100%')
    .height('100%')
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
          category: this.findCategory(this.detail?.categoryId),
          parentCategory: this.findParentCategory(this.detail?.categoryId),
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
      this.hasMorePosts = this.countUnloadedPosts() > 0;
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
    const nextIds: number[] = this.collectNextPostIds(stream);
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
      this.appendPosts(result.data);
      this.hasMorePosts = this.countUnloadedPosts() > 0;
      this.loadMoreMessage = this.hasMorePosts ? '上拉加载更多' : '没有更多了';
      console.info(`${LOG_TAG} load more topicId=${topicId} added=${result.data.length} total=${this.posts.length}`);
      return;
    }

    this.loadMoreMessage = result.error?.message ? `${result.error.message}，上拉重试` : '加载更多失败，上拉重试';
  }

  private collectNextPostIds(stream: number[]): number[] {
    const loadedIds: Set<number> = this.buildLoadedIdSet();
    const nextIds: number[] = [];
    for (let index: number = 0; index < stream.length && nextIds.length < POSTS_PAGE_SIZE; index++) {
      if (!loadedIds.has(stream[index])) {
        nextIds.push(stream[index]);
      }
    }
    return nextIds;
  }

  private appendPosts(newPosts: TopicPost[]): void {
    const loadedIds: Set<number> = this.buildLoadedIdSet();
    const merged: TopicPost[] = this.posts.slice();
    for (let index: number = 0; index < newPosts.length; index++) {
      const post: TopicPost = newPosts[index];
      if (!loadedIds.has(post.id)) {
        loadedIds.add(post.id);
        merged.push(post);
      }
    }
    this.posts = merged;
  }

  private countUnloadedPosts(): number {
    const stream: number[] = this.detail?.stream ? this.detail.stream : [];
    const loadedIds: Set<number> = this.buildLoadedIdSet();
    let count: number = 0;
    for (let index: number = 0; index < stream.length; index++) {
      if (!loadedIds.has(stream[index])) {
        count++;
      }
    }
    return count;
  }

  private buildLoadedIdSet(): Set<number> {
    const loadedIds: Set<number> = new Set();
    for (let index: number = 0; index < this.posts.length; index++) {
      loadedIds.add(this.posts[index].id);
    }
    return loadedIds;
  }

  private startReadingTrackerIfNeeded(): void {
    if (this.trackerStarted || !this.detail) {
      return;
    }
    // 未登录时详情响应不含已读字段,不启动上报(匿名不 POST timings)。
    if (!this.hasServerReadState()) {
      return;
    }

    const topicId: number = this.detail.id;
    const service: TopicService = new TopicService(this.bridge);
    this.readingTracker.setFocus(AppStateEventBus.isForeground());
    this.readingTracker.start(
      topicId,
      (id: number, timings: Map<number, number>, topicTime: number) => service.reportTimings(id, timings, topicTime),
      (postNumbers: number[]) => this.markPostsRead(postNumbers)
    );
    this.readingTracker.seedRead(this.collectAlreadyReadPostNumbers());
    this.trackerStarted = true;
    console.info(`${LOG_TAG} reading tracker started topicId=${topicId}`);
  }

  // 离开详情页时把该主题的已读状态回传给列表页:
  // 蓝点消失(unseen=false),未读徽标 = 最高楼号 − 已读到的最高楼号(可能只加载了部分楼层,
  // 但 highestPostNumber/stream 在首屏就给了全量总数,所以未读数依然准确)。
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

  private publishReadStateToList(): void {
    const detail: TopicDetail | undefined = this.detail;
    if (!detail) {
      return;
    }
    // 匿名或响应无已读态时不上报,避免把服务端真实状态误清。
    if (!this.hasServerReadState()) {
      return;
    }

    const highest: number = this.highestKnownPostNumber();
    const highestRead: number = this.highestReadPostNumber();
    const unread: number = Math.max(0, highest - highestRead);
    TopicReadStateEventBus.publish({
      topicId: detail.id,
      unseen: false,
      unreadPosts: unread
    });
  }

  private highestKnownPostNumber(): number {
    let highest: number = this.detail?.highestPostNumber ?? 0;
    for (let index: number = 0; index < this.posts.length; index++) {
      if (this.posts[index].postNumber > highest) {
        highest = this.posts[index].postNumber;
      }
    }
    return highest;
  }

  private highestReadPostNumber(): number {
    // 三个信号取最高:服务端加载时的旧水位、本次浏览到的最高楼号、已翻真的 read 楼号。
    let watermark: number = this.detail?.lastReadPostNumber ?? 0;
    if (this.maxSeenPostNumber > watermark) {
      watermark = this.maxSeenPostNumber;
    }
    for (let index: number = 0; index < this.posts.length; index++) {
      const post: TopicPost = this.posts[index];
      if (post.read === true && post.postNumber > watermark) {
        watermark = post.postNumber;
      }
    }
    return watermark;
  }

  // List 的 index 0 是 TopicSummary,楼层从 index 1 起 → posts[end - 1] 是当前可见的最后一楼。
  // end 可能落在底部"加载更多"占位上,超界则夹到最后一楼。
  private trackMaxSeenPostNumber(endListIndex: number): void {
    let postIndex: number = endListIndex - 1;
    if (postIndex >= this.posts.length) {
      postIndex = this.posts.length - 1;
    }
    if (postIndex >= 0 && postIndex < this.posts.length) {
      const postNumber: number = this.posts[postIndex].postNumber;
      if (postNumber > this.maxSeenPostNumber) {
        this.maxSeenPostNumber = postNumber;
      }
    }
  }

  private hasServerReadState(): boolean {
    if (this.detail && this.detail.lastReadPostNumber !== undefined) {
      return true;
    }
    for (let index: number = 0; index < this.posts.length; index++) {
      if (this.posts[index].read !== undefined) {
        return true;
      }
    }
    return false;
  }

  private collectAlreadyReadPostNumbers(): number[] {
    const watermark: number = this.detail?.lastReadPostNumber ?? -1;
    const out: number[] = [];
    for (let index: number = 0; index < this.posts.length; index++) {
      const post: TopicPost = this.posts[index];
      const read: boolean = post.read === true ||
        (post.read === undefined && watermark >= 0 && post.postNumber <= watermark);
      if (read) {
        out.push(post.postNumber);
      }
    }
    return out;
  }

  private updateOnscreenPosts(start: number, end: number): void {
    if (!this.trackerStarted) {
      return;
    }
    // List 的 index 0 是 TopicSummary,楼层从 index 1 起 → posts[index - 1]。
    const postNumbers: number[] = [];
    for (let index: number = start; index <= end; index++) {
      const postIndex: number = index - 1;
      if (postIndex >= 0 && postIndex < this.posts.length) {
        postNumbers.push(this.posts[postIndex].postNumber);
      }
    }
    this.readingTracker.setOnscreen(postNumbers);
  }

  private markPostsRead(postNumbers: number[]): void {
    // 收集本批需新标已读的楼层,按楼号升序错峰(自上而下)翻已读,
    // 让各自的蓝点淡出动画依次开始,对齐官网的级联观感。
    const pending: TopicPost[] = [];
    for (let index: number = 0; index < this.posts.length; index++) {
      const post: TopicPost = this.posts[index];
      if (post.read !== true && postNumbers.indexOf(post.postNumber) >= 0) {
        pending.push(post);
      }
    }
    if (pending.length === 0) {
      return;
    }

    pending.sort((a: TopicPost, b: TopicPost) => a.postNumber - b.postNumber);
    for (let order: number = 0; order < pending.length; order++) {
      const post: TopicPost = pending[order];
      // @Observed 实例赋值 → TopicPostItem(@ObjectLink)重渲染 → 蓝点淡出。
      const timerId: number = setTimeout(() => {
        post.read = true;
      }, order * READ_STAGGER_STEP_MS);
      this.readStaggerTimers.push(timerId);
    }
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
    if (!this.isArkWebReady || this.isSiteMetadataLoading || this.categories.length > 0) {
      return;
    }

    this.isSiteMetadataLoading = true;
    const result: NetworkResult<SiteMetadata> = await new SiteService(this.bridge).getSiteMetadata();
    this.isSiteMetadataLoading = false;

    if (result.success && result.data) {
      this.categories = result.data.categories;
      console.info(`${LOG_TAG} site metadata loaded categories=${result.data.categories.length}`);
      return;
    }

    console.info(`${LOG_TAG} site metadata skipped status=${result.statusCode}`);
  }

  private findCategory(categoryId?: number): TopicCategory | undefined {
    if (!categoryId || this.categories.length === 0) {
      return undefined;
    }

    for (let index: number = 0; index < this.categories.length; index++) {
      const category: TopicCategory = this.categories[index];
      if (category.id === categoryId) {
        return category;
      }
    }
    return undefined;
  }

  private findParentCategory(categoryId?: number): TopicCategory | undefined {
    const category: TopicCategory | undefined = this.findCategory(categoryId);
    if (!category || !category.parentCategoryId) {
      return undefined;
    }
    return this.findCategory(category.parentCategoryId);
  }

  private hasBadges(): boolean {
    return this.findCategory(this.detail?.categoryId) !== undefined || this.getTags().length > 0;
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
