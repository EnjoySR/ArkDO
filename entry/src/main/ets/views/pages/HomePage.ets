import { AppConstants } from '../../common/constants/AppConstants';
import { Topic } from '../../models/Topic';
import { ArkWebHost } from '../components/ArkWebHost';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { TopicService } from '../../services/topic/TopicService';

@Component
export struct HomePage {
  @State private topics: Topic[] = [];
  @State private isLoading: boolean = false;
  @State private statusMessage: string = '正在准备 ArkWeb 请求环境';
  @State private requiresChallenge: boolean = false;
  private bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private topicService: TopicService = new TopicService(this.bridge);

  build() {
    Column() {
      ArkWebHost({
        bridge: this.bridge,
        onReady: () => {
          this.loadLatestTopics();
        }
      })

      Row() {
        Text(AppConstants.APP_NAME)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')

        Blank()

        Button(this.isLoading ? '加载中' : '刷新')
          .fontSize(14)
          .enabled(!this.isLoading)
          .onClick(() => {
            this.loadLatestTopics();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 12 })

      Column() {
        Text('最新帖子')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')

        Text(this.statusMessage)
          .fontSize(14)
          .fontColor(this.requiresChallenge ? '#B45309' : '#4B5563')
          .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .backgroundColor('#F3F4F6')

      Scroll() {
        Column() {
          if (this.topics.length === 0) {
            Text(this.isLoading ? '正在请求 /latest.json' : '暂无帖子数据')
              .fontSize(15)
              .fontColor('#6B7280')
              .width('100%')
              .padding({ top: 24 })
          }

          ForEach(this.topics, (topic: Topic) => {
            Column() {
              Text(topic.title)
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('#111827')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Row() {
                Text(topic.author?.username ? topic.author?.username : '未知用户')
                  .fontSize(13)
                  .fontColor('#6B7280')

                Text(`${topic.replyCount ? topic.replyCount : 0} 回复`)
                  .fontSize(13)
                  .fontColor('#6B7280')
                  .margin({ left: 12 })

                Text(`${topic.likeCount ? topic.likeCount : 0} 赞`)
                  .fontSize(13)
                  .fontColor('#6B7280')
                  .margin({ left: 12 })
              }
              .margin({ top: 8 })
            }
            .width('100%')
            .padding({ top: 14, bottom: 14 })
            .border({
              width: { bottom: 1 },
              color: '#E5E7EB'
            })
            .alignItems(HorizontalAlign.Start)
          }, (topic: Topic) => topic.id.toString())
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  private async loadLatestTopics(): Promise<void> {
    if (this.isLoading) {
      return;
    }

    this.isLoading = true;
    this.requiresChallenge = false;
    this.statusMessage = '正在通过 ArkWeb 请求 /latest.json';

    const result: NetworkResult<Topic[]> = await this.topicService.getLatestTopics();
    this.isLoading = false;

    if (result.success && result.data) {
      this.topics = result.data;
      this.statusMessage = `已加载 ${result.data.length} 个最新帖子`;
      return;
    }

    this.topics = [];
    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.statusMessage = result.error?.message ? result.error.message : '最新帖子加载失败';
  }
}
