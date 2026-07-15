import { Log } from '../../services/logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { APP_IS_WIDE_STORAGE_KEY, BreakpointManager } from '../../common/utils/BreakpointManager';
import { ActivityRouteParam, AppRouteName, BadgesRouteParam, BookmarksRouteParam, buildActivityRouteParam, buildBadgesRouteParam, buildBookmarksRouteParam, buildDohSettingsRouteParam, buildLevelProgressRouteParam, buildNotificationsRouteParam, buildProfileRouteParam, buildReadTopicsRouteParam, buildSettingsRouteParam, buildTopicDetailRouteParam, buildWebRouteParam, isActivityRouteParam, isBadgesRouteParam, isBookmarksRouteParam, isTopicDetailRouteParam, isWebRouteParam, LevelProgressRouteParam, TopicDetailRouteParam, WebRouteParam } from '../../navigation/AppRoutes';
import { LinkRouter, LinkTarget, LinkTargetKind } from '../../services/content/LinkRouter';
import { DownloadService } from '../../services/content/DownloadService';
import { DownloadEventBus, DownloadResult } from '../../services/content/DownloadEventBus';
import { common } from '@kit.AbilityKit';
import { Topic } from '../../models/Topic';
import { User } from '../../models/User';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../../services/challenge/ChallengeEventBus';
import { ChallengeRecoveryCoordinator } from '../../services/challenge/ChallengeRecoveryCoordinator';
import { ChallengeRecoveryEventBus } from '../../services/challenge/ChallengeRecoveryEventBus';
import { AuthService } from '../../services/auth/AuthService';
import { NotificationService } from '../../services/notification/NotificationService';
import { NotificationEventBus } from '../../services/notification/NotificationEventBus';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { AvatarImageCache } from '../../services/network/AvatarImageCache';
import { DohManager, DohResolveMode } from '../../services/network/DohManager';
import { NetworkResult, NetworkErrorCode, ChallengeState } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { LoginGate } from '../../services/session/LoginGate';
import { ArkWebHost } from '../components/ArkWebHost';
import { MathRenderHost } from '../components/MathRenderHost';
import { ImageViewer, ViewerImage } from '../components/ImageViewer';
import { SEARCH_OVERLAY_BACK_TICK_KEY, SEARCH_OVERLAY_VISIBLE_KEY, SearchOverlay } from '../components/SearchOverlay';
import { ensureFaIconsLoaded } from '../components/FaIcon';
import { ensureTagIconsLoaded } from '../components/TagIconRegistry';
import { CfChallengePage } from './CfChallengePage';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { NotificationPage } from './NotificationPage';
import { ProfilePage } from './ProfilePage';
import { SettingsPage, SETTINGS_DOH_TICK } from './SettingsPage';
import { DohSettingsPage } from './DohSettingsPage';
import { LevelProgressPage } from './LevelProgressPage';
import { BookmarksPage } from './BookmarksPage';
import { ActivityListPage } from './ActivityListPage';
import { ReadTopicsPage } from './ReadTopicsPage';
import { BadgesPage } from './BadgesPage';
import { TopicDetailPage } from './TopicDetailPage';
import { WebViewPage } from './WebViewPage';

const LOG_TAG: string = '[ArkDO][Root]';
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';

enum RootSheet {
  NONE = 0,
  LOGIN = 1,
  CHALLENGE = 2
}

@Component
export struct RootTabPage {
  // 单一 bindSheet:同一组件链多个 bindSheet 只有最后一个生效,会导致登录 sheet 不显示。
  @State private isSheetVisible: boolean = false;
  @State private activeSheet: RootSheet = RootSheet.NONE;
  // 公式离屏引擎挂载门控:由 MathRenderService.retain/release 经 AppStorage 翻转。
  @StorageProp('mathHostActive') private mathHostActive: boolean = false;
  // 宽屏标志(平板横屏 / 大屏):驱动 Navigation 双栏 Split;手机、平板竖屏恒为 false 走单栏 Stack。
  // @Watch 在宽<->窄切换(旋转)时同步右栏空占位:进宽屏且空栈时垫占位,回窄屏时移除占位。
  @StorageProp(APP_IS_WIDE_STORAGE_KEY) @Watch('onWideChanged') private appIsWide: boolean = false;
  // 图片浏览器提到根级渲染:双栏下必须盖满整窗(否则只占右详情栏),旋转时随根 Stack 重排。
  // 由详情页经 onOpenImages 回调冒泡上来触发,统一在这里开关。
  @State private showImageViewer: boolean = false;
  @State private viewerImages: ViewerImage[] = [];
  @State private viewerStartIndex: number = 0;
  // 帖子搜索浮层:根 Stack 顶层内联渲染(不进 Navigation 栈),由首页搜索图标触发。
  @State private showSearchOverlay: boolean = false;
  // 系统返回键信号:浮层不进导航栈,返回键由 Index @Entry 拦截并 bump 此计数,这里监听后关闭浮层。
  @StorageProp(SEARCH_OVERLAY_BACK_TICK_KEY) @Watch('onSearchBackTick') private searchBackTick: number = 0;
  @State private isArkWebReady: boolean = false;
  @State private currentUser?: User = undefined;
  @State private isCheckingSession: boolean = false;
  @State private hasCheckedSession: boolean = false;
  private bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private notificationService: NotificationService = new NotificationService(this.bridge);
  private navPathStack: NavPathStack = new NavPathStack();
  private sessionCheckSequence: number = 0;
  // 上次会话检查是否失败(CF 盾/网络原因,状态可能不真实),下拉刷新时据此补查。
  private lastSessionCheckFailed: boolean = false;
  // 网络层自愈闸:长时间后台回前台后宿主 webview 连接/DNS 可能僵死(status=0 且非 CF 盾),
  // 首次遇到时重载一次宿主拿新连接并重查;每段失败只自愈一次,成功后复位,避免重载死循环。
  private hasSelfHealedNetwork: boolean = false;
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private handledChallengeVersion: number = ChallengeEventBus.getCurrentVersion();
  private unsubscribeChallengeRequired?: () => void = undefined;
  private unsubscribeSessionChanged?: () => void = undefined;
  private unsubscribeDownload?: () => void = undefined;
  private unsubscribeRequireLogin?: () => void = undefined;
  private unsubscribeManualChallenge?: () => void = undefined;
  // 挑战恢复协调器:优先后台静默过盾,失败才弹窗。惰性创建(需闭包引用本组件方法)。
  private challengeRecovery?: ChallengeRecoveryCoordinator = undefined;

  aboutToAppear(): void {
    this.ensureIconSymbolsLoaded();
    // 冷启动即在宽屏(平板横屏)时,给空的右详情栏垫上占位(@Watch 只在切换时触发,首值需手动同步)。
    this.syncWidePlaceholder();
    // 头像缓存单例注入 host bridge:UserAvatar 深层嵌套拿不到 bridge,统一经它取图(过 SNI 封锁)。
    AvatarImageCache.getInstance().attachBridge(this.bridge);
    if (!this.challengeRecovery) {
      this.challengeRecovery = new ChallengeRecoveryCoordinator(
        this.bridge,
        () => {
          // 恢复成功:广播会话刷新——重载 host、复查登录态、刷新列表。
          SessionEventBus.notifySessionChanged();
        },
        () => {
          this.openChallengeSheet();
        },
        () => {
          // 过盾窗口开始:临时借用 AUTO,让 challenges.cloudflare.com 回退系统 DNS 解出来(不落盘)。
          DohManager.applyTransientMode(getContext(this), DohResolveMode.AUTO);
        },
        () => {
          // 过盾结束:还原用户持久化的 DoH 设置(通常 SECURE_ONLY),不让 AUTO 泄漏到正常浏览。
          DohManager.applyActive(getContext(this));
        }
      );
    }
    if (!this.unsubscribeChallengeRequired) {
      this.unsubscribeChallengeRequired = ChallengeEventBus.subscribe((event: ChallengeRequiredEvent) => {
        this.handleChallengeRequired(event);
      });
    }
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }
    if (!this.unsubscribeDownload) {
      this.unsubscribeDownload = DownloadEventBus.subscribe((result: DownloadResult) => {
        this.handleDownloadResult(result);
      });
    }
    // 深层页面/楼层动作在未登录时点写操作,经 LoginGate 请求登录,统一在此弹出登录页。
    if (!this.unsubscribeRequireLogin) {
      this.unsubscribeRequireLogin = LoginGate.subscribe(() => {
        this.openLoginPage();
      });
    }
    // 首页"手动验证"按钮:停后台静默恢复并直接弹可见验证页。
    if (!this.unsubscribeManualChallenge) {
      this.unsubscribeManualChallenge = ChallengeRecoveryEventBus.subscribeManual(() => {
        this.challengeRecovery?.forceEscalate();
      });
    }
  }

  aboutToDisappear(): void {
    this.notificationService.stop();
    this.challengeRecovery?.dispose();
    if (this.unsubscribeChallengeRequired) {
      this.unsubscribeChallengeRequired();
      this.unsubscribeChallengeRequired = undefined;
    }
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
    if (this.unsubscribeDownload) {
      this.unsubscribeDownload();
      this.unsubscribeDownload = undefined;
    }
    if (this.unsubscribeRequireLogin) {
      this.unsubscribeRequireLogin();
      this.unsubscribeRequireLogin = undefined;
    }
    if (this.unsubscribeManualChallenge) {
      this.unsubscribeManualChallenge();
      this.unsubscribeManualChallenge = undefined;
    }
  }

  build() {
    Stack() {
      ArkWebHost({
        bridge: this.bridge,
        onReady: () => {
          this.handleArkWebReady();
        },
        onLoadFailed: () => {
          this.handleArkWebLoadFailed();
        }
      })
      // 公式离屏引擎:仅在有含数学公式的帖子打开时(refCount>0)才挂载,离开后空闲销毁。
      if (this.mathHostActive) {
        MathRenderHost()
      }
      this.RootNavigation()

      // 图片浏览器:根 Stack 顶层,越过 Navigation 分栏盖满整窗(双栏下也全屏,旋转随根重排)。
      if (this.showImageViewer) {
        ImageViewer({
          images: this.viewerImages,
          startIndex: this.viewerStartIndex,
          onClose: () => {
            this.closeImageViewer();
          }
        })
          // 入场/退场:纯淡入淡出,由 open/close 的 animateTo 驱动。
          .transition(
            TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
          )
      }

      // 帖子搜索浮层:根 Stack 顶层,从当前页融合展开(淡入,由 open/close 的 animateTo 驱动)。
      if (this.showSearchOverlay) {
        SearchOverlay({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onClose: () => {
            this.closeSearch();
          },
          onOpenTopic: (topic: Topic) => {
            // 先关浮层再进详情:详情页正常 push 滑入,返回即回到首页(浮层已关)。
            this.closeSearch();
            this.openTopicDetail(topic);
          }
        })
          .transition(
            TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
          )
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 根 Stack 铺满整窗,其实测宽度即窗口宽度:布局驱动断点,首帧与旋转/分屏都会触发。
    // 宽度过阈值(840vp)→ appIsWide 置真 → Navigation 切双栏。比 mediaquery 更可靠。
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      BreakpointManager.applyWidth(newValue.width as number);
    })
    .bindSheet($$this.isSheetVisible, this.RootSheetBuilder, {
      // CF 交互式挑战需要尽量完整的视口(半屏+圆角+露底会被 Turnstile 视作可疑),且过盾中途
      // 不该被误滑关,故 CHALLENGE 用满高全屏、去拖动条;登录 sheet 维持 90% 底部弹层。
      height: this.activeSheet === RootSheet.CHALLENGE ? '100%' : '90%',
      dragBar: this.activeSheet !== RootSheet.CHALLENGE,
      // CF 验证弹窗自带「关闭」按钮,隐藏原生右上角 X 避免出现两个关闭入口;其余 sheet 保留原生 X。
      showClose: this.activeSheet !== RootSheet.CHALLENGE,
      maskColor: '#33000000',
      backgroundColor: $r('app.color.surface_card'),
      preferType: SheetType.BOTTOM,
      enableOutsideInteractive: false,
      onDisappear: () => {
        this.activeSheet = RootSheet.NONE;
        // 弹窗以任意方式关闭(X/下滑/关闭按钮),若仍在等待兜底则让协调器复位;已解决则无副作用。
        this.challengeRecovery?.notifySheetDismissed();
      }
    })
  }

  @Builder
  private RootNavigation() {
    Navigation(this.navPathStack) {
      this.HomeRoot()
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    // 显式驱动分栏:仅宽屏(平板横屏)双栏 Split,手机 / 平板竖屏单栏 Stack。
    // 不用默认 Auto——其 520vp 阈值会把平板竖屏也切成双栏。手机恒 Stack,与现状一致。
    .mode(this.appIsWide ? NavigationMode.Split : NavigationMode.Stack)
    // 左列表栏宽(仅 Split 生效,Stack/手机下忽略):
    //  ① 调宽列表,读着不挤;② 须 ≥ 分区抽屉宽度(288),否则抽屉滑出会溢进右详情栏。
    //  想微调列表宽度只改这一个数即可。
    .navBarWidth(420)
    .navDestination(this.NavDestinationBuilder)
  }

  @Builder
  private NavDestinationBuilder(name: string, param: Object | undefined) {
    if (name === AppRouteName.TOPIC_DETAIL && isTopicDetailRouteParam(param)) {
      NavDestination() {
        TopicDetailPage({
          param: param as TopicDetailRouteParam,
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onBack: () => {
            this.popNavigation();
          },
          // 图片预览上抛到根级渲染:双栏下才能盖满整窗、旋转正常。
          onOpenImages: (images: ViewerImage[], startIndex: number) => {
            this.openImageViewer(images, startIndex);
          },
          onOpenLink: (url: string) => {
            this.handleOpenLink(url);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.WEB && isWebRouteParam(param)) {
      NavDestination() {
        WebViewPage({
          url: (param as WebRouteParam).url,
          pageTitle: (param as WebRouteParam).title ?? '',
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.NOTIFICATIONS) {
      NavDestination() {
        NotificationPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, slug: string | undefined, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, slug, title, postNumber, postNumber !== undefined);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.PROFILE) {
      NavDestination() {
        ProfilePage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          accountUser: this.currentUser ?? this.getAnonymousUser(),
          isLoggedIn: this.currentUser !== undefined,
          isCheckingSession: this.isCheckingSession,
          hasCheckedSession: this.hasCheckedSession,
          onLoginClick: () => {
            this.openLoginPage();
          },
          onOpenWeb: (url: string, title?: string) => {
            this.openWebPage(url, title);
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          },
          onOpenReadTopics: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.READ_TOPICS, buildReadTopicsRouteParam('profile')));
          },
          onOpenBookmarks: (username: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.BOOKMARKS, buildBookmarksRouteParam(username)));
          },
          onOpenActivity: (username: string, filter: string, title: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.ACTIVITY, buildActivityRouteParam(username, filter, title)));
          },
          onOpenBadges: (username: string, badgeCount: number) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.BADGES, buildBadgesRouteParam(username, badgeCount)));
          },
          onOpenSettings: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.SETTINGS, buildSettingsRouteParam('profile')));
          },
          onOpenLevelProgress: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.LEVEL_PROGRESS,
              buildLevelProgressRouteParam(this.currentUser !== undefined)));
          },
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.LEVEL_PROGRESS) {
      NavDestination() {
        LevelProgressPage({
          isLoggedIn: (param as LevelProgressRouteParam).isLoggedIn,
          onBack: () => {
            this.popNavigation();
          },
          onOpenWeb: (url: string, title?: string) => {
            this.openWebPage(url, title);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.SETTINGS) {
      NavDestination() {
        SettingsPage({
          onBack: () => {
            this.popNavigation();
          },
          onOpenWeb: (url: string, title?: string) => {
            this.openWebPage(url, title);
          },
          onOpenDoh: () => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.DOH_SETTINGS, buildDohSettingsRouteParam('settings')));
          },
          onActiveChallenge: () => {
            // 主动过盾:直接打开交互式 CF 验证 sheet(绕过协调器静默阶段),过盾后刷新会话。
            this.openChallengeSheet();
          },
          onOpenFeedback: () => {
            // 标题留空:详情页拉到帖子后自会填真实标题,不必在此硬编码一份易过期的副本。
            this.openTopicDetailById(AppConstants.FEEDBACK_TOPIC_ID);
          }
        })
      }
      .hideTitleBar(true)
      // 从 DoH 配置页 pop 回来时本页重新可见,自增 AppStorage 计数,让设置页 @StorageProp 重读
      // DoH 摘要(此刻本页已在前台,变更能可靠触发重渲染;单纯 @Prop 不会流入 NavDestination 子树)。
      .onShown(() => {
        const prev: number = (AppStorage.get(SETTINGS_DOH_TICK) as number | undefined) ?? 0;
        AppStorage.setOrCreate(SETTINGS_DOH_TICK, prev + 1);
      })
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.DOH_SETTINGS) {
      NavDestination() {
        DohSettingsPage({
          onBack: () => {
            this.popNavigation();
          },
          onDohApplied: () => {
            this.reloadHostForDoh();
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.ACTIVITY && isActivityRouteParam(param)) {
      NavDestination() {
        ActivityListPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as ActivityRouteParam).username,
          filter: (param as ActivityRouteParam).filter,
          pageTitle: (param as ActivityRouteParam).title,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.READ_TOPICS) {
      NavDestination() {
        ReadTopicsPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onBack: () => {
            this.popNavigation();
          },
          onTopicClick: (topic: Topic) => {
            this.openTopicDetail(topic);
          },
          onOpenTopicAtPost: (topic: Topic, postNumber: number) => {
            this.openTopicDetailById(topic.id, topic.slug, topic.title, postNumber);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.BOOKMARKS && isBookmarksRouteParam(param)) {
      NavDestination() {
        BookmarksPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as BookmarksRouteParam).username,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.BADGES && isBadgesRouteParam(param)) {
      NavDestination() {
        BadgesPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as BadgesRouteParam).username,
          badgeCount: (param as BadgesRouteParam).badgeCount,
          onBack: () => {
            this.popNavigation();
          }
        })
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    } else if (name === AppRouteName.PLACEHOLDER) {
      // 双栏右详情栏的空占位:仅在宽屏未选帖子时垫在栈底,让右栏显示品牌空态而非系统默认空白。
      NavDestination() {
        Column() {
          Text('ArkDO')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
          Text('从左侧选择一个帖子开始阅读')
            .fontSize(15)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.page_bg'))
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    } else {
      NavDestination() {
        Column() {
          Text('页面不存在')
            .fontSize(18)
            .fontColor($r('app.color.text_primary'))
          Button('返回')
            .margin({ top: 16 })
            .onClick(() => {
              this.popNavigation();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.page_bg'))
      }
      .hideTitleBar(true)
      // NavDestination 自身背景默认铺满含状态栏区域;统一为 page_bg,让各二级页顶部状态栏
      // 与页内头部/导航栏同色(否则暗色下露出默认浅底,与内容不一致)。
      .backgroundColor($r('app.color.page_bg'))
    }
  }

  @Builder
  private RootSheetBuilder() {
    if (this.activeSheet === RootSheet.CHALLENGE) {
      CfChallengePage({
        bridge: this.bridge,
        onClose: () => {
          this.closeChallengePage();
        },
        onChallengeResolved: () => {
          this.handleChallengeResolved();
        }
      })
    } else {
      LoginPage({
        onClose: () => {
          this.closeLoginPage();
        },
        onLoginSuccess: () => {
          this.handleLoginSuccess();
        }
      })
    }
  }

  @Builder
  private HomeRoot() {
    HomePage({
      bridge: this.bridge,
      isArkWebReady: this.isArkWebReady,
      accountUser: this.currentUser ?? this.getAnonymousUser(),
      isLoggedIn: this.currentUser !== undefined,
      isCheckingSession: this.isCheckingSession,
      hasCheckedSession: this.hasCheckedSession,
      onAccountClick: () => {
        this.handleAccountClick();
      },
      onSessionRecheck: () => {
        this.recheckSessionIfNeeded();
      },
      onOpenNotifications: () => {
        this.navPathStack.pushPath(new NavPathInfo(AppRouteName.NOTIFICATIONS, buildNotificationsRouteParam('homeBell')));
      },
      onOpenSearch: () => {
        this.openSearch();
      },
      onTopicClick: (topic: Topic) => {
        this.openTopicDetail(topic);
      },
      onOpenTopicById: (topicId: number) => {
        this.openTopicDetailById(topicId);
      },
      onOpenTopicAtPost: (topic: Topic, postNumber: number) => {
        this.openTopicDetailById(topic.id, topic.slug, topic.title, postNumber);
      }
    })
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  private openLoginPage(): void {
    // 弹层已开(CF 挑战/上一轮兜底)时不打断:与 openChallengeSheet/challenge-required 守卫一致。
    // 新接入的全局 LoginGate.requestLogin 可从任意深层页触发,防止覆盖正在进行的静默过盾。
    if (this.isSheetVisible) {
      return;
    }
    this.activeSheet = RootSheet.LOGIN;
    this.isSheetVisible = true;
  }

  private closeLoginPage(): void {
    this.isSheetVisible = false;
    this.activeSheet = RootSheet.NONE;
  }

  private closeChallengePage(): void {
    this.isSheetVisible = false;
    this.activeSheet = RootSheet.NONE;
  }

  private openTopicDetail(topic: Topic): void {
    this.openTopicDetailById(topic.id, topic.slug, topic.title);
  }

  // 按帖子 ID 跳转详情的通用入口(slug/title 可选,缺省时详情页按 id 加载)。
  // targetPostNumber:定位楼号(未读徽标/通知);highlightTarget:落地后短暂高亮目标楼(通知)。
  private openTopicDetailById(topicId: number, slug?: string, title?: string, targetPostNumber?: number, highlightTarget?: boolean): void {
    Log.i(`${LOG_TAG} open topic detail topicId=${topicId} title=${title ? title : ''} target=${targetPostNumber ?? 0}`);
    this.navPathStack.pushPath(new NavPathInfo(
      AppRouteName.TOPIC_DETAIL,
      buildTopicDetailRouteParam(topicId, slug, title ? title : '', targetPostNumber, highlightTarget)
    ));
  }

  // 统一的链接点击入口:经 LinkRouter 判断——站内帖子链接提取 topicId 跳原生详情页,
  // 其余(外站、站内非帖子页)一律打开通用 WebView。
  private handleOpenLink(url: string): void {
    const target: LinkTarget = LinkRouter.resolve(url);
    if (target.kind === LinkTargetKind.TOPIC && target.topicId !== undefined) {
      Log.i(`${LOG_TAG} link -> native topic detail topicId=${target.topicId}`);
      this.openTopicDetailById(target.topicId);
      return;
    }
    if (target.kind === LinkTargetKind.DOWNLOAD) {
      this.startDownload(target.url);
      return;
    }
    this.openWebPage(target.url);
  }

  // 附件下载:交给 host webview 的原生下载委托(带会话 Cookie、跟随重定向)。结果经 DownloadEventBus 回调。
  private startDownload(url: string): void {
    const started: boolean = this.bridge.startDownload(url);
    if (started) {
      this.showToast('开始下载…');
    } else {
      this.showToast('无法下载：宿主未就绪');
    }
  }

  // 下载完成/失败:toast 反馈;成功则拉起系统「打开方式/分享」,弥补文件在沙箱内、系统「文件」App 不可见。
  private handleDownloadResult(result: DownloadResult): void {
    this.showToast(result.message);
    if (!result.success) {
      return;
    }
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context) {
      DownloadService.openWithSystem(context, result.filePath);
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Log.i(`${LOG_TAG} toast failed: ${message}`);
    }
  }

  private openWebPage(url: string, title?: string): void {
    if (!url || url.length === 0) {
      return;
    }
    Log.i(`${LOG_TAG} open web page host=${url.replace(/^https?:\/\/([^\/?#]+).*$/i, '$1')}`);
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.WEB, buildWebRouteParam(url, title)));
  }

  private popNavigation(): void {
    this.navPathStack.pop();
  }

  // 宽<->窄切换时的右栏占位同步:
  //  · 宽屏(Split)且内容栈为空 → 垫入 PLACEHOLDER 当栈底,右栏显示品牌空态而非系统空白;
  //    垫在栈底后,后续打开的帖子 push 在其上,返回到底即回到占位,不会退成空白。
  //  · 窄屏(Stack / 手机)→ 移除所有 PLACEHOLDER,保证手机返回栈干净、绝不出现占位页。
  private onWideChanged(): void {
    this.syncWidePlaceholder();
  }

  private syncWidePlaceholder(): void {
    if (this.appIsWide) {
      if (this.navPathStack.size() === 0) {
        // 无动画压入,避免占位页出现时的推入动效。
        this.navPathStack.pushPathByName(AppRouteName.PLACEHOLDER, undefined, false);
      }
    } else {
      this.navPathStack.removeByName(AppRouteName.PLACEHOLDER);
    }
  }

  // 图片浏览器开关:详情页经 onOpenImages 回调冒泡上来触发。animateTo 驱动 .transition 淡入/淡出。
  private openImageViewer(images: ViewerImage[], startIndex: number): void {
    this.viewerImages = images;
    this.viewerStartIndex = startIndex;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.showImageViewer = true;
    });
  }

  private closeImageViewer(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.showImageViewer = false;
    });
  }

  // 搜索浮层开关:animateTo 驱动 .transition 淡入/淡出;同时镜像可见态到 AppStorage,
  // 供 Index @Entry 的 onBackPress 判断是否拦截系统返回键。
  private openSearch(): void {
    // 可见态切换放进 animateTo 闭包:顶栏源图标(HomePage @StorageProp 驱动移除)与浮层目标图标
    // 的出现进同一动画事务,geometryTransition 才能配对并插值(一镜到底)。
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, () => {
      AppStorage.setOrCreate(SEARCH_OVERLAY_VISIBLE_KEY, true);
      this.showSearchOverlay = true;
    });
  }

  private closeSearch(): void {
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => {
      AppStorage.setOrCreate(SEARCH_OVERLAY_VISIBLE_KEY, false);
      this.showSearchOverlay = false;
    });
  }

  // 系统返回键(Index 拦截后 bump tick):浮层开着就关掉它。
  private onSearchBackTick(): void {
    if (this.showSearchOverlay) {
      this.closeSearch();
    }
  }

  private handleArkWebReady(): void {
    this.isArkWebReady = true;
    // 注入沙箱上下文,让 host webview 的下载委托知道文件保存目录(filesDir/download)。
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context) {
      this.bridge.setDownloadContext(context);
    }
    this.checkCurrentUser();
  }

  // 宿主首屏加载失败(DoH 关 + 无代理导致 linux.do 不可达):强制解锁 UI 进入降级可导航态——
  // 首页跳出"准备环境中"、汉堡菜单出现、头像退化为可点的人像入口,用户得以进设置页开 DoH/代理自救。
  // 不必干等 DNS/连接超时(可长达 30s+)。开启 DoH 后 SessionEventBus 触发宿主重载,成功即走 onReady
  // 正常刷新列表与登录态(reloadBaseUrl 已改判 isControllerAttached,首屏失败后仍能重载)。
  private handleArkWebLoadFailed(): void {
    if (this.isArkWebReady) {
      return;
    }
    Log.i(`${LOG_TAG} ArkWeb host load failed: unblock UI so user can reach DoH settings`);
    this.isArkWebReady = true;
    this.checkCurrentUser();
  }

  private ensureIconSymbolsLoaded(): void {
    const hostContext: Context | undefined = this.getUIContext().getHostContext();
    if (!hostContext) {
      Log.i(`${LOG_TAG} icon symbols load skipped: no host context`);
      return;
    }

    const iconCount: number = ensureFaIconsLoaded(hostContext.resourceManager);
    const tagIconCount: number = ensureTagIconsLoaded(hostContext.resourceManager);
    Log.i(`${LOG_TAG} icon assets loaded symbols=${iconCount} tagIcons=${tagIconCount}`);
  }

  private handleLoginSuccess(): void {
    // 会话变化会触发 host webview 重载,先关闭就绪门闩,确保随后并发的 fetch 排队到重载完成后。
    this.bridge.markHostReloading();
    SessionEventBus.notifySessionChanged();
    this.checkCurrentUser();
    this.closeLoginPage();
  }

  // DoH 变更(切换/开关/删除当前项)后重载宿主 webview,让新 DNS 立即用于解析。
  // 复用会话变更的重载门闩:先关就绪门闩,让并发 fetch 排队到重载完成。
  private reloadHostForDoh(): void {
    this.bridge.markHostReloading();
    SessionEventBus.notifySessionChanged();
  }

  private handleAccountClick(): void {
    // 登录与否都进个人中心:未登录时该页仍有齿轮(设置→DoH)和登录入口,
    // 避免网络不通时点右上角直接弹登录、够不到 DoH 配置而被卡在门外。
    this.openProfilePage();
  }

  private openProfilePage(): void {
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.PROFILE, buildProfileRouteParam('homeAvatar')));
  }

  private getAnonymousUser(): User {
    return {
      id: 0,
      username: ''
    };
  }

  private async checkCurrentUser(): Promise<void> {
    if (!this.isArkWebReady || this.isCheckingSession) {
      return;
    }

    const requestId: number = this.sessionCheckSequence + 1;
    this.sessionCheckSequence = requestId;
    this.isCheckingSession = true;
    this.hasCheckedSession = false;
    const result: NetworkResult<User | undefined> = await new AuthService(this.bridge).getCurrentUser();
    if (requestId !== this.sessionCheckSequence) {
      return;
    }

    this.isCheckingSession = false;
    this.hasCheckedSession = true;
    if (result.success) {
      this.lastSessionCheckFailed = false;
      // 连接恢复,复位自愈闸,允许下一段网络故障再自愈一次。
      this.hasSelfHealedNetwork = false;
      this.currentUser = result.data;
      // 同步全局登录态镜像:供深层页面/楼层动作的写操作闸门(LoginGate)读取。
      LoginGate.setLoggedIn(this.currentUser !== undefined);
      Log.i(`${LOG_TAG} current user checked loggedIn=${this.currentUser !== undefined} username=${this.currentUser?.username ?? ''} hasAvatar=${this.currentUser?.avatarTemplate !== undefined}`);
      // 登录:本次响应已带未读数,立即广播一次(铃铛与头像同帧出现),再启动前台轮询;
      // 登出:停表并清零。
      if (this.currentUser !== undefined) {
        NotificationEventBus.publish({
          unread: this.currentUser.unreadNotifications !== undefined ? this.currentUser.unreadNotifications : 0,
          highPriority: this.currentUser.unreadHighPriorityNotifications !== undefined ? this.currentUser.unreadHighPriorityNotifications : 0
        });
        this.notificationService.start();
      } else {
        this.notificationService.stop();
      }
      return;
    }

    // 检查失败(CF 盾/网络抖动)≠确认未登录:保持上一次的登录状态与通知轮询不动,
    // 仅记失败标记,等下一次下拉刷新时补查。只有成功响应且 current_user 为空才真正置为未登录。
    this.lastSessionCheckFailed = true;
    Log.i(`${LOG_TAG} current user check failed status=${result.statusCode} challenge=${result.challengeState}, keep previous loggedIn=${this.currentUser !== undefined}`);

    // 长时间后台回前台后,宿主 webview 的连接/DNS 解析器可能已僵死:表现为 status=0 的纯网络
    // 失败(error=network_failure),且非 CF 盾(challengeState=NONE)。这条旧连接自己不会恢复,
    // 再怎么用它重查都白搭;重载一次宿主拿一条全新连接(等价于用户手动切 DoH 触发的重载)。
    // reloadHostForDoh 会同步 bump 会话版本 → handleSessionChanged → 宿主重载完再自动重查,
    // 无需在此显式重查。每段失败只自愈一次,重载后仍失败就退回既有兜底,不再循环重载。
    const isNetworkFailure: boolean =
      result.error?.code === NetworkErrorCode.NETWORK_FAILURE &&
      result.challengeState === ChallengeState.NONE;
    if (isNetworkFailure && !this.hasSelfHealedNetwork) {
      this.hasSelfHealedNetwork = true;
      Log.i(`${LOG_TAG} network failure self-heal: reload host and recheck`);
      this.reloadHostForDoh();
    }
  }

  // 下拉刷新时的会话补查:仅在上次检查失败(状态可能不真实)时重查一次,正常情况零开销。
  private recheckSessionIfNeeded(): void {
    if (this.lastSessionCheckFailed && !this.isCheckingSession) {
      Log.i(`${LOG_TAG} recheck session after previous failure`);
      this.checkCurrentUser();
    }
  }

  private handleSessionChanged(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    this.handledSessionVersion = version;
    this.checkCurrentUser();
  }

  private handleChallengeRequired(event: ChallengeRequiredEvent): void {
    if (event.version <= this.handledChallengeVersion) {
      return;
    }

    this.handledChallengeVersion = event.version;
    Log.i(`${LOG_TAG} challenge required version=${event.version} source=${event.source} status=${event.statusCode} state=${event.challengeState}`);
    Log.i(`${DIAG_TAG} stage=rootChallengeRequired version=${event.version} source=${event.source} status=${event.statusCode} state=${event.challengeState} activeSheet=${this.activeSheet} sheetVisible=${this.isSheetVisible}`);
    // 弹窗已开(登录/上一轮兜底)时不再打扰;其余交给协调器决定静默恢复还是升级弹窗。
    if (this.isSheetVisible) {
      return;
    }
    this.challengeRecovery?.handleChallengeSignal(event.source);
  }

  // 协调器升级:静默两次失败后才打开交互式挑战弹窗兜底。
  private openChallengeSheet(): void {
    if (this.isSheetVisible) {
      return;
    }
    this.activeSheet = RootSheet.CHALLENGE;
    this.isSheetVisible = true;
    Log.i(`${DIAG_TAG} stage=rootChallengeOpen`);
  }

  private handleChallengeResolved(): void {
    Log.i(`${LOG_TAG} challenge resolved`);
    Log.i(`${DIAG_TAG} stage=rootChallengeResolved sheetVisible=${this.isSheetVisible}`);
    // 先进冷却再关窗:onDisappear 的 notifySheetDismissed 在冷却态下即为空操作。
    this.challengeRecovery?.notifySheetResolved();
    this.closeChallengePage();
    // 反馈:已过盾时验证页会秒关(源站 404 即通过),给个 toast 免得用户以为闪退/没反应。
    this.showToast('已通过 Cloudflare 验证');
  }
}
