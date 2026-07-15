import { KeyboardAvoidMode } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { common } from '@kit.AbilityKit';
import { Log } from '../../services/logging/Log';
import { Topic } from '../../models/Topic';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SearchResult, TopicService } from '../../services/topic/TopicService';
import { SearchHistoryStore } from '../../services/search/SearchHistoryStore';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';

const LOG_TAG: string = '[ArkDO][Search]';
// 搜索输入框焦点 id:挂载后 requestFocus 弹软键盘。
const INPUT_FOCUS_ID: string = 'arkdoSearchInput';
// 输入停顿多久才真正发起搜索(边打字边搜,避免每次击键都请求)。
const DEBOUNCE_MS: number = 350;
// 少于该字数不发起搜索(低于站点 min_search_term_length 时服务端也只回空,先在本地挡掉)。
const MIN_TERM_LEN: number = 2;
// Discourse 整页搜索分页硬上限。
const MAX_SEARCH_PAGE: number = 10;

// AppStorage 键:浮层可见态镜像 + 系统返回键关闭信号(Index @Entry 与 RootTabPage 共用)。
// 浮层不进 Navigation 栈,系统返回键需由 @Entry 拦截:可见时 bump BACK_TICK,RootTabPage 监听后关闭。
export const SEARCH_OVERLAY_VISIBLE_KEY: string = 'searchOverlayVisible';
export const SEARCH_OVERLAY_BACK_TICK_KEY: string = 'searchOverlayBackTick';

// 帖子搜索浮层:从当前页融合展开(不走 Navigation push)。顶部搜索条 + 下方历史/结果。
// 键盘避让走系统 RESIZE(输入框在顶、结果区自动收缩),无需像评论浮层那样手动监听 avoidAreaChange。
@Component
export struct SearchOverlay {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  isArkWebReady: boolean = false;
  onClose: () => void = () => {};
  onOpenTopic: (topic: Topic) => void = () => {};

  @State private query: string = '';
  @State private results: Topic[] = [];
  @State private history: string[] = [];
  @State private isSearching: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = false;
  @State private hasSearched: boolean = false;
  @State private errorMessage: string = '';
  @State private requiresChallenge: boolean = false;
  // 进场轻微下落:配合调用处的整体淡入,读作"从顶栏融合展开"。
  @State private enterOffsetY: number = 10;
  private currentPage: number = 1;
  private debounceTimer: number = -1;
  // 请求序号:边打字边搜时丢弃过期响应(只认最后一次)。
  private searchSeq: number = 0;
  private seenTopicIds: Set<number> = new Set();

  aboutToAppear(): void {
    // 输入框在顶、键盘在底:用系统 RESIZE 让结果区自动收缩,顶部搜索条不被顶走。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.history = SearchHistoryStore.load(this.hostContext());
    this.focusInput();
  }

  aboutToDisappear(): void {
    this.clearDebounce();
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
    .backgroundColor($r('app.color.page_bg'))
    .translate({ y: this.enterOffsetY })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAppear(() => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.enterOffsetY = 0;
      });
    })
  }

  @Builder
  private SearchBar() {
    Row({ space: 8 }) {
      // 输入容器:放大镜 + 输入框 + 清除。
      Row({ space: 8 }) {
        FaIconView({ icon: this.searchIcon(), color: $r('app.color.text_tertiary'), iconSize: 16 })

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
          this.ResultItem(topic)
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

  @Builder
  private ResultItem(topic: Topic) {
    ListItem() {
      Column() {
        Text(topic.title)
          .fontSize(17)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (topic.searchBlurb !== undefined && topic.searchBlurb.length > 0) {
          Text(topic.searchBlurb)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        }

        if (this.resultTime(topic).length > 0) {
          Text(this.resultTime(topic))
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 4 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 12, bottom: 12 })
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })
      .onClick(() => {
        this.handleResultClick(topic);
      })
    }
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
      this.runSearch(value, true);
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
    this.runSearch(this.query, true);
  }

  private handleResultClick(topic: Topic): void {
    // 点到结果算一次有效搜索,记入历史。
    this.saveHistory(this.trimmedQuery());
    this.onOpenTopic(topic);
  }

  private applyHistoryTerm(term: string): void {
    this.query = term;
    this.saveHistory(term);
    this.runSearch(term, true);
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

  private async runSearch(term: string, reset: boolean): Promise<void> {
    const trimmed: string = term.trim();
    if (trimmed.length < MIN_TERM_LEN) {
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
    } else {
      this.isLoadingMore = true;
    }

    const service: TopicService = new TopicService(this.bridge);
    const result: NetworkResult<SearchResult> = await service.search(trimmed, page);

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
    this.runSearch(this.query, false);
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

  private resultTime(topic: Topic): string {
    return RelativeTime.fromNow(topic.lastPostedAt);
  }

  private hostContext(): common.Context {
    return getContext(this) as common.Context;
  }

  private searchIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('magnifying-glass');
    return def ? def : { id: 'magnifying-glass', rawfilePath: 'fa_icons/magnifying-glass.svg' };
  }
}
