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
  // 已解决(有采纳答案):滚动后的帖子标题(图层 B)行首内联绿色 far-square-check 标记,与顶部摘要卡一致。
  @Prop solved: boolean = false;
  // 已收藏:图层 B 帖子标题最前内联灰色书签标记,排在已解决勾选框之前。
  @Prop bookmarked: boolean = false;
  onBack: () => void = () => {};
  // 点顶栏帖子标题回一楼。只在图层 B(帖子标题)显示时可点——摘要仍在视口内时一楼就在眼前,
  // 且那时显示的是「帖子详情」静态标题,点它没有意义(图层 B 的 hitTestBehavior 已天然做到这点)。
  onTitleClick: () => void = () => {};
  // 过盾快捷入口:仅在「用户开了设置开关」且「本次阅读确实被盾拦下」时显示,由父页判定后传入。
  // 不做常驻——多数时候没盾可过,常驻只会占地方。
  @Prop showChallengeShortcut: boolean = false;
  onChallengeShortcutClick: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([$r('app.color.text_primary')])
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
          // 已解决时行首内联绿色勾选框标记(同摘要卡:烘 #090 的专用 SVG,ImageSpan 内联随文字排)。
          Text() {
            // 书签排在已解决之前:烘 #919191 专用 SVG,ImageSpan 内联随文字排。
            if (this.bookmarked) {
              ImageSpan($rawfile('fa_icons/bookmark-gray.svg'))
                .width(15)
                .height(15)
                .margin({ right: 5 })
                .verticalAlign(ImageSpanAlignment.CENTER)
            }
            if (this.solved) {
              ImageSpan($rawfile('fa_icons/far-square-check-green.svg'))
                .width(15)
                .height(15)
                .margin({ right: 5 })
                .verticalAlign(ImageSpanAlignment.CENTER)
            }
            Span(this.title)
          }
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
        // 整行(标题 + 徽章)都是回一楼的热区。摘要可见时 hitTestBehavior 为 None,点不到,无需再判。
        .onClick(() => {
          this.onTitleClick();
        })
      }
      .layoutWeight(1)
      .alignContent(Alignment.Start)

      // 过盾快捷入口。不随标题双层切换隐藏——「被盾拦着」是当前会话的状态,
      // 与用户滑到了哪儿无关,跟着标题层走反而会让人以为问题自己好了。
      if (this.showChallengeShortcut) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize(20)
            .fontColor([$r('app.color.warning')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.surface_muted'))
        .onClick(() => {
          this.onChallengeShortcutClick();
        })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.page_bg'))
    .border({
      width: { bottom: 1 },
      color: $r('app.color.border')
    })
  }
}
