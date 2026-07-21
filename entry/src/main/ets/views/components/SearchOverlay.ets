import { KeyboardAvoidMode } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { common } from '@kit.AbilityKit';
import { Log } from '../../services/logging/Log';
import { Topic, TopicCategory } from '../../models/Topic';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SearchResult, TopicService } from '../../services/topic/TopicService';
import { SearchHistoryStore } from '../../services/search/SearchHistoryStore';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { TopicListItem } from './TopicListItem';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';

const LOG_TAG: string = '[ArkDO][Search]';
// 搜索输入框焦点 id:挂载后 requestFocus 弹软键盘。
const INPUT_FOCUS_ID: string = 'arkdoSearchInput';
// 输入停顿多久才真正发起搜索(边打字边搜,避免每次击键都请求)。
const DEBOUNCE_MS: number = 350;
// 少于该字数不发起搜索(低于站点 min_search_term_length 时服务端也只回空,先在本地挡掉)。
const MIN_TERM_LEN: number = 2;
// Discourse 整页搜索分页硬上限。
const MAX_SEARCH_PAGE: number = 10;

// 一镜到底共享元素 id:顶栏放大镜(源)与搜索页前导放大镜(目标)标同一 id,
// 由 RootTabPage.openSearch/closeSearch 的 animateTo 插值。
export const SEARCH_ICON_GEOMETRY_ID: string = 'arkdo-search-icon';

// 帖子搜索页:顶部搜索条 + 下方历史/结果。
// 键盘避让走系统 RESIZE(输入框在顶、结果区自动收缩),无需像评论浮层那样手动监听 avoidAreaChange。
@Component
export struct SearchOverlay {
  // 窗口常驻全屏布局:页面根列铺满整屏,搜索栏自行避让状态栏(padding 在带背景的根列上,背景填满状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  isArkWebReady: boolean = false;
  onClose: () => void = () => {};
  onOpenTopic: (topic: Topic) => void = () => {};

  @State private query: string = '';
  @State private results: Topic[] = [];
  @State private history: string[] = [];
  // 分类树:结果项复用 TopicListItem 渲染分类/标签徽标时按 categoryId 查名。
  @State private categories: TopicCategory[] = [];
  // 当前搜索词拆出的普通高亮词(去掉 in:/#/@ 等高级语法),用于摘要命中染色。
  @State private highlights: string[] = [];
  private categoryIndex: CategoryIndex = new CategoryIndex();
  @State private isSearching: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = false;
  @State private hasSearched: boolean = false;
  @State private errorMessage: string = '';
  @State private requiresChallenge: boolean = false;
  private currentPage: number = 1;
  private debounceTimer: number = -1;
  // 请求序号:边打字边搜时丢弃过期响应(只认最后一次)。
  private searchSeq: number = 0;
  private seenTopicIds: Set<number> = new Set();

  aboutToAppear(): void {
    // 输入框在顶、键盘在底:用系统 RESIZE 让结果区自动收缩,顶部搜索条不被顶走。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.history = SearchHistoryStore.load(this.hostContext());
    this.loadCategories();
    this.focusInput();
  }

  // 加载分类树(结果项徽标用);通常 HomePage 已加载并缓存,这里 loadIfNeeded 快速返回。
  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null =
      await this.categoryIndex.loadIfNeeded(this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  aboutToDisappear(): void {
    this.clearDebounce();
    this.hideKeyboard();
    // 还原默认避让,避免影响后续其它页面。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
  }

  build() {
    Column() {
      this.SearchBar()

      Divider()
        .color($r('app.color.border'))
        .strokeWidth(1)

      // 内容区:未达搜索字数显示历史,否则显示结果。
      Stack() {
        if (this.trimmedQuery().length < MIN_TERM_LEN) {
          this.HistoryView()
        } else {
          this.ResultsView()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.sysTopInset })
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private SearchBar() {
    Row({ space: 8 }) {
      // 输入容器:放大镜 + 输入框 + 清除。
      Row({ space: 8 }) {
        // 一镜到底目标:与顶栏源图标同 geometryTransition id,搜索页出现时由源飞入至此。
        FaIconView({ icon: this.searchIcon(), color: $r('app.color.text_tertiary'), iconSize: 16 })
          .geometryTransition(SEARCH_ICON_GEOMETRY_ID, { follow: true })
          .transition(TransitionEffect.OPACITY)

        TextInput({ text: $$this.query, placeholder: '搜索帖子…' })
          .id(INPUT_FOCUS_ID)
          .layoutWeight(1)
          // 给足够高度让内容区容得下整根光标;padding 归零(左侧紧贴放大镜)。
          // 加垂直 padding 反而缩小内容区、切光标;TextInput 单行又不支持 lineHeight 撑行盒。
          .height(40)
          .padding({ left: 0, right: 0, top: 0, bottom: 0 })
          .backgroundColor(Color.Transparent)
          // TextInput 默认自带圆角背景 + 默认裁剪到自身圆角;显式归零,排除默认圆角裁掉光标。
          .borderRadius(0)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => {
            this.handleQueryChanged(value);
          })
          .onSubmit(() => {
            this.handleSubmit();
          })

        if (this.query.length > 0) {
          Text('✕')
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.clearQuery();
            })
        }
      }
      .layoutWeight(1)
      // 高度由 TextInput(含上下 padding)撑,minHeight 兜底;别硬设 height 压死输入框裁掉光标。
      .constraintSize({ minHeight: 40 })
      .padding({ left: 12, right: 4 })
      .backgroundColor($r('app.color.fill_subtle'))
      .borderRadius(10)
      .alignItems(VerticalAlign.Center)
      .clip(false)

      Text('取消')
        .fontSize(15)
        .fontColor($r('app.color.brand'))
        .onClick(() => {
          this.onClose();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 16, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private HistoryView() {
    if (this.history.length === 0) {
      Column() {
        Text('输入关键词搜索帖子')
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        Row() {
          Text('搜索历史')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          Text('清空')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .onClick(() => {
              this.clearHistory();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 6 })

        List() {
          ForEach(this.history, (term: string) => {
            ListItem() {
              Row({ space: 10 }) {
                FaIconView({ icon: this.searchIcon(), color: $r('app.color.text_tertiary'), iconSize: 14 })
                Text(term)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text('✕')
                  .fontSize(13)
                  .fontColor($r('app.color.text_tertiary'))
                  .width(28)
                  .height(28)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.removeHistory(term);
                  })
              }
              .width('100%')
              .height(46)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.applyHistoryTerm(term);
              })
            }
          }, (term: string) => term)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        // 滑动历史列表也收起键盘。
        .onScrollStart(() => {
          this.hideKeyboard();
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private ResultsView() {
    Stack() {
      List() {
        ForEach(this.results, (topic: Topic) => {
          TopicListItem({
            topic: topic,
            category: CategoryIndex.find(this.categories, topic.categoryId),
            parentCategory: CategoryIndex.findParent(this.categories, topic.categoryId),
            searchHighlights: this.highlights,
            onTopicClick: (selected: Topic) => {
              this.handleResultClick(selected);
            },
            onUnreadBadgeClick: (selected: Topic) => {
              this.handleResultClick(selected);
            }
          })
        }, (topic: Topic) => `${topic.id}`)

        if (this.results.length > 0) {
          ListItem() {
            Row() {
              if (this.isLoadingMore) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color($r('app.color.brand'))
                  .margin({ right: 8 })
              }
              Text(this.hasMore ? '上拉加载更多' : '没有更多了')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .height(54)
            .justifyContent(FlexAlign.Center)
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onReachEnd(() => {
        this.loadMore();
      })
      // 一开始滑动结果列表就收起键盘,别挡着看结果。
      .onScrollStart(() => {
        this.hideKeyboard();
      })

      // 首次搜索加载中(尚无结果)。
      if (this.isSearching && this.results.length === 0) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.brand'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      } else if (this.errorMessage.length > 0 && this.results.length === 0) {
        Column() {
          Text(this.errorMessage)
            .fontSize(15)
            .fontColor($r('app.color.warning'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      } else if (this.hasSearched && !this.isSearching && this.results.length === 0) {
        Column() {
          Text('未找到相关帖子')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
  }

  // 输入变化:更新词、防抖后发起搜索;清空/过短时回到历史态。
  private handleQueryChanged(value: string): void {
    this.query = value;
    this.clearDebounce();
    if (value.trim().length < MIN_TERM_LEN) {
      this.resetResults();
      return;
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.runSearch(true);
    }, DEBOUNCE_MS);
  }

  // 回车:立即搜索并记入历史(边打字边搜不写历史,只有主动提交/命中才留痕)。
  private handleSubmit(): void {
    this.clearDebounce();
    const term: string = this.trimmedQuery();
    if (term.length < MIN_TERM_LEN) {
      return;
    }
    this.saveHistory(term);
    this.runSearch(true);
  }

  private handleResultClick(topic: Topic): void {
    // 点到结果算一次有效搜索,记入历史。
    this.saveHistory(this.trimmedQuery());
    this.hideKeyboard();
    this.onOpenTopic(topic);
  }

  private applyHistoryTerm(term: string): void {
    this.query = term;
    this.saveHistory(term);
    this.runSearch(true);
    // 点历史词已选定搜索目标,收起键盘让位给结果列表(不再 focusInput 弹键盘)。
    this.hideKeyboard();
  }

  // 收起软键盘:停当前输入会话(焦点可留在输入框,再次点击会重新弹出)。
  private hideKeyboard(): void {
    try {
      inputMethod.getController().stopInputSession();
    } catch (err) {
      // 收键盘失败不影响主流程。
    }
  }

  private async runSearch(reset: boolean): Promise<void> {
    const term: string = this.trimmedQuery();
    if (term.length < MIN_TERM_LEN) {
      return;
    }
    if (!this.isArkWebReady) {
      this.errorMessage = '正在准备请求环境，请稍后重试';
      this.hasSearched = true;
      return;
    }

    const page: number = reset ? 1 : this.currentPage + 1;
    const seq: number = this.searchSeq + 1;
    this.searchSeq = seq;

    if (reset) {
      this.isSearching = true;
      this.errorMessage = '';
      this.requiresChallenge = false;
      this.hasSearched = true;
      // 高亮词按本次搜索词定格(不随后续输入漂移;高级语法会被 parseHighlights 过滤掉)。
      this.highlights = this.parseHighlights(term);
    } else {
      this.isLoadingMore = true;
    }

    const service: TopicService = new TopicService(this.bridge);
    const result: NetworkResult<SearchResult> = await service.search(term, page);

    // 过期响应(用户已改词/翻页)直接丢弃。
    if (seq !== this.searchSeq) {
      return;
    }
    this.isSearching = false;
    this.isLoadingMore = false;

    if (result.success && result.data) {
      const hasMore: boolean = result.data.hasMore && page < MAX_SEARCH_PAGE;
      if (reset) {
        this.seenTopicIds = new Set();
        this.results = this.collect(result.data.topics);
      } else {
        this.results = this.results.concat(this.collect(result.data.topics));
      }
      this.currentPage = page;
      this.hasMore = hasMore;
      this.errorMessage = '';
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    if (reset) {
      this.errorMessage = this.requiresChallenge ? '搜索遇到访问验证，请稍后重试' : '搜索失败，请检查网络后重试';
    }
    Log.i(`${LOG_TAG} search failed page=${page} status=${result.statusCode} requiresChallenge=${this.requiresChallenge}`);
  }

  // 去重收集(同一主题不同页可能重复出现)。
  private collect(topics: Topic[]): Topic[] {
    const out: Topic[] = [];
    for (let index: number = 0; index < topics.length; index++) {
      const topic: Topic = topics[index];
      if (!this.seenTopicIds.has(topic.id)) {
        this.seenTopicIds.add(topic.id);
        out.push(topic);
      }
    }
    return out;
  }

  private loadMore(): void {
    if (this.isSearching || this.isLoadingMore || !this.hasMore || this.results.length === 0) {
      return;
    }
    this.runSearch(false);
  }

  private resetResults(): void {
    this.searchSeq++;
    this.results = [];
    this.seenTopicIds = new Set();
    this.currentPage = 1;
    this.hasMore = false;
    this.hasSearched = false;
    this.isSearching = false;
    this.isLoadingMore = false;
    this.errorMessage = '';
  }

  private clearQuery(): void {
    this.query = '';
    this.clearDebounce();
    this.resetResults();
    this.focusInput();
  }

  private saveHistory(term: string): void {
    if (term.length < MIN_TERM_LEN) {
      return;
    }
    this.history = SearchHistoryStore.add(this.hostContext(), term);
  }

  private removeHistory(term: string): void {
    this.history = SearchHistoryStore.remove(this.hostContext(), term);
  }

  private clearHistory(): void {
    SearchHistoryStore.clear(this.hostContext());
    this.history = [];
  }

  private focusInput(): void {
    setTimeout(() => {
      this.getUIContext().getFocusController().requestFocus(INPUT_FOCUS_ID);
    }, 120);
  }

  private clearDebounce(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
  }

  private trimmedQuery(): string {
    return this.query.trim();
  }

  // 从搜索词拆出普通高亮词:去掉高级语法(in:title / category: / #版块 / @用户 / -排除)。
  private parseHighlights(term: string): string[] {
    const parts: string[] = term.split(/\s+/);
    const out: string[] = [];
    for (let i: number = 0; i < parts.length; i++) {
      const p: string = parts[i];
      if (p.length < 2 || p.indexOf(':') >= 0) {
        continue;
      }
      const head: string = p.charAt(0);
      if (head === '#' || head === '@' || head === '-' || head === '+') {
        continue;
      }
      out.push(p);
    }
    return out;
  }

  private hostContext(): common.Context {
    return getContext(this) as common.Context;
  }

  private searchIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('magnifying-glass');
    return def ? def : { id: 'magnifying-glass', rawfilePath: 'fa_icons/magnifying-glass.svg' };
  }
}
