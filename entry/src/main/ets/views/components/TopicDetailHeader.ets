import { TopicCategory, TopicTag } from '../../models/Topic';
import { TopicMetadataBadges } from './TopicBadges';

// 详情页头部:返回键 + 双层标题。两种标题内容始终挂载、叠层显示,
// 靠 opacity+translate 随 summaryVisible 做淡入+竖向上滑切换:
// 摘要(标题/分类/标签)仍在视口内时显示静态标题「帖子详情」,滑出后切换为帖子标题与分类标签行。
@Component
export struct TopicDetailHeader {
  @Prop summaryVisible: boolean = true;
  // 标题与分类/标签随详情、站点元数据异步到达而变化 → 用 @Prop 保持与父组件同步刷新。
  @Prop title: string = '';
  @Prop showBadges: boolean = false;
  @Prop category: TopicCategory | undefined = undefined;
  @Prop parentCategory: TopicCategory | undefined = undefined;
  @Prop tags: TopicTag[] = [];
  onBack: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([$r('app.color.icon_secondary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.surface_muted'))
      .onClick(() => {
        this.onBack();
      })

      Stack({ alignContent: Alignment.Start }) {
        // 图层 A:摘要在视口内时显示的静态标题「帖子详情」。
        Text('帖子详情')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .opacity(this.summaryVisible ? 1 : 0)
          .translate({ y: this.summaryVisible ? 0 : -8 })
          .hitTestBehavior(this.summaryVisible ? HitTestMode.Default : HitTestMode.None)
          .animation({ duration: 250, curve: Curve.EaseInOut })

        // 图层 B:摘要滑出后显示的帖子标题 + 分类/标签行。
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.showBadges) {
            TopicMetadataBadges({
              category: this.category,
              parentCategory: this.parentCategory,
              tags: this.tags
            })
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .opacity(this.summaryVisible ? 0 : 1)
        .translate({ y: this.summaryVisible ? 8 : 0 })
        .hitTestBehavior(this.summaryVisible ? HitTestMode.None : HitTestMode.Default)
        .animation({ duration: 250, curve: Curve.EaseInOut })
      }
      .layoutWeight(1)
      .alignContent(Alignment.Start)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .height(60)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.page_bg'))
    .border({
      width: { bottom: 1 },
      color: $r('app.color.border')
    })
  }
}
