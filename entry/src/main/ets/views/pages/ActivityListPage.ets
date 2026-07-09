import { Log } from '../../services/logging/Log';
import { TopicCategory } from '../../models/Topic';
import { UserActionType, UserActivityItem, UserActivityPage } from '../../models/UserProfile';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { JsonNetworkClient, NetworkResult } from '../../services/network/NetworkTypes';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { UserProfileService } from '../../services/user/UserProfileService';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { TopicMetadataBadges } from '../components/TopicBadges';

const LOG_TAG: string = '[ArkDO][ActivityListPage]';
const PAGE_PADDING: number = 16;

// 通用用户动态列表:我的话题(filter=4)、我的回复(5)、我的点赞(1)、最近活动全部(4,5)。
// 数据源统一为 /user_actions.json,按 offset 翻页。
@Component
export struct ActivityListPage {
  bridge: JsonNetworkClient | undefined = undefined;
  isArkWebReady: boolean = false;
  username: string = '';
  filter: string = '4,5';
  pageTitle: string = '动态';
  onBack: () => void = () => {};
  onOpenTopic: (topicId: number, title: string, postNumber?: number) => void = () => {};

  @State private items: UserActivityItem[] = [];
  @State private categories: TopicCategory[] = [];
  @State private isInitialLoading: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = true;
  @State private loadFailed: boolean = false;
  @State private message: string = '';
  private service?: UserProfileService = undefined;
  private categoryIndex: CategoryIndex = new CategoryIndex();
  private loading: boolean = false;

  aboutToAppear(): void {
    if (this.bridge) {
      this.service = new UserProfileService(this.bridge);
    }
    this.loadCategories();
    this.loadInitial();
  }

  build() {
    Column() {
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

        Text(this.pageTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 8 })

      this.Content()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private Content() {
    if (this.items.length === 0) {
      Column() {
        if (this.isInitialLoading) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.ld_accent'))
            .margin({ bottom: 12 })
          Text('加载中...')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
        } else if (this.loadFailed) {
          Text(this.message.length > 0 ? this.message : '加载失败')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
          Button('重试')
            .fontSize(15)
            .fontColor($r('app.color.ld_accent'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(20)
            .padding({ left: 28, right: 28, top: 8, bottom: 8 })
            .margin({ top: 16 })
            .onClick(() => {
              this.loadInitial();
            })
        } else {
          Text('这里还没有内容')
            .fontSize(15)
            .fontColor($r('app.color.text_faint'))
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
        List() {
          ForEach(this.items, (item: UserActivityItem, index: number) => {
            ListItem() {
              this.ActivityRow(item)
            }
          }, (item: UserActivityItem, index: number) => `${item.topicId}_${item.postNumber ?? 0}_${index}`)

          ListItem() {
            Row() {
              if (this.isLoadingMore) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color($r('app.color.ld_accent'))
                  .margin({ right: 8 })
              }
              Text(this.hasMore ? '上拉加载更多' : '没有更多了')
                .fontSize(13)
                .fontColor($r('app.color.text_faint'))
            }
            .width('100%')
            .height(54)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.border'), startMargin: 0, endMargin: 0 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onReachEnd(() => {
          this.loadMore();
        })
      }
      .layoutWeight(1)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onRefreshing(() => {
        this.loadInitial();
      })
    }
  }

  // 单行:标题(回复带 ↩ 图标)+ 分类徽标 + 摘要(2 行)+ 时间。
  @Builder
  private ActivityRow(item: UserActivityItem) {
    Column() {
      Row() {
        if (item.actionType === UserActionType.REPLY) {
          FaIconView({
            icon: this.faIcon('reply'),
            iconSize: 13,
            color: $r('app.color.text_faint')
          })
            .margin({ top: 3, right: 6 })
        }
        Text(item.title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.hasBadges(item)) {
        TopicMetadataBadges({
          category: this.getCategoryFor(item.categoryId),
          parentCategory: this.getParentCategoryFor(item.categoryId),
          tags: item.tags
        })
          .width('100%')
          .margin({ top: 5 })
      }

      if (item.excerpt.length > 0) {
        Text(item.excerpt)
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(21)
          .margin({ top: 6 })
      }

      Row() {
        Blank()
        Text(RelativeTime.fromNow(item.createdAt))
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 12, bottom: 13 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpenTopic(item.topicId, item.title, item.postNumber);
    })
  }

  // ==================== 数据加载 ====================

  private async loadInitial(): Promise<void> {
    if (!this.service || this.loading) {
      if (!this.service) {
        this.message = '正在准备请求环境';
      }
      this.isRefreshing = false;
      return;
    }
    const isFirstLoad: boolean = this.items.length === 0;
    this.loading = true;
    this.isInitialLoading = isFirstLoad;
    this.isRefreshing = !isFirstLoad;
    this.loadFailed = false;

    const result: NetworkResult<UserActivityPage> = await this.service.getActivity(this.username, this.filter, 0);
    this.loading = false;
    this.isInitialLoading = false;
    this.isRefreshing = false;

    if (!result.success || result.data === undefined) {
      this.loadFailed = true;
      this.message = result.error?.message ? result.error.message : '加载失败，请重试';
      Log.i(`${LOG_TAG} initial load failed filter=${this.filter} status=${result.statusCode}`);
      return;
    }

    this.items = result.data.items;
    this.hasMore = result.data.hasMore;
    this.message = '';
    Log.i(`${LOG_TAG} initial loaded filter=${this.filter} count=${this.items.length} hasMore=${this.hasMore}`);
  }

  private async loadMore(): Promise<void> {
    if (!this.service || this.loading || !this.hasMore || this.items.length === 0) {
      return;
    }
    this.loading = true;
    this.isLoadingMore = true;

    const result: NetworkResult<UserActivityPage> =
      await this.service.getActivity(this.username, this.filter, this.items.length);
    this.loading = false;
    this.isLoadingMore = false;

    if (!result.success || result.data === undefined) {
      Log.i(`${LOG_TAG} load more failed filter=${this.filter} status=${result.statusCode}`);
      return;
    }
    if (result.data.items.length === 0) {
      this.hasMore = false;
      return;
    }
    this.items = this.items.concat(result.data.items);
    this.hasMore = result.data.hasMore;
  }

  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge as JsonNetworkClient, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  // ==================== 展示辅助 ====================

  private hasBadges(item: UserActivityItem): boolean {
    return this.getCategoryFor(item.categoryId) !== undefined || item.tags.length > 0;
  }

  private getCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.find(this.categories, categoryId);
  }

  private getParentCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.findParent(this.categories, categoryId);
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }
}
