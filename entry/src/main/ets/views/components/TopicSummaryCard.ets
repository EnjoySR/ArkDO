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

  build() {
    Column() {
      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
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
        .fontColor('#6B7280')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 20, bottom: 16 })
    .border({
      width: { bottom: 1 },
      color: '#E5E7EB'
    })
    .alignItems(HorizontalAlign.Start)
  }

  private hasBadges(): boolean {
    return this.category !== undefined || this.tags.length > 0;
  }
}
