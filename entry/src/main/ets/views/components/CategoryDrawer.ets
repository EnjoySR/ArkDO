import { TopicCategory } from '../../models/Topic';
import { FeedDef, FeedKey, FeedPrefs } from '../../services/site/FeedPrefs';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { getCategoryColor, getCategoryIcon, getCategoryLogo, resolveBadgeAssetUrl } from './TopicBadgeUtils';

const ROW_HEIGHT: number = 48;
const COLOR_BAR_WIDTH: number = 4;

// @Builder 收单个对象参数(ArkTS/Rollup 对多参数 @Builder 会报 Argument name clash)。
interface CategoryRowParams {
  category: TopicCategory;
  isChild: boolean;
  // 图标兜底用的父版块;顶级版块传自身。
  parent: TopicCategory;
}

/**
 * 首页版块抽屉:顶部内置入口区(最新 + 设置页启用的可选入口),下接可折叠的两级版块树。
 * 未登录时 readRestricted 版块与 requiresLogin 入口置灰加锁/隐藏。选中项高亮。
 */
@Component
export struct CategoryDrawer {
  // 分类异步加载,@Prop 才能在父组件更新后同步进抽屉(普通成员变量只在创建时赋值一次)。
  @Prop categories: TopicCategory[] = [];
  @Prop isLoggedIn: boolean = false;
  // 设置页启用且有序的可选入口 key(不含 latest)。
  @Prop enabledFeedKeys: string[] = [];
  // 当前选中的内置入口 key;选中的是某版块时传空串。
  @Prop selectedFeedKey: string = FeedKey.LATEST;
  // 当前选中版块 id;未选版块时为 0。
  @Prop selectedCategoryId: number = 0;
  onSelectFeed: (feedKey: string) => void = () => {};
  onSelectCategory: (category: TopicCategory) => void = () => {};
  // 点了受限版块/需登录入口:交给宿主拉起登录。
  onRequireLogin: () => void = () => {};
  @State private expandedIds: number[] = [];

  aboutToAppear(): void {
    // 若当前选中的是某子版块,自动展开其父,让选中项可见。
    const selected: TopicCategory | undefined = this.findCategory(this.selectedCategoryId);
    if (selected && selected.parentCategoryId !== undefined) {
      this.expandedIds = [selected.parentCategoryId];
    }
  }

  build() {
    Column() {
      Text('版块')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 18, bottom: 10 })

      Scroll() {
        Column() {
          // 内置入口区
          ForEach(this.visibleFeeds(), (feed: FeedDef) => {
            this.FeedRow(feed)
          }, (feed: FeedDef) => feed.key)

          Divider()
            .strokeWidth(0.5)
            .color($r('app.color.border'))
            .margin({ left: 16, right: 16, top: 6, bottom: 6 })

          // 版块树:顶级版块 + (展开时)子版块
          ForEach(this.topLevelCategories(), (topCat: TopicCategory) => {
            // 顶级版块自身作图标兜底(getCategoryIcon 先看自身、再看父,自作父为无副作用空操作)。
            this.CategoryRow({ category: topCat, isChild: false, parent: topCat })
            if (this.isExpanded(topCat.id)) {
              ForEach(this.childrenOf(topCat.id), (child: TopicCategory) => {
                this.CategoryRow({ category: child, isChild: true, parent: topCat })
              }, (child: TopicCategory) => `c${child.id}`)
            }
          }, (topCat: TopicCategory) => `p${topCat.id}`)

          Row().width('100%').height(24)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ==================== Builder ====================

  @Builder
  private FeedRow(feed: FeedDef) {
    Row() {
      Row()
        .width(COLOR_BAR_WIDTH)
        .height(20)
        .borderRadius(2)
        .backgroundColor(this.isFeedSelected(feed.key) ? $r('app.color.brand') : Color.Transparent)
        .margin({ right: 12 })

      Text(feed.label)
        .fontSize(15)
        .fontWeight(this.isFeedSelected(feed.key) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.isFeedSelected(feed.key) ? $r('app.color.brand') : $r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 12, right: 16 })
    .backgroundColor(this.isFeedSelected(feed.key) ? $r('app.color.surface_muted') : Color.Transparent)
    .onClick(() => {
      this.onSelectFeed(feed.key);
    })
  }

  @Builder
  private CategoryRow(p: CategoryRowParams) {
    Row() {
      // 前导图标:与帖子列表分类徽章同款——图标 → 上传 logo → 兜底色点(子版块回退父版块)。
      Row() {
        if (getCategoryIcon(p.category, p.parent)) {
          FaIconView({
            icon: getCategoryIcon(p.category, p.parent) as FaIconDefinition,
            color: getCategoryColor(p.category),
            iconSize: 15
          })
        } else if (getCategoryLogo(p.category, p.parent).length > 0) {
          Image(resolveBadgeAssetUrl(getCategoryLogo(p.category, p.parent)))
            .width(15)
            .height(15)
            .objectFit(ImageFit.Contain)
        } else {
          Circle()
            .width(11)
            .height(11)
            .fill(getCategoryColor(p.category))
        }
      }
      .width(18)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 10 })

      Text(p.category.name)
        .fontSize(p.isChild ? 14 : 15)
        .fontWeight(this.isCategorySelected(p.category.id) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.isCategorySelected(p.category.id) ? $r('app.color.brand') : $r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.isRestricted(p.category)) {
        FaIconView({
          icon: this.getLockIcon() as FaIconDefinition,
          color: $r('app.color.text_faint'),
          iconSize: 12
        })
          .margin({ left: 6, right: 4 })
      } else if (!p.isChild && this.hasChildren(p.category.id)) {
        // 箭头单独热区:点它只折叠/展开子版块,不进入版块(行其余部分才是「浏览该版块」)。
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.text_faint')])
            .rotate({ angle: this.isExpanded(p.category.id) ? 90 : 0 })
        }
        .height('100%')
        .padding({ left: 10, right: 4 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.toggleExpand(p.category.id);
        })
      }
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: p.isChild ? 28 : 12, right: 16 })
    .opacity(this.isRestricted(p.category) ? 0.45 : 1)
    .backgroundColor(this.isCategorySelected(p.category.id) ? $r('app.color.surface_muted') : Color.Transparent)
    .onClick(() => {
      this.handleCategoryTap(p.category);
    })
  }

  // ==================== 交互 ====================

  private handleCategoryTap(category: TopicCategory): void {
    // 受限版块:拉起登录;否则浏览该版块(顶级版块本身也可浏览,展开靠右侧箭头独立热区)。
    if (this.isRestricted(category)) {
      this.onRequireLogin();
      return;
    }
    this.onSelectCategory(category);
  }

  private toggleExpand(id: number): void {
    const next: number[] = this.expandedIds.slice();
    const index: number = next.indexOf(id);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(id);
    }
    this.expandedIds = next;
  }

  // ==================== 数据 ====================

  private visibleFeeds(): FeedDef[] {
    const feeds: FeedDef[] = [FeedPrefs.latestFeed()];
    for (let index: number = 0; index < this.enabledFeedKeys.length; index++) {
      const def: FeedDef | undefined = FeedPrefs.feedDef(this.enabledFeedKeys[index]);
      if (def && (!def.requiresLogin || this.isLoggedIn)) {
        feeds.push(def);
      }
    }
    return feeds;
  }

  private topLevelCategories(): TopicCategory[] {
    const result: TopicCategory[] = [];
    for (let index: number = 0; index < this.categories.length; index++) {
      if (this.categories[index].parentCategoryId === undefined && !this.isHiddenCategory(this.categories[index])) {
        result.push(this.categories[index]);
      }
    }
    return result;
  }

  // 过滤 Discourse 默认的「未分类」版块(slug=uncategorized),不在版块列表里展示。
  private isHiddenCategory(category: TopicCategory): boolean {
    return category.slug === 'uncategorized';
  }

  private childrenOf(parentId: number): TopicCategory[] {
    const result: TopicCategory[] = [];
    for (let index: number = 0; index < this.categories.length; index++) {
      if (this.categories[index].parentCategoryId === parentId) {
        result.push(this.categories[index]);
      }
    }
    return result;
  }

  private hasChildren(parentId: number): boolean {
    for (let index: number = 0; index < this.categories.length; index++) {
      if (this.categories[index].parentCategoryId === parentId) {
        return true;
      }
    }
    return false;
  }

  private findCategory(id: number): TopicCategory | undefined {
    if (id <= 0) {
      return undefined;
    }
    for (let index: number = 0; index < this.categories.length; index++) {
      if (this.categories[index].id === id) {
        return this.categories[index];
      }
    }
    return undefined;
  }

  private isExpanded(id: number): boolean {
    return this.expandedIds.indexOf(id) >= 0;
  }

  private isRestricted(category: TopicCategory): boolean {
    return category.readRestricted === true && !this.isLoggedIn;
  }

  private isFeedSelected(key: string): boolean {
    return this.selectedCategoryId <= 0 && this.selectedFeedKey === key;
  }

  private isCategorySelected(id: number): boolean {
    return this.selectedCategoryId === id;
  }

  private getLockIcon(): FaIconDefinition | undefined {
    return getFaIcon('lock');
  }
}
