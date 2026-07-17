import { Log } from '../../services/logging/Log';
import { TopicCategory } from '../../models/Topic';
import { SolvedPostItem, SolvedPostPage } from '../../models/UserProfile';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { JsonNetworkClient, NetworkResult } from '../../services/network/NetworkTypes';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { UserProfileService } from '../../services/user/UserProfileService';
import { TopicMetadataBadges } from '../components/TopicBadges';
import { LoadStateView } from '../components/LoadStateView';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';

const LOG_TAG: string = '[ArkDO][SolvedPostsPage]';
const PAGE_PADDING: number = 16;

// 某人被采纳为解决方案的回复列表(/solution/by_user.json,discourse-solved 插件)。
// 入口是他人主页统计格里的「解决方案」数字。Boosts/回应/投票 三个插件页没做——
// 它们对判断一个人几乎零贡献,而这个是「靠不靠谱」的硬证据。
//
// 与 ActivityListPage 的区别:不出头像。整页主语已经是目标用户,每行再挂一张
// 一模一样的他的头像是纯噪音(官网就是这么做的),去掉后省下宽度给答案正文。
@Component
export struct SolvedPostsPage {
  // 窗口常驻全屏布局:根列自行避让状态栏(padding 在带背景的根列上,背景填满状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: JsonNetworkClient | undefined = undefined;
  isArkWebReady: boolean = false;
  username: string = '';
  solvedCount: number = 0;
  onBack: () => void = () => {};
  onOpenTopic: (topicId: number, title: string, postNumber?: number) => void = () => {};

  @State private items: SolvedPostItem[] = [];
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

        Text(this.getPageTitle())
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
    .padding({ top: this.sysTopInset })
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private Content() {
    if (this.items.length === 0) {
      LoadStateView({
        isLoading: this.isInitialLoading,
        loadingText: '加载中…',
        message: this.message.length > 0 ? this.message : '加载失败',
        showRetry: this.loadFailed,
        emptyTitle: '还没有被采纳的答案',
        onRetry: () => {
          this.loadInitial();
        }
      })
    } else {
      Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
        List() {
          ForEach(this.items, (item: SolvedPostItem, index: number) => {
            ListItem() {
              this.SolvedRow(item)
            }
          }, (item: SolvedPostItem, index: number) => `${item.topicId}_${item.postNumber}_${index}`)

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

  // 单行:绿勾 + 右侧(话题标题 / 分类 + 时间 / 绿线引用答案)。
  // 缩进靠「勾号 + layoutWeight Column」自然形成,不给子行加 left margin——
  // width('100%') 再叠左边距会把行整体右推、日期被切出屏幕(之前的 BUG)。
  @Builder
  private SolvedRow(item: SolvedPostItem) {
    Row() {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(15)
        .fontColor([$r('app.color.ld_success')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .margin({ top: 2, right: 6 })

      Column() {
        Text(item.topicTitle)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          if (this.getCategoryFor(item.categoryId)) {
            TopicMetadataBadges({
              category: this.getCategoryFor(item.categoryId),
              parentCategory: this.getParentCategoryFor(item.categoryId),
              tags: []
            })
              .layoutWeight(1)
          } else {
            Blank()
          }
          Text(RelativeTime.fromNow(item.createdAt))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 5 })

        if (item.excerpt.length > 0) {
          Text(item.excerpt)
            .fontSize(14)
            .fontColor($r('app.color.text_body'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(21)
            .width('100%')
            .padding({ left: 10 })
            .border({ width: { left: 2 }, color: { left: $r('app.color.ld_success') } })
            .margin({ top: 8 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 12, bottom: 13 })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      // 落到他那条被采纳的楼层,不是话题首楼。
      this.onOpenTopic(item.topicId, item.topicTitle, item.postNumber);
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

    const result: NetworkResult<SolvedPostPage> = await this.service.getSolvedPosts(this.username, 0);
    this.loading = false;
    this.isInitialLoading = false;
    this.isRefreshing = false;

    if (!result.success || result.data === undefined) {
      this.loadFailed = true;
      this.message = result.error?.message ? result.error.message : '加载失败，请重试';
      Log.i(`${LOG_TAG} initial load failed user=${this.username} status=${result.statusCode}`);
      return;
    }

    this.items = result.data.items;
    this.hasMore = result.data.hasMore;
    this.message = '';
    Log.i(`${LOG_TAG} initial loaded user=${this.username} count=${this.items.length} hasMore=${this.hasMore}`);
  }

  private async loadMore(): Promise<void> {
    if (!this.service || this.loading || !this.hasMore || this.items.length === 0) {
      return;
    }
    this.loading = true;
    this.isLoadingMore = true;

    const result: NetworkResult<SolvedPostPage> =
      await this.service.getSolvedPosts(this.username, this.items.length);
    this.loading = false;
    this.isLoadingMore = false;

    if (!result.success || result.data === undefined) {
      Log.i(`${LOG_TAG} load more failed user=${this.username} status=${result.statusCode}`);
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

  private getPageTitle(): string {
    return this.solvedCount > 0 ? `解决方案 · ${this.solvedCount}` : '解决方案';
  }

  private getCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.find(this.categories, categoryId);
  }

  private getParentCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.findParent(this.categories, categoryId);
  }
}
