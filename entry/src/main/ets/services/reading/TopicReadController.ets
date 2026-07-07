import { TopicDetail, TopicPost } from '../../models/TopicDetail';
import { AppStateEventBus } from '../session/AppStateEventBus';
import { TopicReadStateEventBus } from '../session/TopicReadStateEventBus';
import { ReadingTracker, ReportTimingsFn } from './ReadingTracker';

// 相邻楼层错峰翻已读的间隔:让蓝点淡出动画自上而下依次开始,对齐官网的级联观感。
const READ_STAGGER_STEP_MS: number = 80;

export type DetailProvider = () => TopicDetail | undefined;
export type PostsProvider = () => TopicPost[];

// 详情页已读追踪控制器:托管 ReadingTracker 的启停/焦点胶水、"已读到哪"的水位计算、
// 错峰翻已读动画,以及离开页面时把已读状态回传列表页(消蓝点、更新未读徽标)。
// 通过 provider 闭包读取页面 @State 的 detail/posts(posts 分页后会换新数组,不能在启动时捕获快照);
// 翻已读直接对 @Observed 的 TopicPost 赋值,由 @ObjectLink 精准重渲染,不经过页面。
export class TopicReadController {
  private getDetail: DetailProvider;
  private getPosts: PostsProvider;
  private tracker: ReadingTracker = new ReadingTracker();
  private started: boolean = false;
  private unsubscribeAppState?: () => void = undefined;
  private staggerTimers: number[] = [];
  // 本次浏览进入过视口的最高楼号:作为"已读到哪"的水位,用于返回时算真实剩余未读。
  // 比依赖停留时长的 post.read 更贴合"我看过了就算读了"的预期,避免徽标卡住不更新。
  private maxSeenPostNumber: number = 0;

  constructor(getDetail: DetailProvider, getPosts: PostsProvider) {
    this.getDetail = getDetail;
    this.getPosts = getPosts;
  }

  // 页面挂载:订阅 App 前后台切换,驱动阅读计时的焦点(对齐 Discourse session.hasFocus)。
  attach(): void {
    if (!this.unsubscribeAppState) {
      this.unsubscribeAppState = AppStateEventBus.subscribe((isForeground: boolean) => {
        this.tracker.setFocus(isForeground);
      });
    }
  }

  // 页面离开:先把当前已读状态回传列表页,再结算并停止计时(最后一次 flush 上报)、
  // 清掉未触发的错峰定时器与前后台订阅。
  detach(): void {
    this.publishReadStateToList();
    this.tracker.stop();
    this.started = false;

    for (let index: number = 0; index < this.staggerTimers.length; index++) {
      clearTimeout(this.staggerTimers[index]);
    }
    this.staggerTimers = [];

    if (this.unsubscribeAppState) {
      this.unsubscribeAppState();
      this.unsubscribeAppState = undefined;
    }
  }

  // 详情加载成功后启动计时上报。未登录时详情响应不含已读字段,不启动(匿名不 POST timings)。
  startIfNeeded(reportFn: ReportTimingsFn, logTag: string): void {
    const detail: TopicDetail | undefined = this.getDetail();
    if (this.started || !detail) {
      return;
    }
    if (!this.hasServerReadState()) {
      return;
    }

    this.tracker.setFocus(AppStateEventBus.isForeground());
    this.tracker.start(
      detail.id,
      reportFn,
      (postNumbers: number[]) => this.markPostsRead(postNumbers),
      (postNumbers: number[], reporting: boolean) => this.markPostsReporting(postNumbers, reporting)
    );
    this.tracker.seedRead(this.collectAlreadyReadPostNumbers());
    this.started = true;
    console.info(`${logTag} reading tracker started topicId=${detail.id}`);
  }

  // 可见楼层范围变化(入参为 posts 数组下标,列表头部占位的换算由页面完成):
  // 记录"看到过"的最高楼号水位、同步在屏楼层给计时器、刷新防挂机的滚动时间戳。
  // postEndIndex 可能落在底部"加载更多"占位上,超界则夹到最后一楼。
  onVisibleRange(postStartIndex: number, postEndIndex: number): void {
    const posts: TopicPost[] = this.getPosts();

    let seenIndex: number = postEndIndex;
    if (seenIndex >= posts.length) {
      seenIndex = posts.length - 1;
    }
    if (seenIndex >= 0) {
      const postNumber: number = posts[seenIndex].postNumber;
      if (postNumber > this.maxSeenPostNumber) {
        this.maxSeenPostNumber = postNumber;
      }
    }

    if (this.started) {
      const postNumbers: number[] = [];
      for (let index: number = postStartIndex; index <= postEndIndex; index++) {
        if (index >= 0 && index < posts.length) {
          postNumbers.push(posts[index].postNumber);
        }
      }
      this.tracker.setOnscreen(postNumbers);
    }

    this.tracker.scrolled();
  }

  // 离开详情页时把该主题的已读状态回传给列表页:
  // 蓝点消失(unseen=false),未读徽标 = 最高楼号 − 已读到的最高楼号(可能只加载了部分楼层,
  // 但 highestPostNumber/stream 在首屏就给了全量总数,所以未读数依然准确)。
  private publishReadStateToList(): void {
    const detail: TopicDetail | undefined = this.getDetail();
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
    const posts: TopicPost[] = this.getPosts();
    let highest: number = this.getDetail()?.highestPostNumber ?? 0;
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].postNumber > highest) {
        highest = posts[index].postNumber;
      }
    }
    return highest;
  }

  private highestReadPostNumber(): number {
    // 三个信号取最高:服务端加载时的旧水位、本次浏览到的最高楼号、已翻真的 read 楼号。
    const posts: TopicPost[] = this.getPosts();
    let watermark: number = this.getDetail()?.lastReadPostNumber ?? 0;
    if (this.maxSeenPostNumber > watermark) {
      watermark = this.maxSeenPostNumber;
    }
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
      if (post.read === true && post.postNumber > watermark) {
        watermark = post.postNumber;
      }
    }
    return watermark;
  }

  private hasServerReadState(): boolean {
    const detail: TopicDetail | undefined = this.getDetail();
    if (detail && detail.lastReadPostNumber !== undefined) {
      return true;
    }
    const posts: TopicPost[] = this.getPosts();
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].read !== undefined) {
        return true;
      }
    }
    return false;
  }

  private collectAlreadyReadPostNumbers(): number[] {
    const posts: TopicPost[] = this.getPosts();
    const watermark: number = this.getDetail()?.lastReadPostNumber ?? -1;
    const out: number[] = [];
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
      const read: boolean = post.read === true ||
        (post.read === undefined && watermark >= 0 && post.postNumber <= watermark);
      if (read) {
        out.push(post.postNumber);
      }
    }
    return out;
  }

  // 上报进行中:把本批楼层标记为 reporting,让蓝点进入"呼吸"态;结束(成功/失败)时清除。
  // 已翻已读的楼层跳过(它们已淡出,呼吸无意义)。直接改 @Observed 字段驱动 @ObjectLink 重渲染。
  private markPostsReporting(postNumbers: number[], reporting: boolean): void {
    const posts: TopicPost[] = this.getPosts();
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
      if (postNumbers.indexOf(post.postNumber) < 0) {
        continue;
      }
      if (reporting && post.read === true) {
        continue;
      }
      post.reporting = reporting;
    }
  }

  private markPostsRead(postNumbers: number[]): void {
    // 收集本批需新标已读的楼层,按楼号升序错峰(自上而下)翻已读。
    const posts: TopicPost[] = this.getPosts();
    const pending: TopicPost[] = [];
    for (let index: number = 0; index < posts.length; index++) {
      const post: TopicPost = posts[index];
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
      this.staggerTimers.push(timerId);
    }
  }
}
