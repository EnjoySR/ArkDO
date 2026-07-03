import { TopicDetailRouteParam } from '../../navigation/AppRoutes';
import { TopicDetail, TopicPost } from '../../models/TopicDetail';
import { User } from '../../models/User';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { TopicService } from '../../services/topic/TopicService';
import { TopicPostItem } from '../components/TopicPostItem';
import { UserAvatar } from '../components/UserAvatar';

const LOG_TAG: string = '[ArkDO][TopicDetail]';

@Component
export struct TopicDetailPage {
  @State private detail: TopicDetail | undefined = undefined;
  @State private posts: TopicPost[] = [];
  @State private isLoading: boolean = false;
  @State private message: string = '正在准备 ArkWeb 请求环境';
  @State private requiresChallenge: boolean = false;
  param: TopicDetailRouteParam = {
    topicId: 0,
    title: ''
  };
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  onBack: () => void = () => {};
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;

  aboutToAppear(): void {
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }

    if (this.isArkWebReady && !this.detail) {
      this.loadTopicDetail();
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
        Button('返回')
          .fontSize(15)
          .fontColor('#2563EB')
          .backgroundColor('#F3F4F6')
          .height(36)
          .padding({ left: 16, right: 16 })
          .borderRadius(18)
          .onClick(() => {
            this.onBack();
          })

        Text('帖子详情')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .margin({ left: 16 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
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
            TopicPostItem({ post: post })
          }, (post: TopicPost) => post.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20 })
      } else {
        this.StateContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private TopicSummary() {
    Column() {
      Text(this.getTitle())
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .width('100%')

      Row() {
        UserAvatar({ user: this.getOriginalAuthor(), avatarSize: 32 })
          .margin({ right: 10 })

        Column() {
          Text(this.getOriginalAuthorName())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getTopicMetaText())
            .fontSize(12)
            .fontColor('#6B7280')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: 14 })
      .alignItems(VerticalAlign.Center)
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
    console.info(`${LOG_TAG} load detail start topicId=${this.param.topicId} slug=${this.getSlugLabel()}`);

    const result: NetworkResult<TopicDetail> =
      await new TopicService(this.bridge).getTopicDetail(this.param.topicId, this.param.slug);

    this.isLoading = false;
    if (result.success && result.data) {
      this.detail = result.data;
      this.posts = result.data.posts;
      this.message = result.data.posts.length > 0 ? '' : '暂无帖子内容';
      console.info(`${LOG_TAG} load detail success topicId=${result.data.id} posts=${result.data.posts.length}`);
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.message = result.error?.message ? result.error.message : '帖子详情加载失败';
    console.info(`${LOG_TAG} load detail failed topicId=${this.param.topicId} status=${result.statusCode}`);
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady && !this.detail && !this.isLoading) {
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

  private getOriginalAuthor(): User | undefined {
    if (this.posts.length === 0) {
      return undefined;
    }
    return this.posts[0].author;
  }

  private getOriginalAuthorName(): string {
    const author: User | undefined = this.getOriginalAuthor();
    if (author?.displayName && author.displayName.length > 0) {
      return author.displayName;
    }
    if (author?.username && author.username.length > 0) {
      return author.username;
    }
    return '未知用户';
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

  private getSlugLabel(): string {
    if (!this.param.slug || this.param.slug.length === 0) {
      return '无';
    }
    return this.param.slug;
  }
}
