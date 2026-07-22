import { Topic, TopicCategory, TopicTag } from '../../models/Topic';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { FONT_BODY_LARGE } from '../../common/theme/Metrics';
import { TopicMetadataBadges } from './TopicBadges';
import { UserAvatar } from './UserAvatar';

// 摘要高亮分段:hit 为命中词(染品牌色),否则普通文本。
interface BlurbSegment {
  text: string;
  hit: boolean;
}

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
  // 搜索场景高亮词(空格拆分的普通关键词):在 searchBlurb 摘要里把命中词染色。普通 feed 传空。
  searchHighlights: string[] = [];

  build() {
    ListItem() {
      Row() {
        UserAvatar({ user: this.topic.author, avatarSize: 48 })
          .margin({ right: 8 })

        Column() {
          // 未读徽标 / 小蓝点都作为内联 Span 追加在标题文本流末尾,始终贴在最后一行文字后面。
          // 二者互斥:有未读回复 → 蓝色数字药丸(左右加空格撑开背景);否则(全新主题)→ 小蓝点。
          // 未读标记不做 baselineOffset:ArkUI 会把偏移后的内联 Span 纳入行盒计算,
          // 多行标题会因此比没有标记的标题显得行距更松。父 Text 用 textVerticalAlign
          // 让不同字号的 Span 在单行内视觉居中。
          // 药丸内部用不换行空格( )撑背景:普通空格是可断行点,标题换行时会从药丸左边的空格处
          // 断开,导致半截蓝色背景留在上一行;换成   后药丸不可拆,断行只发生在它前面的引导空格,
          // 整个药丸连背景一起下移到新行。
          Text() {
            // 书签:已收藏时标题最前内联灰色书签标记(烘 #919191 专用 SVG,同已解决走 ImageSpan 内联)。
            // 排在已解决勾选框之前。
            if (this.topic.bookmarked === true) {
              ImageSpan($rawfile('fa_icons/bookmark-gray.svg'))
                .width(15)
                .height(15)
                .margin({ right: 5 })
                .verticalAlign(ImageSpanAlignment.CENTER)
            }
            // 已解决:标题行首内联绿色勾选框标记(烘 #090 专用 SVG,ImageSpan 内联随标题文字换行同排)。
            if (this.topic.hasAcceptedAnswer === true) {
              ImageSpan($rawfile('fa_icons/far-square-check-green.svg'))
                .width(15)
                .height(15)
                .margin({ right: 5 })
                .verticalAlign(ImageSpanAlignment.CENTER)
            }
            // 标题:搜索场景把命中词染品牌色(逐段拆 Span);普通 feed 保持单 Span 不变。
            if (this.searchHighlights.length > 0) {
              ForEach(this.titleSegments(), (seg: BlurbSegment, index: number) => {
                Span(seg.text)
                  .fontColor(seg.hit ? $r('app.color.brand') : $r('app.color.text_body'))
                  .fontWeight(FontWeight.Medium)
              }, (seg: BlurbSegment, index: number) => `t${index}`)
            } else {
              Span(this.topic.title)
            }
            if (this.hasUnreadBadge()) {
              // 无背景的普通空格作外间距兼唯一可断点:药丸整体在此换行,不会被拆。
              Span('  ')
                .fontSize(12)
              Span(` ${this.topic.unreadPosts} `)
                .fontSize(12)
                .fontColor(Color.White)
                // 未读标记蓝:语义强调色,明暗底都成立,保留字面量(勿映射 ld_accent,白天会变深蓝)。
                .textBackgroundStyle({ color: '#66CCFF', radius: 9 })
            } else if (this.topic.unseen === true) {
              Span(' ●')
                .fontSize(8)
                .fontColor('#66CCFF')
            }
          }
          .fontSize(FONT_BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_body'))
          .lineHeight(23)
          .textVerticalAlign(TextVerticalAlign.CENTER)
          .width('100%')

          // 搜索命中摘要:标题下一行灰字,命中词染品牌色。仅搜索结果(topic.searchBlurb 有值)显示。
          if (this.topic.searchBlurb !== undefined && this.topic.searchBlurb.length > 0) {
            Text() {
              ForEach(this.blurbSegments(), (seg: BlurbSegment, index: number) => {
                Span(seg.text)
                  .fontColor(seg.hit ? $r('app.color.brand') : $r('app.color.text_secondary'))
                  .fontWeight(seg.hit ? FontWeight.Medium : FontWeight.Regular)
              }, (seg: BlurbSegment, index: number) => `${index}`)
            }
            .fontSize(13)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
          }

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

  private blurbSegments(): BlurbSegment[] {
    return this.segmentsOf(this.topic.searchBlurb ?? '');
  }

  private titleSegments(): BlurbSegment[] {
    return this.segmentsOf(this.topic.title);
  }

  // 把文本按高亮词切成 [普通/命中] 分段:大小写不敏感,逐字符找最早出现的任一命中词。标题/摘要共用。
  private segmentsOf(text: string): BlurbSegment[] {
    if (text.length === 0) {
      return [];
    }
    const terms: string[] = [];
    for (let i: number = 0; i < this.searchHighlights.length; i++) {
      const term: string = this.searchHighlights[i];
      if (term.length > 0) {
        terms.push(term.toLowerCase());
      }
    }
    if (terms.length === 0) {
      return [{ text: text, hit: false }];
    }

    const lower: string = text.toLowerCase();
    const segments: BlurbSegment[] = [];
    let cursor: number = 0;
    while (cursor < text.length) {
      let bestPos: number = -1;
      let bestLen: number = 0;
      for (let i: number = 0; i < terms.length; i++) {
        const pos: number = lower.indexOf(terms[i], cursor);
        if (pos >= 0 && (bestPos < 0 || pos < bestPos)) {
          bestPos = pos;
          bestLen = terms[i].length;
        }
      }
      if (bestPos < 0) {
        segments.push({ text: text.slice(cursor), hit: false });
        break;
      }
      if (bestPos > cursor) {
        segments.push({ text: text.slice(cursor, bestPos), hit: false });
      }
      segments.push({ text: text.slice(bestPos, bestPos + bestLen), hit: true });
      cursor = bestPos + bestLen;
    }
    return segments;
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
