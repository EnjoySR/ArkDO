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
  // 有未读回复时整行点击走这里:直跳详情页第一条未读楼(无未读则走 onTopicClick 从头打开)。
  onUnreadBadgeClick: (topic: Topic) => void = () => {};

  build() {
    ListItem() {
      Row() {
        UserAvatar({ user: this.topic.author, avatarSize: 48 })
          .margin({ right: 8 })

        Column() {
          // 未读徽标 / 小蓝点都作为内联 Span 追加在标题文本流末尾,始终贴在最后一行文字后面。
          // 二者互斥:有未读回复 → 蓝色数字药丸(左右加空格撑开背景);否则(全新主题)→ 小蓝点。
          // 用 baselineOffset 把标记从基线上抬,对齐 CJK 文字视觉重心。
          // 药丸内部用不换行空格( )撑背景:普通空格是可断行点,标题换行时会从药丸左边的空格处
          // 断开,导致半截蓝色背景留在上一行;换成   后药丸不可拆,断行只发生在它前面的引导空格,
          // 整个药丸连背景一起下移到新行。
          Text() {
            Span(this.topic.title)
            if (this.hasUnreadBadge()) {
              // 无背景的普通空格作外间距兼唯一可断点:药丸整体在此换行,不会被拆。
              Span('  ')
                .fontSize(12)
              Span(` ${this.topic.unreadPosts} `)
                .fontSize(12)
                .fontColor(Color.White)
                // 未读标记蓝:语义强调色,明暗底都成立,保留字面量(勿映射 ld_accent,白天会变深蓝)。
                .textBackgroundStyle({ color: '#66CCFF', radius: 9 })
                .baselineOffset(LengthMetrics.vp(2))
            } else if (this.topic.unseen === true) {
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

          // 分类 / 标签 与 时间同一行:徽标占剩余宽度可横向滚动,时间固定在最右侧。
          if (this.hasBadges() || this.getRelativeTime().length > 0) {
            Row() {
              if (this.hasBadges()) {
                TopicMetadataBadges({
                  category: this.category,
                  parentCategory: this.parentCategory,
                  tags: this.topic.tags
                })
                .layoutWeight(1)
              } else {
                Blank()
              }

              if (this.getRelativeTime().length > 0) {
                Text(this.getRelativeTime())
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ left: 8 })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 3 })
          }
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
        // 有未读徽标 → 整行点击直跳第一条未读楼;否则从第 1 层打开。
        if (this.hasUnreadBadge()) {
          this.onUnreadBadgeClick(this.topic);
        } else {
          this.onTopicClick(this.topic);
        }
      })
    }
  }

  private hasUnreadBadge(): boolean {
    return this.topic.unreadPosts !== undefined && this.topic.unreadPosts > 0;
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
