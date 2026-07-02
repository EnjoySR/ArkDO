import { Topic } from '../../models/Topic';
import { UserAvatar } from './UserAvatar';

@Component
export struct TopicListItem {
  topic: Topic = {
    id: 0,
    title: ''
  };

  build() {
    ListItem() {
      Row() {
        UserAvatar({ user: this.topic.author, avatarSize: 38 })
          .margin({ right: 12 })

        Column() {
          Text(this.topic.title)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row() {
            Text(this.getAuthorUsername())
              .fontSize(13)
              .fontColor('#6B7280')

            Text(`${this.topic.replyCount ? this.topic.replyCount : 0} 回复`)
              .fontSize(13)
              .fontColor('#6B7280')
              .margin({ left: 12 })

            Text(`${this.topic.likeCount ? this.topic.likeCount : 0} 赞`)
              .fontSize(13)
              .fontColor('#6B7280')
              .margin({ left: 12 })
          }
          .margin({ top: 8 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .border({
        width: { bottom: 1 },
        color: '#E5E7EB'
      })
      .alignItems(VerticalAlign.Top)
    }
  }

  private getAuthorUsername(): string {
    const username: string | undefined = this.topic.author?.username;
    if (!username) {
      return '未知用户';
    }
    return username;
  }
}
