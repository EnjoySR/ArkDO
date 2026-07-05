import { TopicCategory, TopicTag } from '../../models/Topic';
import { TopicCategoryBadge } from './TopicCategoryBadge';
import { TopicTagBadge } from './TopicTagBadge';

@Component
export struct TopicMetadataBadges {
  category?: TopicCategory;
  parentCategory?: TopicCategory;
  tags: TopicTag[] = [];

  build() {
    Scroll() {
      Row() {
        if (this.category) {
          TopicCategoryBadge({
            category: this.category as TopicCategory,
            parentCategory: this.parentCategory
          })
        }

        ForEach(this.tags, (tag: TopicTag) => {
          TopicTagBadge({ tag: tag })
        }, (tag: TopicTag, index: number) => `${index}-${tag.name}`)
      }
      .height(20)
      .constraintSize({ minWidth: '100%' })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(20)
  }
}
