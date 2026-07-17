import { TopicCategory, TopicTag } from '../../models/Topic';
import { TopicCategoryBadge } from './TopicCategoryBadge';
import { TopicTagBadge } from './TopicTagBadge';

// 判定内容溢出的容差(vp):浮点抖动下别把「刚好装下」误判成可滚。
const OVERFLOW_EPSILON: number = 1;

@Component
export struct TopicMetadataBadges {
  category?: TopicCategory;
  parentCategory?: TopicCategory;
  tags: TopicTag[] = [];
  // 标签行实际宽度与视口宽度:两者比出「装不装得下」。
  // Row 上有 minWidth:'100%',故内容宽恒 ≥ 视口宽,只需判大于。
  @State private contentWidth: number = 0;
  @State private viewportWidth: number = 0;

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
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.contentWidth = newArea.width as number;
      })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(20)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewportWidth = newArea.width as number;
    })
    // 装得下就别认领横向手势:Scroll 默认无论内容是否溢出都照吃不误,
    // 会把整个列表区的横向滑动(如首页左滑)在标签行上截胡。
    .enableScrollInteraction(this.contentWidth - this.viewportWidth > OVERFLOW_EPSILON)
  }
}
