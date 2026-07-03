import { AppConstants } from '../../common/constants/AppConstants';
import { Topic } from '../../models/Topic';
import { TopicListItem } from '../components/TopicListItem';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { TopicPage, TopicService } from '../../services/topic/TopicService';

const LOG_TAG: string = '[ArkDO][Home]';

@Component
export struct HomePage {
  @State private topics: Topic[] = [];
  @State private isInitialLoading: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = true;
  @State private currentPage: number = 0;
  @State private listMessage: string = '正在准备 ArkWeb 请求环境';
  @State private footerMessage: string = '上拉加载更多';
  @State private requiresChallenge: boolean = false;
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  onTopicClick: (topic: Topic) => void = () => {};
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;

  aboutToAppear(): void {
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }
    this.syncSessionVersion();
    if (this.isArkWebReady && this.topics.length === 0) {
      this.refreshLatestTopics();
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
  }

  build() {
    Column() {
      Row() {
        Text(AppConstants.APP_NAME)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 12 })

      Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
        List() {
          if (this.topics.length === 0) {
            ListItem() {
              Column() {
                if (this.isInitialLoading) {
                  LoadingProgress()
                    .width(28)
                    .height(28)
                    .color('#2563EB')
                    .margin({ bottom: 12 })
                }

                Text(this.listMessage)
                  .fontSize(15)
                  .fontColor(this.requiresChallenge ? '#B45309' : '#6B7280')
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height(240)
              .justifyContent(FlexAlign.Center)
            }
          }

          ForEach(this.topics, (topic: Topic) => {
            TopicListItem({
              topic: topic,
              onTopicClick: (selectedTopic: Topic) => {
                this.onTopicClick(selectedTopic);
              }
            })
          }, (topic: Topic) => topic.id.toString())

          if (this.topics.length > 0) {
            ListItem() {
              Row() {
                if (this.isLoadingMore) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color('#2563EB')
                    .margin({ right: 8 })
                }

                Text(this.footerMessage)
                  .fontSize(13)
                  .fontColor(this.requiresChallenge ? '#B45309' : '#6B7280')
              }
              .width('100%')
              .height(54)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 20, right: 20 })
        .onReachEnd(() => {
          this.loadMoreTopics();
        })
      }
      .width('100%')
      .layoutWeight(1)
      .pullToRefresh(true)
      .refreshOffset(64)
      .onRefreshing(() => {
        this.refreshLatestTopics();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  private async refreshLatestTopics(): Promise<void> {
    if (!this.isArkWebReady) {
      this.listMessage = '正在准备 ArkWeb 请求环境';
      return;
    }

    if (this.isRefreshing || this.isLoadingMore) {
      return;
    }

    this.isRefreshing = true;
    this.isInitialLoading = this.topics.length === 0;
    this.requiresChallenge = false;
    this.listMessage = '正在加载最新帖子';
    this.footerMessage = '上拉加载更多';

    const result: NetworkResult<TopicPage> = await new TopicService(this.bridge).getLatestTopicsPage(0);
    this.isRefreshing = false;
    this.isInitialLoading = false;

    if (result.success && result.data) {
      this.topics = result.data.topics;
      this.currentPage = 0;
      this.hasMore = result.data.hasMore;
      this.listMessage = result.data.topics.length > 0 ? '' : '暂无帖子数据';
      this.footerMessage = this.hasMore ? '上拉加载更多' : '没有更多了';
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    if (this.topics.length === 0) {
      this.listMessage = result.error?.message ? result.error.message : '最新帖子加载失败';
    } else {
      this.footerMessage = result.error?.message ? result.error.message : '刷新失败';
    }
  }

  private async loadMoreTopics(): Promise<void> {
    if (!this.isArkWebReady) {
      this.footerMessage = '正在准备 ArkWeb 请求环境';
      return;
    }

    if (this.isRefreshing || this.isLoadingMore || !this.hasMore || this.topics.length === 0) {
      return;
    }

    this.isLoadingMore = true;
    this.requiresChallenge = false;
    this.footerMessage = '正在加载更多';

    const nextPage: number = this.currentPage + 1;
    const result: NetworkResult<TopicPage> = await new TopicService(this.bridge).getLatestTopicsPage(nextPage);
    this.isLoadingMore = false;

    if (result.success && result.data) {
      this.topics = this.mergeTopics(this.topics, result.data.topics);
      this.currentPage = nextPage;
      this.hasMore = result.data.hasMore && result.data.topics.length > 0;
      this.footerMessage = this.hasMore ? '上拉加载更多' : '没有更多了';
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.footerMessage = result.error?.message ? `${result.error.message}，上拉重试` : '加载失败，上拉重试';
  }

  private handleSessionChanged(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    this.handledSessionVersion = version;
    console.info(`${LOG_TAG} session changed version=${version}, refresh latest topics`);
    this.footerMessage = '会话已更新，正在刷新';
    this.refreshLatestTopics();
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady && this.topics.length === 0) {
      this.refreshLatestTopics();
    }
  }

  private syncSessionVersion(): void {
    this.handleSessionChanged(SessionEventBus.getCurrentVersion());
  }

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
      if (!seenTopicIds.get(topic.id)) {
        seenTopicIds.set(topic.id, true);
        mergedTopics.push(topic);
      }
    }

    return mergedTopics;
  }
}
