import { TopicCategory, TopicTag } from '../../models/Topic';
import { TopicMetadataBadges } from './TopicBadges';

// 详情页顶部摘要卡:标题 + 分类/标签徽章 + 统计行。作为 List 的首个 ListItem 内容。
// 标题/分类随详情与站点元数据异步到达而变化 → @Prop 保持与父组件同步刷新。
@Component
export struct TopicSummaryCard {
  @Prop title: string = '';
  @Prop category: TopicCategory | undefined = undefined;
  @Prop parentCategory: TopicCategory | undefined = undefined;
  @Prop tags: TopicTag[] = [];
  @Prop metaText: string = '';
  // 已解决(有采纳答案):标题行首内联一个绿色 far-square-check 标记。
  @Prop solved: boolean = false;
  // 已收藏:标题最前内联一个灰色书签标记,排在已解决勾选框之前。
  @Prop bookmarked: boolean = false;

  build() {
    Column() {
      // 标题:solved 时行首内联绿色勾选框标记。ImageSpan 无 fillColor、colorFilter 对矢量 SVG 不生效,
      // 故用已烘 #090 的专用 SVG 变体(同 download_blue 先例);内联进 Text 才随标题文字换行同排。
      Text() {
        // 书签排在已解决之前:烘 #919191 专用 SVG,ImageSpan 内联随标题文字换行同排。
        if (this.bookmarked) {
          ImageSpan($rawfile('fa_icons/bookmark-gray.svg'))
            .width(20)
            .height(20)
            .margin({ right: 6 })
            .verticalAlign(ImageSpanAlignment.CENTER)
        }
        if (this.solved) {
          ImageSpan($rawfile('fa_icons/far-square-check-green.svg'))
            .width(20)
            .height(20)
            .margin({ right: 6 })
            .verticalAlign(ImageSpanAlignment.CENTER)
        }
        Span(this.title)
      }
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (this.hasBadges()) {
        TopicMetadataBadges({
          category: this.category,
          parentCategory: this.parentCategory,
          tags: this.tags
        })
        .width('100%')
        .margin({ top: 8 })
      }

      Text(this.metaText)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 20, bottom: 16 })
    .border({
      width: { bottom: 1 },
      color: $r('app.color.border')
    })
    .alignItems(HorizontalAlign.Start)
  }

  private hasBadges(): boolean {
    return this.category !== undefined || this.tags.length > 0;
  }
}
