import { LengthMetrics } from '@kit.ArkUI';
import { Topic, TopicCategory, TopicTag } from '../../models/Topic';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { TopicMetadataBadges } from './TopicBadges';
import { UserAvatar } from './UserAvatar';

@Component
export struct TopicListItem {
  // @ObjectLink 绑定 @Observed 的 Topic:点击已读 / 返回同步未读数时精准触发本行重渲染。
  // 由父组件 ForEach 传入,不能有默认值。
  @ObjectLink topic: Topic;
  category?: TopicCategory;
  parentCategory?: TopicCategory;
  onTopicClick: (topic: Topic) => void = () => {};
  // 点未读数字徽标:直跳详情页第一条未读楼(与整行点击从头打开区分)。
  onUnreadBadgeClick: (topic: Topic) => void = () => {};

  build() {
    ListItem() {
      Row() {
        UserAvatar({ user: this.topic.author, avatarSize: 48 })
          .margin({ right: 8 })

        Column() {
          // 蓝点作为内联 Span 追加在标题文本流末尾,始终贴在最后一行文字后面(对齐官网)。
          // 用 baselineOffset 把圆点从基线上抬,对齐 CJK 文字视觉重心(否则看着偏下)。
          Text() {
            Span(this.topic.title)
            if (this.topic.unseen === true) {
              Span(' ●')
                .fontSize(8)
                .fontColor('#66CCFF')
                .baselineOffset(LengthMetrics.vp(2))
            }
          }
          .fontSize(18)
          .fontWeight(FontWeight.Regular)
          .fontColor($r('app.color.text_primary'))
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
            Row() {
              // 有未读回复 → 蓝色数字徽标顶替"N 回复";否则显示回复数。
              if (this.hasUnreadBadge()) {
                Text(`${this.topic.unreadPosts}`)
                  .fontSize(12)
                  .fontColor(Color.White)
                  .backgroundColor('#66CCFF')
                  .borderRadius(9)
                  .padding({ left: 7, right: 7, top: 1, bottom: 1 })
                  // 徽标点击直跳未读楼:热区四向外扩(徽标本体太小),Block 阻止事件穿透到整行。
                  .responseRegion({ x: '-50%', y: '-80%', width: '200%', height: '260%' })
                  .hitTestBehavior(HitTestMode.Block)
                  .onClick(() => {
                    this.onUnreadBadgeClick(this.topic);
                  })
              } else {
                Text(`${this.getReplyCount()} 回复`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }

              Text('·')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 8, right: 8 })

              Text(`${this.topic.likeCount ? this.topic.likeCount : 0} 赞`)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }

            if (this.getRelativeTime().length > 0) {
              Text(this.getRelativeTime())
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .border({
        width: { bottom: 1 },
        color: $r('app.color.border')
      })
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        this.onTopicClick(this.topic);
      })
    }
  }

  private hasUnreadBadge(): boolean {
    return this.topic.unreadPosts !== undefined && this.topic.unreadPosts > 0;
  }

  // 回复数口径与网页一致:总楼层数减去主楼(posts_count - 1)。
  private getReplyCount(): number {
    const postsCount: number | undefined = this.topic.postsCount;
    if (typeof postsCount === 'number' && postsCount > 0) {
      return postsCount - 1;
    }
    return 0;
  }

  private getRelativeTime(): string {
    return RelativeTime.fromNow(this.topic.lastPostedAt);
  }

  private hasBadges(): boolean {
    return !!this.category || this.getTags().length > 0;
  }

  private getTags(): TopicTag[] {
    return this.topic.tags ? this.topic.tags : [];
  }
}
