import { Log } from '../../services/logging/Log';
import { Topic, TopicCategory } from '../../models/Topic';
import { JsonNetworkClient, NetworkResult } from '../../services/network/NetworkTypes';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { TopicPage, TopicService } from '../../services/topic/TopicService';
import { TopicListItem } from '../components/TopicListItem';
import { LoadStateView } from '../components/LoadStateView';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { PageHeader } from '../components/PageHeader';
import { ListFooter } from '../components/ListFooter';

const LOG_TAG: string = '[ArkDO][ReadTopicsPage]';

// 已读帖子列表:数据源 /read.json(Discourse core 的 read 过滤器,即网页版 /u/{用户名}/activity/read),
// 只回当前登录用户读过的主题、按最近阅读排序。响应是标准 topic_list,整行复用首页 TopicListItem。
@Component
export struct ReadTopicsPage {
  // 窗口常驻全屏布局:根列自行避让状态栏(padding 在带背景的根列上,背景填满状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: JsonNetworkClient | undefined = undefined;
  isArkWebReady: boolean = false;
  onBack: () => void = () => {};
  onTopicClick: (topic: Topic) => void = () => {};
  // 有未读回复时跳到第一条未读楼(不高亮,只留红线),与首页未读徽标行为一致。
  onOpenTopicAtPost: (topic: Topic, postNumber: number) => void = () => {};

  @State private topics: Topic[] = [];
  @State private categories: TopicCategory[] = [];
  @State private isInitialLoading: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = true;
  @State private loadFailed: boolean = false;
  @State private message: string = '';
  private service?: TopicService = undefined;
  private categoryIndex: CategoryIndex = new CategoryIndex();
  // 已取到的最后一页页码,翻页时自增重拼路径(服务端只给 more_topics_url 的有无)。
  private currentPage: number = 0;
  private loading: boolean = false;

  aboutToAppear(): void {
    if (this.bridge) {
      this.service = new TopicService(this.bridge);
    }
    this.loadCategories();
    this.loadInitial();
  }

  build() {
    Column() {
      PageHeader({
        title: '已读',
        onBack: () => {
          this.onBack();
        }
      })

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
    if (this.topics.length === 0) {
      LoadStateView({
        isLoading: this.isInitialLoading,
        loadingText: '加载中…',
        message: this.message.length > 0 ? this.message : '加载失败',
        showRetry: this.loadFailed,
        emptyTitle: '还没有读过的帖子',
        onRetry: () => {
          this.loadInitial();
        }
      })
    } else {
      Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
        List() {
          ForEach(this.topics, (topic: Topic) => {
            TopicListItem({
              topic: topic,
              category: CategoryIndex.find(this.categories, topic.categoryId),
              parentCategory: CategoryIndex.findParent(this.categories, topic.categoryId),
              onTopicClick: (selectedTopic: Topic) => {
                selectedTopic.unseen = false;
                this.onTopicClick(selectedTopic);
              },
              onUnreadBadgeClick: (selectedTopic: Topic) => {
                this.handleUnreadBadgeClick(selectedTopic);
              }
            })
            // key 纳入 bookmarked:与首页同理,收藏态变化时强制重建该行绑新实例。
          }, (topic: Topic) => `${topic.id}_${topic.bookmarked === true ? 1 : 0}`)

          ListItem() {
            ListFooter({ isLoading: this.isLoadingMore, hasMore: this.hasMore })
          }
        }
        .width('100%')
        .layoutWeight(1)
        // 左右留白对齐首页帖子列表:TopicListItem 只带上下 padding,横向留白由 List 给。
        // 分隔线不用 List.divider:TopicListItem 自带底部 1px 边框,再加会画成两条。
        .padding({ left: 12, right: 12 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onReachEnd(() => {
          this.loadMore();
        })
      }
      .layoutWeight(1)
      // Refresh 会把子 List 裁剪到自身边界:子 List 的 expandSafeArea 穿不透,需在此同样声明。
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .pullToRefresh(true)
      .refreshOffset(64)
      .onRefreshing(() => {
        this.loadInitial();
      })
    }
  }

  // ==================== 数据加载 ====================

  private async loadInitial(): Promise<void> {
    if (!this.service || this.loading) {
      if (!this.service) {
        this.message = '正在准备请求环境';
        this.loadFailed = true;
      }
      this.isRefreshing = false;
      return;
    }
    const isFirstLoad: boolean = this.topics.length === 0;
    this.loading = true;
    this.isInitialLoading = isFirstLoad;
    this.isRefreshing = !isFirstLoad;
    this.loadFailed = false;

    const result: NetworkResult<TopicPage> = await this.service.getReadTopicsPage(0);
    this.loading = false;
    this.isInitialLoading = false;
    this.isRefreshing = false;

    if (!result.success || result.data === undefined) {
      this.loadFailed = true;
      this.message = result.error?.message ? result.error.message : '加载失败，请重试';
      Log.i(`${LOG_TAG} initial load failed status=${result.statusCode}`);
      return;
    }

    this.topics = result.data.topics;
    this.currentPage = 0;
    this.hasMore = result.data.hasMore;
    this.message = '';
    Log.i(`${LOG_TAG} initial loaded count=${this.topics.length} hasMore=${this.hasMore}`);
  }

  private async loadMore(): Promise<void> {
    if (!this.service || this.loading || !this.hasMore || this.topics.length === 0) {
      return;
    }
    this.loading = true;
    this.isLoadingMore = true;

    const nextPage: number = this.currentPage + 1;
    const result: NetworkResult<TopicPage> = await this.service.getReadTopicsPage(nextPage);
    this.loading = false;
    this.isLoadingMore = false;

    if (!result.success || result.data === undefined) {
      Log.i(`${LOG_TAG} load more failed page=${nextPage} status=${result.statusCode}`);
      return;
    }

    this.topics = this.mergeTopics(this.topics, result.data.topics);
    this.currentPage = nextPage;
    this.hasMore = result.data.hasMore && result.data.topics.length > 0;
  }

  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge as JsonNetworkClient, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  // ==================== 交互 ====================

  // 与首页同逻辑:跳到最后已读的下一楼(不越过最高楼号);无已读记录则从头打开。
  private handleUnreadBadgeClick(topic: Topic): void {
    topic.unseen = false;
    const lastRead: number = topic.lastReadPostNumber ?? 0;
    if (lastRead <= 0) {
      this.onTopicClick(topic);
      return;
    }
    let target: number = lastRead + 1;
    const highest: number = topic.highestPostNumber ?? 0;
    if (highest > 0 && target > highest) {
      target = highest;
    }
    this.onOpenTopicAtPost(topic, target);
  }

  // 按 id 去重后拼接:阅读顺序会随翻页变动,跨页可能重复回同一帖。
  private mergeTopics(existingTopics: Topic[], nextTopics: Topic[]): Topic[] {
    const seenTopicIds: Map<number, boolean> = new Map();
    const mergedTopics: Topic[] = [];

    for (let index: number = 0; index < existingTopics.length; index++) {
      const topic: Topic = existingTopics[index];
      seenTopicIds.set(topic.id, true);
      mergedTopics.push(topic);
    }

    for (let index: number = 0; index < nextTopics.length; index++) {
      const topic: Topic = nextTopics[index];
      if (!seenTopicIds.has(topic.id)) {
        seenTopicIds.set(topic.id, true);
        mergedTopics.push(topic);
      }
    }

    return mergedTopics;
  }
}
