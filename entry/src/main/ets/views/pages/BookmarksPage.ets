import { Log } from '../../services/logging/Log';
import { LoginGate } from '../../services/session/LoginGate';
import { Bookmark, BookmarkPage } from '../../models/Bookmark';
import { TopicCategory } from '../../models/Topic';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { BookmarkService } from '../../services/bookmark/BookmarkService';
import { JsonNetworkClient, NetworkResult } from '../../services/network/NetworkTypes';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { UserAvatar } from '../components/UserAvatar';
import { LoadStateView } from '../components/LoadStateView';
import { TopicMetadataBadges } from '../components/TopicBadges';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { showToast as promptToast } from '../../common/utils/Toast';

const LOG_TAG: string = '[ArkDO][BookmarksPage]';
const PAGE_PADDING: number = 16;

@Component
export struct BookmarksPage {
  // 窗口常驻全屏布局:根列自行避让状态栏(padding 在带背景的根列上,背景填满状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: JsonNetworkClient | undefined = undefined;
  isArkWebReady: boolean = false;
  username: string = '';
  onBack: () => void = () => {};
  // 点书签 → 进原生详情页并定位到收藏的楼层。
  onOpenTopic: (topicId: number, title: string, postNumber?: number) => void = () => {};

  @State private bookmarks: Bookmark[] = [];
  @State private categories: TopicCategory[] = [];
  @State private isInitialLoading: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = true;
  @State private loadFailed: boolean = false;
  @State private message: string = '';
  private service?: BookmarkService = undefined;
  private categoryIndex: CategoryIndex = new CategoryIndex();
  private moreUrl: string = '';
  private loading: boolean = false;

  aboutToAppear(): void {
    if (this.bridge) {
      this.service = new BookmarkService(this.bridge);
    }
    this.loadCategories();
    this.loadInitial();
  }

  build() {
    Column() {
      // 顶栏
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

        Text('书签')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.bookmarks.length > 0) {
          Text(`${this.bookmarks.length}`)
            .fontSize(14)
            .fontColor($r('app.color.text_faint'))
            .font({ family: 'HarmonyOS Sans' })
            .padding({ right: 8 })
        }
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
    if (this.bookmarks.length === 0) {
      LoadStateView({
        isLoading: this.isInitialLoading,
        loadingText: '加载中…',
        message: this.message.length > 0 ? this.message : '书签加载失败',
        showRetry: this.loadFailed,
        emptyIcon: $r('sys.symbol.bookmark'),
        emptyTitle: '还没有书签',
        emptySubtitle: '在帖子里点书签图标，就能把它存到这里随时回看',
        onRetry: () => {
          this.loadInitial();
        }
      })
    } else {
      Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
        List() {
          ForEach(this.bookmarks, (item: Bookmark) => {
            ListItem() {
              this.BookmarkRow(item)
            }
            // key 带上 pinned:置顶状态变化时 key 变,ForEach 才会重建该行,
            // 否则标题图钉与菜单文案会停留在旧状态(id 不变 ForEach 视作未变)。
          }, (item: Bookmark) => `${item.id}_${item.pinned}`)

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
        // 分割线由 List 统一管理:一条 1vp 实线,不受单条背景色与滚动像素对齐影响
        // (旧的每条 0.5vp 底边框在滚动时会被像素对齐抹掉、且在置顶行底色上几乎不可见)。
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

  // 单条书签:上半部分对齐首页帖子行(头像 + 标题 + 分类/标签徽标),
  // 下半部分是被收藏楼层的纯文本摘要,从头像左边缘起通栏铺开。
  @Builder
  private BookmarkRow(item: Bookmark) {
    Column() {
      // 头像 + 标题/徽标
      Row() {
        UserAvatar({ user: item.author, avatarSize: 46 })
          .margin({ right: 10 })

        Column() {
          Row() {
            if (item.pinned) {
              SymbolGlyph($r('sys.symbol.bookmark_fill'))
                .fontSize(13)
                .fontColor([$r('app.color.ld_gold')])
                .margin({ right: 4, top: 2 })
            }
            Text(item.title)
              .fontSize(17)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          // 分类 + 标签:与首页帖子列表同一组件、同样式。
          if (this.hasBadges(item)) {
            TopicMetadataBadges({
              category: this.getCategoryFor(item.categoryId),
              parentCategory: this.getParentCategoryFor(item.categoryId),
              tags: item.tags
            })
              .width('100%')
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 摘录:纯文本、无背景,从头像左边缘起通栏铺开,2 行截断。
      if (item.excerpt.length > 0) {
        Text() {
          if (item.linkedPostNumber > 1) {
            Span(`#${item.linkedPostNumber} · `)
              .fontSize(13)
              .fontColor($r('app.color.text_faint'))
          }
          Span(item.excerpt)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(21)
        .margin({ top: 8 })
      }

      // 元信息:回复数 · 收藏时间 · 三点菜单(置顶/删除)
      Row() {
        Text(`${this.getReplyCount(item)} 回复`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        if (this.getBookmarkTime(item).length > 0) {
          Text(this.getBookmarkTime(item))
            .fontSize(13)
            .fontColor($r('app.color.text_faint'))
        }
        // 三点菜单:热区外扩,Block 阻止点击穿透到整行(否则会跳转帖子)。
        Row() {
          FaIconView({
            icon: this.faIcon('ellipsis'),
            iconSize: 16,
            color: $r('app.color.text_faint')
          })
        }
        .height(28)
        .padding({ left: 12 })
        .hitTestBehavior(HitTestMode.Block)
        .bindMenu([
          {
            value: item.pinned ? '取消置顶' : '置顶',
            action: (): void => {
              this.togglePin(item);
            }
          },
          {
            value: '删除',
            action: (): void => {
              this.confirmDelete(item);
            }
          }
        ])
      }
      .width('100%')
      .margin({ top: 6 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 12, bottom: 13 })
    .backgroundColor(item.pinned ? $r('app.color.surface_band') : $r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpenTopic(item.topicId, item.title,
        item.linkedPostNumber > 1 ? item.linkedPostNumber : undefined);
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
    const isFirstLoad: boolean = this.bookmarks.length === 0;
    this.loading = true;
    this.isInitialLoading = isFirstLoad;
    this.isRefreshing = !isFirstLoad;
    this.loadFailed = false;

    const result: NetworkResult<BookmarkPage> = await this.service.getFirstPage(this.username);
    this.loading = false;
    this.isInitialLoading = false;
    this.isRefreshing = false;

    if (!result.success || result.data === undefined) {
      this.loadFailed = true;
      this.message = result.error?.message ? result.error.message : '书签加载失败，请重试';
      Log.i(`${LOG_TAG} initial load failed status=${result.statusCode}`);
      return;
    }

    this.bookmarks = this.sortPinnedFirst(result.data.bookmarks);
    this.moreUrl = result.data.moreUrl ? result.data.moreUrl : '';
    this.hasMore = this.moreUrl.length > 0;
    this.message = '';
    Log.i(`${LOG_TAG} initial loaded count=${this.bookmarks.length} hasMore=${this.hasMore}`);
  }

  private async loadMore(): Promise<void> {
    if (!this.service || this.loading || !this.hasMore || this.moreUrl.length === 0) {
      return;
    }
    this.loading = true;
    this.isLoadingMore = true;

    const result: NetworkResult<BookmarkPage> = await this.service.getNextPage(this.moreUrl);
    this.loading = false;
    this.isLoadingMore = false;

    if (!result.success || result.data === undefined) {
      Log.i(`${LOG_TAG} load more failed status=${result.statusCode}`);
      return;
    }

    if (result.data.bookmarks.length === 0) {
      this.hasMore = false;
      this.moreUrl = '';
      return;
    }
    this.bookmarks = this.sortPinnedFirst(this.bookmarks.concat(result.data.bookmarks));
    this.moreUrl = result.data.moreUrl ? result.data.moreUrl : '';
    this.hasMore = this.moreUrl.length > 0;
  }

  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge as JsonNetworkClient, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  // 置顶排最前,组内保持服务端顺序(稳定分区)。
  private sortPinnedFirst(list: Bookmark[]): Bookmark[] {
    const pinned: Bookmark[] = [];
    const rest: Bookmark[] = [];
    for (let index: number = 0; index < list.length; index++) {
      if (list[index].pinned) {
        pinned.push(list[index]);
      } else {
        rest.push(list[index]);
      }
    }
    return pinned.concat(rest);
  }

  // ==================== 置顶 / 删除 ====================

  private async togglePin(item: Bookmark): Promise<void> {
    if (!this.service) {
      return;
    }
    // 未登录:拦截并弹登录页,不发请求(书签置顶)。
    if (!LoginGate.ensureLoggedIn()) {
      return;
    }
    const result: NetworkResult<boolean> = await this.service.togglePin(item.id);
    if (!result.success) {
      this.showToast(result.error?.message ? result.error.message : '操作失败，请稍后再试');
      Log.i(`${LOG_TAG} toggle pin failed id=${item.id} status=${result.statusCode}`);
      return;
    }
    // 本地翻转 pinned 并重排(置顶置顶),避免整页重拉。
    const nextPinned: boolean = !item.pinned;
    const next: Bookmark[] = [];
    for (let index: number = 0; index < this.bookmarks.length; index++) {
      const cur: Bookmark = this.bookmarks[index];
      next.push(cur.id === item.id ? this.withPinned(cur, nextPinned) : cur);
    }
    this.bookmarks = this.sortPinnedFirst(next);
    this.showToast(nextPinned ? '已置顶' : '已取消置顶');
  }

  private confirmDelete(item: Bookmark): void {
    this.getUIContext().showAlertDialog({
      title: '删除书签',
      message: '确定要删除这个书签吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.ld_danger'),
        action: () => {
          this.performDelete(item);
        }
      }
    });
  }

  private async performDelete(item: Bookmark): Promise<void> {
    if (!this.service) {
      return;
    }
    // 未登录:拦截并弹登录页,不发请求(删除书签)。
    if (!LoginGate.ensureLoggedIn()) {
      return;
    }
    const result: NetworkResult<boolean> = await this.service.deleteBookmark(item.id);
    if (!result.success) {
      this.showToast(result.error?.message ? result.error.message : '删除失败，请稍后再试');
      Log.i(`${LOG_TAG} delete failed id=${item.id} status=${result.statusCode}`);
      return;
    }
    const next: Bookmark[] = [];
    for (let index: number = 0; index < this.bookmarks.length; index++) {
      if (this.bookmarks[index].id !== item.id) {
        next.push(this.bookmarks[index]);
      }
    }
    this.bookmarks = next;
    this.showToast('已删除');
  }

  // 复制一份并改 pinned(Bookmark 是接口/值对象,重建以触发列表刷新)。
  private withPinned(src: Bookmark, pinned: boolean): Bookmark {
    return {
      id: src.id, topicId: src.topicId, title: src.title, excerpt: src.excerpt,
      linkedPostNumber: src.linkedPostNumber, pinned: pinned, categoryId: src.categoryId,
      tags: src.tags, author: src.author, highestPostNumber: src.highestPostNumber,
      createdAt: src.createdAt
    };
  }

  private showToast(message: string): void {
    promptToast(this.getUIContext(), message);
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }

  // ==================== 展示辅助 ====================

  private hasBadges(item: Bookmark): boolean {
    return this.getCategoryFor(item.categoryId) !== undefined || item.tags.length > 0;
  }

  private getCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.find(this.categories, categoryId);
  }

  private getParentCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.findParent(this.categories, categoryId);
  }

  // 回复数口径与首页一致:总楼数 - 1;缺 highest_post_number 时返回 0。
  private getReplyCount(item: Bookmark): number {
    if (item.highestPostNumber !== undefined && item.highestPostNumber > 0) {
      return item.highestPostNumber - 1;
    }
    return 0;
  }

  private getBookmarkTime(item: Bookmark): string {
    const rel: string = RelativeTime.fromNow(item.createdAt);
    return rel.length > 0 ? `收藏于 ${rel}` : '';
  }
}
