import { Log } from '../../services/logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { User } from '../../models/User';
import { Topic, TopicCategory } from '../../models/Topic';
import { TopicListItem } from '../components/TopicListItem';
import { UserAvatar } from '../components/UserAvatar';
import { NotificationBell } from '../components/NotificationBell';
import { PulsingHalo } from '../components/PulsingHalo';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { ChallengeRecoveryEventBus, ChallengeRecoveryState } from '../../services/challenge/ChallengeRecoveryEventBus';
import { TopicReadState, TopicReadStateEventBus } from '../../services/session/TopicReadStateEventBus';
import { NotificationEventBus, NotificationSnapshot } from '../../services/notification/NotificationEventBus';
import { TopicPage, TopicService } from '../../services/topic/TopicService';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { FeedDef, FeedKey, FeedPrefs } from '../../services/site/FeedPrefs';
import { SiteDef, SitePrefs } from '../../services/site/SitePrefs';
import { CategoryDrawer } from '../components/CategoryDrawer';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { SEARCH_OVERLAY_VISIBLE_KEY, SEARCH_ICON_GEOMETRY_ID } from '../components/SearchOverlay';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { PostRichContent } from '../components/PostRichContent';
import { VersionAnnouncement, VersionAnnouncementService } from '../../services/announce/VersionAnnouncement';
import { bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][Home]';
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';
// 侧边抽屉宽度(关闭时向左平移此距离移出屏幕)。
const DRAWER_WIDTH: number = 288;
// 静默过验中"手动验证"按钮的延迟出现时间:保护快乐路径(通常几秒就静默过了),
// 别让用户第一时间就把自己拽进全屏验证页。
const MANUAL_VERIFY_DELAY_MS: number = 6000;

// 版本公告弹窗:true=每次启动都弹(调试用);false=同一版本只弹一次(上线值)。
const ANNOUNCE_ALWAYS_SHOW: boolean = false;
// 诊断关键字:hilog / DevEco Log 里搜 ANNOUNCE_DIAG 看公告全链路日志。
const ANNOUNCE_DIAG: string = '[ArkDO][ANNOUNCE_DIAG]';
// 记「已弹过的 versionCode」的偏好 key(全项目共用 'app_settings' 库)。
const ANNOUNCE_PREFS_NAME: string = 'app_settings';
const ANNOUNCE_SHOWN_CODE_KEY: string = 'announce_shown_version_code';

@Component
export struct HomePage {
  @State private topics: Topic[] = [];
  @State private isInitialLoading: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private isLoadingMore: boolean = false;
  @State private hasMore: boolean = true;
  @State private currentPage: number = 0;
  @State private listMessage: string = '正在准备 ArkWeb 请求环境';
  @State private footerMessage: string = '上拉加载更多';
  @State private requiresChallenge: boolean = false;
  @State private loadFailed: boolean = false;
  // 挑战恢复状态:驱动空态在"后台静默过验中 / 终态失败"两态间切换。
  @State private recoveryState: ChallengeRecoveryState = ChallengeRecoveryEventBus.getCurrentState();
  // 静默期"手动验证"按钮是否已延迟出现。
  @State private showManualVerify: boolean = false;
  private manualVerifyTimer: number = -1;
  private unsubscribeRecoveryState?: () => void = undefined;
  @State private categories: TopicCategory[] = [];
  // 侧边版块抽屉开关。
  @State private showSideBar: boolean = false;
  // 抽屉横向拖拽偏移(向左拖为负,跟手);松手过阈值关闭、否则弹回 0。
  @State private drawerDragX: number = 0;
  // 当前内容源:selectedCategory 有值=看某版块;否则看内置入口 selectedFeedKey。
  @State private selectedCategory?: TopicCategory = undefined;
  @State private selectedFeedKey: string = FeedKey.LATEST;
  // 设置页启用且有序的可选入口 key(打开抽屉时刷新)。
  @State private enabledFeedKeys: string[] = [];
  // 抽屉「我的站点」区:入口开关 + 要展示的站点(打开抽屉时与 enabledFeedKeys 一并刷新)。
  @State private sitesEntryEnabled: boolean = true;
  @State private drawerSites: SiteDef[] = [];
  // 头像铃铛未读数:由 NotificationEventBus 广播驱动(NotificationService 前台轮询产出)。
  @State private unreadNotifications: number = 0;
  private unsubscribeNotifications?: () => void = undefined;
  private categoryIndex: CategoryIndex = new CategoryIndex();
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  @Prop accountUser: User = { id: 0, username: '' };
  @Prop isLoggedIn: boolean = false;
  @Prop isCheckingSession: boolean = false;
  @Prop hasCheckedSession: boolean = false;
  onAccountClick: () => void = () => {};
  // 下拉刷新时通知宿主补查会话:上次会话检查被 CF 拦截时,右上角状态可能不真实。
  onSessionRecheck: () => void = () => {};
  onOpenNotifications: () => void = () => {};
  onOpenSearch: () => void = () => {};
  // 搜索浮层可见态镜像:一镜到底期间隐藏顶栏源图标,把几何交给浮层里的目标图标(geometryTransition)。
  @StorageProp(SEARCH_OVERLAY_VISIBLE_KEY) private searchOverlayVisible: boolean = false;
  // 窗口常驻全屏布局:主体内容自行避让状态栏(padding 加在带背景的主体列,背景填满状态栏条);
  // 遮罩与抽屉不加,天然盖满整屏。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onTopicClick: (topic: Topic) => void = () => {};
  // 按帖子 ID 直接跳转详情(通用入口,不依赖完整 Topic 对象)。
  onOpenTopicById: (topicId: number) => void = () => {};
  // 点未读徽标:带目标楼号打开详情,直接定位到第一条未读楼。
  onOpenTopicAtPost: (topic: Topic, postNumber: number) => void = () => {};
  // 抽屉「我的站点」标题行:打开站点管理页。
  onOpenSites: () => void = () => {};
  // 抽屉站点行:打开该站点(走通用 WebView 页)。siteId 用于缓存该站 favicon。
  onOpenSite: (url: string, title: string, siteId: string) => void = () => {};
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;
  private unsubscribeTopicReadState?: () => void = undefined;
  // 调试用:输入帖子 ID 直接跳转详情(有些帖子已从最新列表里翻走,无法在列表中找到)。
  private jumpDialogController: CustomDialogController = new CustomDialogController({
    builder: TopicJumpDialog({
      onConfirm: (topicId: number) => {
        this.jumpToTopic(topicId);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });
  // 版本公告弹层:命中当前 versionCode 的回复后展示其正文。
  @State private announceVisible: boolean = false;
  @State private announceCooked: string = '';
  // 本次页面挂载是否已发起过公告检查(每次冷启动只查一次,不随下拉刷新/切源重复)。
  private announceChecked: boolean = false;

  aboutToAppear(): void {
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }
    if (!this.unsubscribeTopicReadState) {
      // 从详情页返回时同步该主题的已读状态(消蓝点、更新未读徽标)。
      this.unsubscribeTopicReadState = TopicReadStateEventBus.subscribe((state: TopicReadState) => {
        this.handleTopicReadStateChanged(state);
      });
    }
    if (!this.unsubscribeNotifications) {
      // 先取当前已知值(避免首帧空窗),再订阅后续变化。
      this.unreadNotifications = NotificationEventBus.current().unread;
      this.unsubscribeNotifications = NotificationEventBus.subscribe((snapshot: NotificationSnapshot) => {
        this.unreadNotifications = snapshot.unread;
      });
    }
    if (!this.unsubscribeRecoveryState) {
      this.unsubscribeRecoveryState = ChallengeRecoveryEventBus.subscribeState((state: ChallengeRecoveryState) => {
        this.handleRecoveryStateChanged(state);
      });
    }
    this.refreshDrawerPrefs();
    this.syncSessionVersion();
    if (this.isArkWebReady && this.topics.length === 0) {
      this.loadSiteMetadataIfNeeded();
      this.refreshLatestTopics();
    }
    this.checkVersionAnnouncement();
  }

  aboutToDisappear(): void {
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
    if (this.unsubscribeTopicReadState) {
      this.unsubscribeTopicReadState();
      this.unsubscribeTopicReadState = undefined;
    }
    if (this.unsubscribeNotifications) {
      this.unsubscribeNotifications();
      this.unsubscribeNotifications = undefined;
    }
    if (this.unsubscribeRecoveryState) {
      this.unsubscribeRecoveryState();
      this.unsubscribeRecoveryState = undefined;
    }
    this.clearManualVerifyTimer();
  }

  // 挑战恢复状态迁移:进入静默态时延迟放出"手动验证"按钮;离开则清掉计时器。
  private handleRecoveryStateChanged(state: ChallengeRecoveryState): void {
    this.recoveryState = state;
    if (state === ChallengeRecoveryState.RESOLVING) {
      this.showManualVerify = false;
      this.clearManualVerifyTimer();
      this.manualVerifyTimer = setTimeout(() => {
        this.manualVerifyTimer = -1;
        this.showManualVerify = true;
      }, MANUAL_VERIFY_DELAY_MS);
    } else {
      this.clearManualVerifyTimer();
      this.showManualVerify = false;
    }
  }

  // "手动验证"按钮:静默/空闲态请求协调器接管弹页;冷却态无活跃挑战,退化为普通刷新。
  private onManualVerify(): void {
    if (this.recoveryState === ChallengeRecoveryState.COOLDOWN) {
      this.refreshLatestTopics();
      return;
    }
    ChallengeRecoveryEventBus.requestManual();
  }

  private clearManualVerifyTimer(): void {
    if (this.manualVerifyTimer >= 0) {
      clearTimeout(this.manualVerifyTimer);
      this.manualVerifyTimer = -1;
    }
  }

  build() {
    // 自绘抽屉:Stack 底层为主体,上层为遮罩 + 侧边抽屉(靠 translate 滑入/滑出)。
    // 不用 SideBarContainer——其 overlay 遮罩不拦截点击、内滚也不灵。
    Stack({ alignContent: Alignment.TopStart }) {
      // 主体:顶栏 + 帖子列表
      Column() {
        Row() {
          // 环境未就绪("准备环境中...")时抽屉尚无意义,隐藏汉堡入口(标题左移填满,就绪后再出现)。
          if (this.isArkWebReady) {
            this.MenuButton()
          }

          this.FeedTitle()

        // 搜索入口:环境就绪后常驻(搜索匿名可用,不随登录态隐藏)。
        if (this.isArkWebReady) {
          this.SearchButton()
        }

        // 仅在会话已确认且已登录时显示铃铛(未登录/未确认不出现)。
        if (this.hasCheckedSession && this.isLoggedIn) {
          NotificationBell({
            unreadCount: this.unreadNotifications,
            onBellClick: () => {
              // 打开通知页(进页会发 recent=true 让服务端 bump seen);本地先乐观清零红点。
              this.unreadNotifications = 0;
              this.onOpenNotifications();
            }
          })
        }

        this.AccountEntry()
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12, top: 16, bottom: 14 })

      Stack() {
        Refresh({ refreshing: this.isRefreshing, promptText: '刷新中' }) {
          List() {
            ForEach(this.topics, (topic: Topic) => {
              TopicListItem({
                topic: topic,
                category: CategoryIndex.find(this.categories, topic.categoryId),
                parentCategory: CategoryIndex.findParent(this.categories, topic.categoryId),
                onTopicClick: (selectedTopic: Topic) => {
                  // 点击即清除蓝点(乐观已读);未读徽标待返回时由详情页结算的真实未读数同步。
                  selectedTopic.unseen = false;
                  this.onTopicClick(selectedTopic);
                },
                onUnreadBadgeClick: (selectedTopic: Topic) => {
                  this.handleUnreadBadgeClick(selectedTopic);
                }
              })
              // key 纳入 bookmarked:相同 id 时 ForEach 复用旧子组件、不把 @ObjectLink 换到刷新后的新实例,
              // 收藏后回列表刷新图标不更新。把书签态并入 key,变化时强制重建该行绑新实例。
              // unread 走「同实例改字段 + @Observed 通知」路径,无需进 key。
            }, (topic: Topic) => `${topic.id}_${topic.bookmarked === true ? 1 : 0}`)

            if (this.topics.length > 0) {
              ListItem() {
                Row() {
                  if (this.isLoadingMore) {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                      .color($r('app.color.brand'))
                      .margin({ right: 8 })
                  }

                  Text(this.footerMessage)
                    .fontSize(13)
                    .fontColor(this.requiresChallenge ? $r('app.color.warning') : $r('app.color.text_secondary'))
                }
                .width('100%')
                .height(54)
                .justifyContent(FlexAlign.Center)
              }
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: 12, right: 12, bottom: 0 })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          .onReachEnd(() => {
            this.loadMoreTopics();
          })
        }
        .width('100%')
        .height('100%')
        // Refresh 会把子 List 裁剪到自身边界;子 List 的 expandSafeArea 无法穿透,
        // 需在 Refresh 上同样声明,否则列表底部无法延伸覆盖底部操作条(安全区)。
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .pullToRefresh(true)
        .refreshOffset(64)
        .onRefreshing(() => {
          this.refreshLatestTopics();
        })

        if (this.topics.length === 0) {
          Column() {
            if (!this.isArkWebReady) {
              Image($r('app.media.linuxdo_logo'))
                .width(64)
                .height(64)
                .margin({ bottom: 16 })

              Text('准备环境中...')
                .fontSize(15)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
            } else if (this.requiresChallenge) {
              // 挑战态:后台静默过验中 / 终态失败(升级弹窗被关掉未通过)。
              if (this.recoveryState === ChallengeRecoveryState.RESOLVING) {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color($r('app.color.brand'))
                  .margin({ bottom: 12 })

                Text('正在自动验证访问，请稍候…')
                  .fontSize(15)
                  .fontColor($r('app.color.warning'))
                  .textAlign(TextAlign.Center)

                // 静默几秒仍未过才放出手动入口,避免把快乐路径提前拽进全屏验证页。
                if (this.showManualVerify) {
                  Button('手动验证')
                    .fontSize(15)
                    .fontColor($r('app.color.brand'))
                    .backgroundColor($r('app.color.surface_muted'))
                    .borderRadius(20)
                    .padding({ left: 28, right: 28, top: 8, bottom: 8 })
                    .margin({ top: 16 })
                    .onClick(() => {
                      this.onManualVerify();
                    })
                }
              } else {
                Text('访问验证未完成')
                  .fontSize(15)
                  .fontColor($r('app.color.warning'))
                  .textAlign(TextAlign.Center)

                Button('手动验证')
                  .fontSize(15)
                  .fontColor($r('app.color.brand'))
                  .backgroundColor($r('app.color.surface_muted'))
                  .borderRadius(20)
                  .padding({ left: 28, right: 28, top: 8, bottom: 8 })
                  .margin({ top: 16 })
                  .onClick(() => {
                    this.onManualVerify();
                  })
              }
            } else {
              if (this.isInitialLoading) {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color($r('app.color.brand'))
                  .margin({ bottom: 12 })
              }

              Text(this.listMessage)
                .fontSize(15)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)

              if (this.loadFailed && !this.isInitialLoading) {
                Button('重试')
                  .fontSize(15)
                  .fontColor($r('app.color.brand'))
                  .backgroundColor($r('app.color.surface_muted'))
                  .borderRadius(20)
                  .padding({ left: 28, right: 28, top: 8, bottom: 8 })
                  .margin({ top: 16 })
                  .onClick(() => {
                    this.refreshLatestTopics();
                  })
              }
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.sysTopInset })
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .alignItems(HorizontalAlign.Start)

      // 遮罩:抽屉打开时铺满,拦截并点击关闭,防止点穿到帖子列表。
      if (this.showSideBar) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#33000000')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onClick(() => {
            this.closeDrawer();
          })
      }

      // 侧边抽屉:常驻渲染,靠 translate 滑入/滑出;关闭时移出屏幕左侧不可点。
      CategoryDrawer({
        categories: this.categories,
        isLoggedIn: this.isLoggedIn,
        enabledFeedKeys: this.enabledFeedKeys,
        sitesEntryEnabled: this.sitesEntryEnabled,
        sites: this.drawerSites,
        selectedFeedKey: this.selectedCategory ? '' : this.selectedFeedKey,
        selectedCategoryId: this.selectedCategory ? this.selectedCategory.id : 0,
        onSelectFeed: (feedKey: string) => {
          this.handleSelectFeed(feedKey);
        },
        onSelectCategory: (category: TopicCategory) => {
          this.handleSelectCategory(category);
        },
        onRequireLogin: () => {
          this.handleDrawerRequireLogin();
        },
        onOpenSites: () => {
          this.closeDrawer();
          this.onOpenSites();
        },
        onOpenSite: (url: string, title: string, siteId: string) => {
          this.closeDrawer();
          this.onOpenSite(url, title, siteId);
        }
      })
        .width(DRAWER_WIDTH)
        .height('100%')
        // 打开时叠加拖拽偏移跟手;关闭时整体移出屏幕左侧。
        .translate({ x: this.showSideBar ? this.drawerDragX : -DRAWER_WIDTH })
        .gesture(
          // 横向拖:向左拖动抽屉,过 1/3 宽即关闭,否则弹回。仅横向,不干扰内部竖向滚动。
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionUpdate((event: GestureEvent) => {
              if (this.showSideBar) {
                this.drawerDragX = Math.min(0, event.offsetX);
              }
            })
            .onActionEnd((event: GestureEvent) => {
              this.handleDrawerPanEnd();
            })
        )
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet(this.announceVisible, this.AnnouncementSheet(), {
      height: SheetSize.FIT_CONTENT,
      // 顶部拖拽条:下滑即可关闭弹层(内容可滚动时也不冲突,拖拽条是独立手柄)。
      dragBar: true,
      showClose: true,
      onDisappear: () => {
        this.announceVisible = false;
      }
    })
  }

  // 版本公告弹层:标题 + 命中回复的完整富文本正文(含 [vXXXX] 版本号,超长可滚动)。
  @Builder
  private AnnouncementSheet() {
    Column() {
      Text('本次更新')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24, bottom: 16 })

      Scroll() {
        Column() {
          PostRichContent({
            cookedHtml: this.announceCooked,
            fallbackText: '',
            polls: []
          })
            .width('100%')
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      // 内容滚到顶再下拉时把手势交还弹层,让「按住内容区域下滑」也能关闭(否则 Scroll 独吞垂直手势)。
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 24 })
  }

  // 顶栏标题:默认「最新」显示应用名时,把「ArkDO」末尾的 O 换成 linux.do 三色圆 logo(内联 ImageSpan
  // 保持基线对齐);选中版块/其他入口时仍是纯文字标题。logo 为固定色 SVG,深色模式下不翻转,保留品牌配色。
  @Builder
  private FeedTitle() {
    if (this.currentFeedTitle() === AppConstants.APP_NAME) {
      Text() {
        Span(AppConstants.APP_NAME.slice(0, -1))
        ImageSpan($r('app.media.linuxdo_logo'))
          .width(24)
          .height(24)
          .verticalAlign(ImageSpanAlignment.CENTER)
          .margin({ bottom: 2 })
      }
      .fontSize(26)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
    } else {
      Text(this.currentFeedTitle())
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
  }

  // 左上角汉堡入口:打开版块抽屉(三条发丝线,无需依赖 sys.symbol 资源)。
  @Builder
  private MenuButton() {
    Button() {
      Column({ space: 4 }) {
        Divider().width(18).strokeWidth(2).color($r('app.color.text_primary'))
        Divider().width(18).strokeWidth(2).color($r('app.color.text_primary'))
        Divider().width(18).strokeWidth(2).color($r('app.color.text_primary'))
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(42)
    .height(42)
    .borderRadius(21)
    .backgroundColor(Color.Transparent)
    .padding(0)
    .margin({ right: 10 })
    .onClick(() => {
      this.openDrawer();
    })
  }

  // 顶栏搜索入口:放大镜图标,点击一镜到底展开搜索浮层(由 RootTabPage 承载)。
  // 浮层可见时把源图标 if 掉(几何交给浮层前导图标),二者同 geometryTransition id、由同一 animateTo 驱动插值。
  @Builder
  private SearchButton() {
    Button() {
      if (!this.searchOverlayVisible) {
        FaIconView({ icon: this.searchIcon(), color: $r('app.color.text_primary'), iconSize: 20 })
          .geometryTransition(SEARCH_ICON_GEOMETRY_ID, { follow: true })
          .transition(TransitionEffect.OPACITY)
      }
    }
    .width(42)
    .height(42)
    .borderRadius(21)
    .backgroundColor(Color.Transparent)
    .padding(0)
    .margin({ right: 4 })
    .onClick(() => {
      this.onOpenSearch();
    })
  }

  private searchIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('magnifying-glass');
    return def ? def : { id: 'magnifying-glass', rawfilePath: 'fa_icons/magnifying-glass.svg' };
  }

  private jumpToTopic(topicId: number): void {
    Log.i(`${LOG_TAG} debug jump to topic topicId=${topicId}`);
    this.onOpenTopicById(topicId);
  }

  @Builder
  private AccountEntry() {
    if (!this.hasCheckedSession && !this.isCheckingSession) {
      Blank()
        .width(42)
        .height(42)
    } else {
      Button() {
        Stack() {
          if (this.isCheckingSession) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color($r('app.color.brand'))
          } else if (this.isLoggedIn) {
            // 光圈在底层(先声明)、头像在顶层(后声明),头像后方一圈圈向外扩散。
            Stack() {
              PulsingHalo({ baseSize: 34, color: $r('app.color.brand') })
              UserAvatar({
                user: this.accountUser,
                avatarSize: 34
              })
            }
          } else {
            SymbolGlyph($r('sys.symbol.person'))
              .fontSize(28)
              .fontColor([$r('app.color.brand')])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          }
        }
        .width(38)
        .height(38)
        .alignContent(Alignment.Center)
      }
      .width(42)
      .height(42)
      .borderRadius(21)
      .backgroundColor(Color.Transparent)
      .padding(0)
      // 放行溢出:头像光圈会扩散到 42 之外,默认圆角裁剪会切掉,需关闭裁剪。
      .clip(false)
      .enabled(!this.isCheckingSession)
      .onClick(() => {
        this.onAccountClick();
      })
      // 长按头像:弹出输入框填帖子 ID,直接跳转到指定帖子详情。
      // Button 自带点击识别器会抢占触摸,须用 priorityGesture 让长按优先于内置手势。
      .priorityGesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => {
            this.jumpDialogController.open();
          })
      )
    }
  }

  // 打开抽屉前刷新一次抽屉配置(设置页/站点管理页可能刚改过),带滑入动画。
  private openDrawer(): void {
    this.refreshDrawerPrefs();
    this.drawerDragX = 0;
    this.animateDrawer(true);
  }

  // 抽屉配置统一重读:启用入口 + 站点入口开关 + 要展示的站点。
  // 子页改完 pop 回来不会重建本页,靠每次开抽屉重读 preferences 拿最新值(无需 AppStorage tick)。
  private refreshDrawerPrefs(): void {
    this.enabledFeedKeys = FeedPrefs.getEnabledKeys(getContext(this));
    this.sitesEntryEnabled = SitePrefs.isEntryEnabled(getContext(this));
    this.drawerSites = SitePrefs.drawerSites(getContext(this));
  }

  private closeDrawer(): void {
    this.animateDrawer(false);
  }

  // 抽屉开合动画:在 animateTo 里翻转 showSideBar,遮罩淡入/淡出、抽屉平移滑动;同时归零拖拽偏移。
  private animateDrawer(show: boolean): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.showSideBar = show;
      this.drawerDragX = 0;
    });
  }

  // 抽屉横向拖拽松手:向左拖过 1/3 宽则关闭,否则弹回原位。
  private handleDrawerPanEnd(): void {
    if (!this.showSideBar) {
      return;
    }
    if (-this.drawerDragX > DRAWER_WIDTH / 3) {
      this.closeDrawer();
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.drawerDragX = 0;
    });
  }

  // 抽屉里选了内置入口:切源并重载列表(与当前源相同则仅关抽屉)。
  private handleSelectFeed(feedKey: string): void {
    this.closeDrawer();
    if (this.selectedCategory === undefined && this.selectedFeedKey === feedKey) {
      return;
    }
    this.selectedCategory = undefined;
    this.selectedFeedKey = feedKey;
    this.resetAndReload();
  }

  // 抽屉里选了某版块:切源并重载列表。
  private handleSelectCategory(category: TopicCategory): void {
    this.closeDrawer();
    if (this.selectedCategory !== undefined && this.selectedCategory.id === category.id) {
      return;
    }
    this.selectedCategory = category;
    this.resetAndReload();
  }

  // 点了受限版块/需登录入口:关抽屉并提示登录(账号入口在右上角头像)。
  private handleDrawerRequireLogin(): void {
    this.closeDrawer();
    this.showToast('登录后可查看该版块');
  }

  private resetAndReload(): void {
    this.topics = [];
    this.currentPage = 0;
    this.hasMore = true;
    this.loadFailed = false;
    this.refreshLatestTopics();
  }

  // 按当前内容源取一页:选中版块走分类接口,否则走内置入口接口。
  private fetchTopicPage(page: number): Promise<NetworkResult<TopicPage>> {
    const service: TopicService = new TopicService(this.bridge);
    if (this.selectedCategory !== undefined) {
      return service.getCategoryTopicsPage(this.selectedCategory, page);
    }
    return service.getFeedPage(this.selectedFeedKey, page);
  }

  // 当前内容源的标题:选中版块=版块名;热门/未读等入口=入口名;默认「最新」显示应用名 ArkDO。
  private currentFeedTitle(): string {
    if (this.selectedCategory !== undefined) {
      return this.selectedCategory.name;
    }
    if (this.selectedFeedKey === FeedKey.LATEST) {
      return AppConstants.APP_NAME;
    }
    const def: FeedDef | undefined = FeedPrefs.feedDef(this.selectedFeedKey);
    return def ? def.label : AppConstants.APP_NAME;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Log.i(`${LOG_TAG} toast failed: ${message}`);
    }
  }

  private async refreshLatestTopics(): Promise<void> {
    if (!this.isArkWebReady) {
      this.listMessage = '正在准备 ArkWeb 请求环境';
      return;
    }

    this.loadSiteMetadataIfNeeded();
    // 顺带补查会话状态:上次 current.json 被 CF 拦截时右上角可能误显示为未登录。
    this.onSessionRecheck();

    if (this.isRefreshing || this.isLoadingMore || this.isInitialLoading) {
      return;
    }

    const isFirstLoad: boolean = this.topics.length === 0;
    this.isInitialLoading = isFirstLoad;
    this.isRefreshing = !isFirstLoad;
    this.requiresChallenge = false;
    this.loadFailed = false;
    this.listMessage = `正在加载${this.currentFeedTitle()}`;
    this.footerMessage = '上拉加载更多';

    if (isFirstLoad) {
      // 计时锚点②:首页帖子列表开始拉取。与应用启动日志配对,测量冷启动到首屏拉取的耗时。
      Log.i(`${LOG_TAG} stage=firstLatestFetchStart ts=${Date.now()}`);
    }
    const result: NetworkResult<TopicPage> = await this.fetchTopicPage(0);
    this.isRefreshing = false;
    this.isInitialLoading = false;

    if (result.success && result.data) {
      this.topics = result.data.topics;
      this.currentPage = 0;
      this.hasMore = result.data.hasMore;
      this.listMessage = result.data.topics.length > 0 ? '' : '暂无帖子数据';
      this.footerMessage = this.hasMore ? '上拉加载更多' : '没有更多了';
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    const friendlyMessage: string = this.requiresChallenge
      ? '内容加载遇到访问验证,请稍后重试'
      : '加载失败,请检查网络后重试';
    if (this.topics.length === 0) {
      this.loadFailed = true;
      this.listMessage = friendlyMessage;
      // 诊断:这块全屏"访问验证/加载失败"提示在什么情形下弹出。它只在列表为空时出现,
      // 关键要靠时间戳配合前后的既有日志(冷启动标志/前后台切换/上一笔 latest.json 是否返回空列表)还原
      // "使用中列表怎么变空的"。这里记本次失败的指纹:是 CF 拦截还是普通网络失败、状态码、错误信息。
      Log.i(`${DIAG_TAG} stage=homeEmptyPromptShown requiresChallenge=${this.requiresChallenge} status=${result.statusCode} isLoggedIn=${this.isLoggedIn} errCode=${result.error?.code ?? ''} errMsg=${result.error?.message ?? ''}`);
    } else {
      this.footerMessage = '刷新失败,请重试';
    }
  }

  private async loadMoreTopics(): Promise<void> {
    if (!this.isArkWebReady) {
      this.footerMessage = '正在准备 ArkWeb 请求环境';
      return;
    }

    this.loadSiteMetadataIfNeeded();

    if (this.isRefreshing || this.isLoadingMore || !this.hasMore || this.topics.length === 0) {
      return;
    }

    this.isLoadingMore = true;
    this.requiresChallenge = false;
    this.footerMessage = '正在加载更多';

    const nextPage: number = this.currentPage + 1;
    const result: NetworkResult<TopicPage> = await this.fetchTopicPage(nextPage);
    this.isLoadingMore = false;

    if (result.success && result.data) {
      this.topics = this.mergeTopics(this.topics, result.data.topics);
      this.currentPage = nextPage;
      this.hasMore = result.data.hasMore && result.data.topics.length > 0;
      this.footerMessage = this.hasMore ? '上拉加载更多' : '没有更多了';
      return;
    }

    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.footerMessage = result.error?.message ? `${result.error.message}，上拉重试` : '加载失败，上拉重试';
  }

  private handleSessionChanged(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    this.handledSessionVersion = version;
    Log.i(`${LOG_TAG} session changed version=${version}, refresh latest topics`);
    this.footerMessage = '会话已更新，正在刷新';
    this.refreshLatestTopics();
  }

  private handleTopicReadStateChanged(state: TopicReadState): void {
    for (let index: number = 0; index < this.topics.length; index++) {
      const topic: Topic = this.topics[index];
      if (topic.id === state.topicId) {
        // @Observed 实例赋值 → 对应 TopicListItem(@ObjectLink)精准重渲染。
        topic.unseen = state.unseen;
        topic.unreadPosts = state.unreadPosts;
        // 同步已读水位(最高楼 − 剩余未读):再点未读徽标时跳转目标才是最新的第一条未读楼。
        if (topic.highestPostNumber !== undefined && topic.highestPostNumber > 0) {
          topic.lastReadPostNumber = Math.max(0, topic.highestPostNumber - state.unreadPosts);
        }
        Log.i(`${LOG_TAG} topic read state synced topicId=${state.topicId} unreadPosts=${state.unreadPosts}`);
        return;
      }
    }
  }

  // 点未读徽标:目标楼 = 已读水位 + 1(封顶最高楼)。字段缺失(匿名/异常数据)退化为普通打开。
  private handleUnreadBadgeClick(topic: Topic): void {
    topic.unseen = false;
    const lastRead: number = topic.lastReadPostNumber ?? 0;
    if (lastRead <= 0) {
      this.onTopicClick(topic);
      return;
    }
    let target: number = lastRead + 1;
    const highest: number = topic.highestPostNumber ?? 0;
    if (highest > 0 && target > highest) {
      target = highest;
    }
    this.onOpenTopicAtPost(topic, target);
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady && this.topics.length === 0) {
      this.loadSiteMetadataIfNeeded();
      this.refreshLatestTopics();
    }
    this.checkVersionAnnouncement();
  }

  // 首页就绪后拉版本公告:用当前 versionCode 从公告帖末尾往前匹配 [v<code>] 那条回复弹出。
  // 冷启动只查一次;桥是父组件注入的 @Prop,服务必须在此惰性创建(字段初始化器会捕获空壳默认 bridge)。
  private async checkVersionAnnouncement(): Promise<void> {
    Log.i(`${ANNOUNCE_DIAG} 触发检查 isArkWebReady=${this.isArkWebReady} 本次挂载已查过=${this.announceChecked}`);
    if (this.announceChecked || !this.isArkWebReady) {
      return;
    }
    this.announceChecked = true;

    const versionCode: number = this.readVersionCode();
    Log.i(`${ANNOUNCE_DIAG} 当前 versionCode=${versionCode} ALWAYS_SHOW=${ANNOUNCE_ALWAYS_SHOW}`);
    if (versionCode <= 0) {
      Log.w(`${ANNOUNCE_DIAG} versionCode 读取失败,跳过`);
      return;
    }
    if (!ANNOUNCE_ALWAYS_SHOW && this.announceAlreadyShown(versionCode)) {
      Log.i(`${ANNOUNCE_DIAG} 该版本已弹过,跳过(改 ALWAYS_SHOW=true 可强制弹)`);
      return;
    }

    const service: VersionAnnouncementService = new VersionAnnouncementService(this.bridge);
    const announcement: VersionAnnouncement | null = await service.fetchForVersion(versionCode);
    if (!announcement) {
      Log.i(`${ANNOUNCE_DIAG} 无匹配公告,不弹窗`);
      return;
    }
    Log.i(`${ANNOUNCE_DIAG} 弹出公告 楼号=${announcement.postNumber}`);
    this.announceCooked = announcement.cookedHtml;
    this.announceVisible = true;
    if (!ANNOUNCE_ALWAYS_SHOW) {
      this.markAnnounceShown(versionCode);
    }
  }

  private readVersionCode(): number {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionCode;
    } catch (error) {
      Log.w(`${LOG_TAG} 读取 versionCode 失败: ${JSON.stringify(error)}`);
      return 0;
    }
  }

  private announceAlreadyShown(versionCode: number): boolean {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(getContext(this), { name: ANNOUNCE_PREFS_NAME });
      return (store.getSync(ANNOUNCE_SHOWN_CODE_KEY, 0) as number) === versionCode;
    } catch (error) {
      return false;
    }
  }

  private markAnnounceShown(versionCode: number): void {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(getContext(this), { name: ANNOUNCE_PREFS_NAME });
      store.putSync(ANNOUNCE_SHOWN_CODE_KEY, versionCode);
      store.flush();
    } catch (error) {
      Log.w(`${LOG_TAG} 记录已弹版本失败: ${JSON.stringify(error)}`);
    }
  }

  private syncSessionVersion(): void {
    this.handleSessionChanged(SessionEventBus.getCurrentVersion());
  }

  private async loadSiteMetadataIfNeeded(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  private mergeTopics(existingTopics: Topic[], nextTopics: Topic[]): Topic[] {
    const seenTopicIds: Map<number, boolean> = new Map();
    const mergedTopics: Topic[] = [];

    for (let index: number = 0; index < existingTopics.length; index++) {
      const topic: Topic = existingTopics[index];
      seenTopicIds.set(topic.id, true);
      mergedTopics.push(topic);
    }

    for (let index: number = 0; index < nextTopics.length; index++) {
      const topic: Topic = nextTopics[index];
      if (!seenTopicIds.get(topic.id)) {
        seenTopicIds.set(topic.id, true);
        mergedTopics.push(topic);
      }
    }

    return mergedTopics;
  }
}

// 调试用输入框:填帖子 ID 直接跳转详情。
@CustomDialog
struct TopicJumpDialog {
  controller: CustomDialogController;
  onConfirm: (topicId: number) => void = () => {};
  @State private idText: string = '';

  build() {
    Column() {
      Text('跳转到帖子')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 16 })

      TextInput({ placeholder: '输入帖子 ID' })
        .type(InputType.Number)
        .defaultFocus(true)
        .fontSize(16)
        .height(46)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(10)
        .onChange((value: string) => {
          this.idText = value;
        })
        .onSubmit(() => {
          this.confirm();
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_muted'))
          .onClick(() => {
            this.controller.close();
          })

        Button('跳转')
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.brand'))
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
      .margin({ top: 20 })
    }
    .width('80%')
    .padding(20)
    .backgroundColor($r('app.color.page_bg'))
    .borderRadius(16)
  }

  private confirm(): void {
    const topicId: number = parseInt(this.idText.trim(), 10);
    if (isNaN(topicId) || topicId <= 0) {
      return;
    }
    this.controller.close();
    this.onConfirm(topicId);
  }
}
