import { Topic, TopicCategory, TopicTag } from '../../models/Topic';
import { TopicMetadataBadges } from './TopicBadges';
import { UserAvatar } from './UserAvatar';

@Component
export struct TopicListItem {
  topic: Topic = {
    id: 0,
    title: '',
    tags: []
  };
  category?: TopicCategory;
  parentCategory?: TopicCategory;
  onTopicClick: (topic: Topic) => void = () => {};

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
            .width('100%')

          if (this.hasBadges()) {
            TopicMetadataBadges({
              category: this.category,
              parentCategory: this.parentCategory,
              tags: this.topic.tags
            })
            .width('100%')
            .margin({ top: 3})
          }

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
          .margin({ top: 4 })
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
      .onClick(() => {
        this.onTopicClick(this.topic);
      })
    }
  }

  private getAuthorUsername(): string {
    const username: string | undefined = this.topic.author?.username;
    if (!username) {
      return '未知用户';
    }
    return username;
  }

  private hasBadges(): boolean {
    return !!this.category || this.getTags().length > 0;
  }

  private getTags(): TopicTag[] {
    return this.topic.tags ? this.topic.tags : [];
  }
}
