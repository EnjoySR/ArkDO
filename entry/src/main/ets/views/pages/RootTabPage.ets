import { Log } from '../../services/logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { APP_IS_WIDE_STORAGE_KEY, BreakpointManager } from '../../common/utils/BreakpointManager';
import { ActivityRouteParam, AppRouteName, BadgesRouteParam, BookmarksRouteParam, buildActivityRouteParam, buildBadgesRouteParam, buildBookmarksRouteParam, buildDraftsRouteParam, buildDohSettingsRouteParam, buildLevelProgressRouteParam, buildNotificationsRouteParam, buildProfileRouteParam, buildReadTopicsRouteParam, buildSettingsRouteParam, buildSitesRouteParam, buildSolvedRouteParam, buildTopicDetailRouteParam, buildTopicDetailDraftRouteParam, buildUserProfileRouteParam, buildWebRouteParam, isActivityRouteParam, isBadgesRouteParam, isBookmarksRouteParam, isDraftsRouteParam, DraftsRouteParam, isSolvedRouteParam, isTopicDetailRouteParam, isUserProfileRouteParam, isWebRouteParam, LevelProgressRouteParam, SolvedRouteParam, TopicDetailRouteParam, UserProfileRouteParam, WebRouteParam } from '../../navigation/AppRoutes';
import { LinkRouter, LinkTarget, LinkTargetKind } from '../../services/content/LinkRouter';
import { DownloadService } from '../../services/content/DownloadService';
import { DownloadEventBus, DownloadResult } from '../../services/content/DownloadEventBus';
import { common } from '@kit.AbilityKit';
import window from '@ohos.window';
import { APP_IS_DARK_STORAGE_KEY } from '../../common/theme/ThemeManager';
import { ImmersiveWindow } from '../../common/utils/ImmersiveWindow';
import { Topic } from '../../models/Topic';
import { User } from '../../models/User';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../../services/challenge/ChallengeEventBus';
import { ChallengeRecoveryCoordinator } from '../../services/challenge/ChallengeRecoveryCoordinator';
import { ChallengeRecoveryEventBus } from '../../services/challenge/ChallengeRecoveryEventBus';
import { ChallengeShortcutEventBus } from '../../services/challenge/ChallengeShortcutEventBus';
import { AuthService } from '../../services/auth/AuthService';
import { NotificationService } from '../../services/notification/NotificationService';
import { NotificationEventBus } from '../../services/notification/NotificationEventBus';
import { HarmonyPushTokenProvider } from '../../services/push/HarmonyPushTokenProvider';
import { PushNotificationPermissionResult, PushNotificationPermissionService } from '../../services/push/PushNotificationPermissionService';
import { HttpPushRelayClient } from '../../services/push/PushRelayClient';
import { PushRegistrationResult, PushRelayRegistration, PushRelayUser, PushStatusResult, PushSubscriptionService } from '../../services/push/PushSubscriptionService';
import { PushSubscriptionStore, StoredPushSubscription } from '../../services/push/PushSubscriptionStore';
import { describePushNotificationRoute, PushNotificationRoute } from '../../services/push/PushNotificationNavigation';
import { PushNotificationNavigationEventBus } from '../../services/push/PushNotificationNavigationEventBus';
import { PushTokenUpdateEventBus } from '../../services/push/PushTokenUpdateEventBus';
import { isPushRelayConfigured, PushRelayConfig, resolvePushRelayConfig } from '../../services/push/PushRelayConfig';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { AvatarImageCache } from '../../services/network/AvatarImageCache';
import { SiteIconStore } from '../../services/site/SiteIconStore';
import { image } from '@kit.ImageKit';
import { DohManager, DohResolveMode } from '../../services/network/DohManager';
import { NetworkResult, NetworkErrorCode, ChallengeState } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { LoginGate } from '../../services/session/LoginGate';
import { ArkWebHost } from '../components/ArkWebHost';
import { MathRenderHost } from '../components/MathRenderHost';
import {
  IMAGE_VIEWER_BACK_TICK_KEY,
  IMAGE_VIEWER_VISIBLE_KEY,
  ImageViewer,
  ViewerImage
} from '../components/ImageViewer';
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
import { SitesPage, SITES_TICK } from './SitesPage';
import { LevelProgressPage } from './LevelProgressPage';
import { BookmarksPage } from './BookmarksPage';
import { DraftsPage, DRAFTS_COMPOSER_BACK_TICK_KEY, DRAFTS_COMPOSER_VISIBLE_KEY, DRAFTS_REFRESH_TICK_KEY } from './DraftsPage';
import { ActivityListPage } from './ActivityListPage';
import { ReadTopicsPage } from './ReadTopicsPage';
import { BadgesPage } from './BadgesPage';
import { UserProfilePage } from './UserProfilePage';
import { SolvedPostsPage } from './SolvedPostsPage';
import { TopicDetailPage } from './TopicDetailPage';
import { COMPOSER_OVERLAY_BACK_TICK_KEY, COMPOSER_OVERLAY_VISIBLE_KEY } from './ComposerPage';
import { WebViewPage } from './WebViewPage';

const LOG_TAG: string = '[ArkDO][Root]';
// 推送自愈的单账号连续失败上限:超过就停手,等下次冷启动或 token 轮换再试,
// 免得离线时每轮会话轮询都白打一次网络。
const PUSH_RECONCILE_MAX_ATTEMPTS: number = 3;
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';
// ===== 首页左滑跟手拉出个人中心 =====
// 松手判定阈值:滑过屏宽这个比例即补完,否则回弹。
const SWIPE_COMMIT_RATIO: number = 0.4;
// 松手判定阈值:横向甩速(vp/s)超过即直接补完,不看距离。
const SWIPE_COMMIT_VELOCITY: number = 800;
// ↓↓↓ 手感就调这三个:补完时长、回弹时长、收尾曲线。 ↓↓↓
const SWIPE_COMMIT_MS: number = 280;
const SWIPE_REBOUND_MS: number = 220;
const SWIPE_SETTLE_CURVE: Curve = Curve.Friction;
// 首页视差(对齐系统默认转场的观感):个人中心滑到底时,首页左移自身宽度的这个比例、并压暗这个幅度。
// 与个人中心的位移共用同一个 progress,天然同步。0 即关掉视差。
const SWIPE_PARALLAX_RATIO: number = 0.25;
const SWIPE_PARALLAX_DIM: number = 0.08;

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
  // 预览返回键信号:Index @Entry 拦截后 bump,经 @Param 透传给 ImageViewer(翻回上一张/首图关闭)。
  @StorageProp(IMAGE_VIEWER_BACK_TICK_KEY) private viewerBackTick: number = 0;
  // 主窗口引用:图片预览期间隐藏/恢复状态栏用(打开时获取,关闭后释放)。
  // 窗口常驻全屏布局(ImmersiveWindow):状态栏避让下沉到各页面的顶层内容容器
  // (padding 加在带页面背景色的容器上,背景自然填满状态栏条且颜色逐页正确);
  // 页面内遮罩/浮层留在未加 padding 的层级,天然盖满物理屏。此处 Navigation 不加任何避让。
  private viewerWindow?: window.Window = undefined;
  // 帖子搜索浮层:根 Stack 顶层内联渲染(不进 Navigation 栈),由首页搜索图标触发。
  @State private showSearchOverlay: boolean = false;
  // 系统返回键信号:浮层不进导航栈,返回键由 Index @Entry 拦截并 bump 此计数,这里监听后关闭浮层。
  @StorageProp(SEARCH_OVERLAY_BACK_TICK_KEY) @Watch('onSearchBackTick') private searchBackTick: number = 0;
  @State private isArkWebReady: boolean = false;
  // 宿主真就绪信号:仅在 onReady(onPageEnd,executor 已挂)时自增。isArkWebReady 会被看门狗/失败路径
  // 提前置真且烧掉 false→true 跳变,导致真就绪时首页的 @Watch(isArkWebReady) 不再触发、列表卡在失败态;
  // 用这个独立单调计数专门驱动「真就绪后重拉列表」,与 UI 解锁标志解耦。
  @State private hostReadyEpoch: number = 0;
  @State private currentUser?: User = undefined;
  @State private isCheckingSession: boolean = false;
  @State private hasCheckedSession: boolean = false;
  private bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private notificationService: NotificationService = new NotificationService(this.bridge);
  private pushPermissionService: PushNotificationPermissionService = new PushNotificationPermissionService();
  private pushSubscriptionService?: PushSubscriptionService = undefined;
  private navPathStack: NavPathStack = new NavPathStack();
  // 手势激活闸:仅此为 true 时 customNavContentTransition 才接管 PROFILE 的 push;
  // 点头像那条路照走系统默认转场,互不干扰。
  @State private profileSwipeActive: boolean = false;
  // 跟手进度 0~1:同时驱动 ProfilePage 的 translate、首页视差、proxy.updateTransition,三者共用一个源。
  @State private profileSwipeProgress: number = 0;
  private profileSwipeProxy?: NavigationTransitionProxy = undefined;
  // 收尾动画进行中:此间不许 onTransitionEnd 重置 active,否则位移表达式短路成 0、页面瞬移归位,
  // 收尾动画等于白播(表现为"一松手就唰一下到位")。
  private profileSwipeSettling: boolean = false;
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
  private unsubscribePushNavigation?: () => void = undefined;
  private unsubscribePushTokenUpdate?: () => void = undefined;
  // 推送自愈:已成功自愈过的账号身份(避免每轮会话轮询重复跑)、并发闸、失败重试计数。
  private pushReconcileAccountKey: string = '';
  private pushReconcileInFlight: boolean = false;
  private pushReconcileAttempts: number = 0;
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
    if (!this.unsubscribePushNavigation) {
      this.unsubscribePushNavigation = PushNotificationNavigationEventBus.subscribe((route: PushNotificationRoute) => {
        this.handlePushNotificationRoute(route);
      });
    }
    const pendingPushRoute: PushNotificationRoute | undefined = PushNotificationNavigationEventBus.takePending();
    if (pendingPushRoute) {
      this.handlePushNotificationRoute(pendingPushRoute);
    }
    // 设备 token 轮换:中继里的旧 token 已投不到本机,须重新登记(force 绕开账号去重)。
    if (!this.unsubscribePushTokenUpdate) {
      this.unsubscribePushTokenUpdate = PushTokenUpdateEventBus.subscribe(() => {
        PushTokenUpdateEventBus.clearPending();
        this.reconcilePushSubscription(true);
      });
    }
    if (PushTokenUpdateEventBus.takePending()) {
      this.reconcilePushSubscription(true);
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
    if (this.unsubscribePushNavigation) {
      this.unsubscribePushNavigation();
      this.unsubscribePushNavigation = undefined;
    }
    if (this.unsubscribePushTokenUpdate) {
      this.unsubscribePushTokenUpdate();
      this.unsubscribePushTokenUpdate = undefined;
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
          backTick: this.viewerBackTick,
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
            // 浮层只从左栏入口打开,选中结果等同于「换一帖」而非「深入一层」,故与左栏同路。
            this.closeSearch();
            this.selectTopicFromMaster(topic.id, topic.slug, topic.title);
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
    // 只接管「手势闸打开 + PUSH + 目标是 PROFILE」这一种;其余一律返回 undefined 走系统默认,
    // 不影响其他页面的转场。
    .customNavContentTransition((from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
      return this.buildProfileSwipeTransition(to, operation);
    })
  }

  private buildProfileSwipeTransition(to: NavContentInfo, operation: NavigationOperation): NavigationAnimatedTransition | undefined {
    if (!this.profileSwipeActive || operation !== NavigationOperation.PUSH || to.name !== AppRouteName.PROFILE) {
      return undefined;
    }
    return {
      // 不开这个,updateTransition / cancelTransition 全是空操作(API 12 起)。
      isInteractive: true,
      // 兜底:手势异常中断没人收尾时超时自动结束,避免转场悬着——挂起期间 Navigation 吞掉所有输入。
      timeout: 3000,
      transition: (proxy: NavigationTransitionProxy) => {
        this.profileSwipeProxy = proxy;
        proxy.updateTransition?.(0);
      },
      // 注:实测每次转场此回调会触发两遍(系统行为),故这里必须保持幂等,别塞非幂等副作用。
      onTransitionEnd: (success: boolean) => {
        this.profileSwipeProxy = undefined;
        // 收尾动画还在播时不要重置——留给动画的 onFinish 收,否则页面当场瞬移。
        if (!this.profileSwipeSettling) {
          this.profileSwipeActive = false;
          this.profileSwipeProgress = 0;
        }
      }
    };
  }

  // 手指按下即 push:跟手要求目标页当场在场,晚了就跟不上手指(实测 push 到转场就绪 ≈15~20ms,一帧内)。
  private handleProfileSwipeStart(): void {
    // 宽屏(平板横屏)是 Split 双栏:首页常驻左栏、个人中心出现在右栏,
    // "把页面从右边拖进来"这个隐喻不成立,视差还会把左栏整个推走。宽屏只留点头像入口。
    if (this.appIsWide || this.profileSwipeActive || this.profileSwipeSettling) {
      return;
    }
    this.profileSwipeActive = true;
    this.profileSwipeProgress = 0;
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.PROFILE, buildProfileRouteParam('homeSwipe')));
  }

  private handleProfileSwipeUpdate(progress: number): void {
    if (!this.profileSwipeActive) {
      return;
    }
    this.profileSwipeProgress = progress;
    this.profileSwipeProxy?.updateTransition?.(progress);
  }

  // 松手:过阈值或甩速够快就补完,否则回弹。两条路的收尾动画都由自绘 translate 播,
  // 时长/曲线见顶部三个常量。
  private handleProfileSwipeEnd(progress: number, velocity: number): void {
    if (!this.profileSwipeActive || this.profileSwipeSettling) {
      return;
    }
    const commit: boolean = progress >= SWIPE_COMMIT_RATIO || velocity >= SWIPE_COMMIT_VELOCITY;
    this.profileSwipeSettling = true;
    if (commit) {
      // 先自绘把页面推到满屏,推到位了再 finish。
      // 不能一松手就 finish——系统当场判定转场结束并撤掉 NavBar,而自绘动画还要再播 SWIPE_COMMIT_MS,
      // 这期间页面尚未盖满,露出的那条缝背后首页已经没了(表现为"背后首页突然消失")。
      this.settleProfileSwipe(1, SWIPE_COMMIT_MS, () => {
        this.profileSwipeProxy?.finishTransition();
      });
    } else {
      // 回弹走 finish+pop,不走 cancelTransition:
      //   cancelTransition 虽然能把栈回滚干净(栈深归 0),但会把 NavBar 的 eventHub 永久留在禁用态
      //   ——此后首页命中测试恒为空,上下滑/左滑/点击全死,只有渲染还在动(GIF 照转),极难察觉。
      //   系统日志实锤:"NavBar/12 eventHub not enabled" + "Touch test result is empty."
      //   而正常 POP 流程会把 eventHub 收拾干净,故绕道:让 push 落地再补一次 pop。
      // 顺序上先自绘把页面滑回屏外,滑到看不见了再 finish+pop——
      // finish 那一下页面会瞬间归位,把它藏在屏幕外,眼睛看到的全程才是平滑的。
      this.settleProfileSwipe(0, SWIPE_REBOUND_MS, () => {
        this.profileSwipeProxy?.finishTransition();
        this.navPathStack.pop(false);
      });
    }
  }

  // 把进度动画到 target,播完执行 after 并复位。
  // 注意:target 与当前进度相等时 animateTo 无状态变化,onFinish 不会触发——
  // 必须走同步分支,否则 active 永久卡 true、转场悬着不落地(下一次左滑直接失灵)。
  private settleProfileSwipe(target: number, duration: number, after: () => void): void {
    const finishUp: () => void = () => {
      after();
      this.profileSwipeSettling = false;
      this.profileSwipeActive = false;
      this.profileSwipeProgress = 0;
    };
    if (Math.abs(this.profileSwipeProgress - target) < 0.001) {
      finishUp();
      return;
    }
    this.getUIContext().animateTo({
      duration: duration,
      curve: SWIPE_SETTLE_CURVE,
      onFinish: finishUp
    }, () => {
      this.profileSwipeProgress = target;
    });
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
          // 顶栏过盾快捷入口:直接开验证页,并让恢复协调器停掉后台静默重试、把弹窗交给用户接管
          // (与首页空态「手动验证」同一路径),否则协调器可能正处于 DISMISSED 保持期而把弹窗吞掉。
          onOpenChallenge: () => {
            this.challengeRecovery?.forceEscalate();
            this.openChallengeSheet();
          },
          // 图片预览上抛到根级渲染:双栏下才能盖满整窗、旋转正常。
          onOpenImages: (images: ViewerImage[], startIndex: number) => {
            this.openImageViewer(images, startIndex);
          },
          onOpenLink: (url: string) => {
            this.handleOpenLink(url);
          },
          onOpenUser: (user: User) => {
            this.openUserProfileFor(user);
          }
        })
      }
      .hideTitleBar(true)
      // 详情页返回键优先消费本页内联浮层:全屏编辑器 > 图片预览。二者都从详情页打开、
      // Navigation 栈非空,返回键先到栈顶 NavDestination(轮不到 Index @Entry),不拦会直接弹掉详情页。
      .onBackPressed(() => this.consumeTopicDetailBack())
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
          },
          // 只有「我的站点」打开的页面才留 favicon(带 siteId);帖子外链的图标直接丢弃。
          onFaviconReceived: (favicon: image.PixelMap) => {
            this.cacheSiteFavicon((param as WebRouteParam).siteId, favicon);
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
          onOpenDrafts: (username: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.DRAFTS, buildDraftsRouteParam(username)));
          },
          onLogoutCleanup: () => {
            return this.disableSystemPushForLogout();
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
      // 左滑跟手时本页的位移。百分比相对自身宽度,不必测屏宽:progress=0 整页停在右侧屏外,=1 归位。
      // 手势闸关闭时恒 0,点头像那条路(系统默认转场)不受影响。
      .translate({ x: this.profileSwipeActive ? `${(1 - this.profileSwipeProgress) * 100}%` : 0 })
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
          currentUser: this.currentUser ?? this.getAnonymousUser(),
          isLoggedIn: this.currentUser !== undefined,
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
          },
          onEnablePush: () => {
            return this.enableSystemPush();
          },
          onDisablePush: () => {
            return this.disableSystemPush();
          },
          onRefreshPush: () => {
            return this.refreshSystemPushStatus();
          },
          onSendTestPush: () => {
            return this.sendTestSystemPush();
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
    } else if (name === AppRouteName.SITES) {
      NavDestination() {
        SitesPage({
          onBack: () => {
            this.popNavigation();
          },
          onOpenSite: (url: string, title: string, siteId: string) => {
            this.openWebPage(url, title, siteId);
          }
        })
      }
      .hideTitleBar(true)
      // 从站点的 WEB 页 pop 回来时本页重新可见,自增计数让站点页重读——favicon 此刻可能刚落盘。
      .onShown(() => {
        const prev: number = (AppStorage.get(SITES_TICK) as number | undefined) ?? 0;
        AppStorage.setOrCreate(SITES_TICK, prev + 1);
      })
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
    } else if (name === AppRouteName.DRAFTS && isDraftsRouteParam(param)) {
      NavDestination() {
        DraftsPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as DraftsRouteParam).username,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string) => {
            this.openTopicDetailById(topicId, undefined, title, undefined, false);
          },
          onOpenTopicWithDraft: (topicId: number, title: string, draftReply: string, draftKey: string, sequence: number) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.TOPIC_DETAIL,
              buildTopicDetailDraftRouteParam(topicId, title, draftReply, draftKey, sequence)));
          },
          onOpenWeb: (url: string, title: string) => {
            this.openWebPage(url, title);
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
      // 从帖子详情 pop 回来时本页重新可见:自增计数让草稿页重拉列表。
      // 续写发表后草稿已在服务端删除,不重拉的话返回时那条还挂在列表里(要手动下拉才消失)。
      .onShown(() => {
        const prev: number = (AppStorage.get(DRAFTS_REFRESH_TICK_KEY) as number | undefined) ?? 0;
        AppStorage.setOrCreate(DRAFTS_REFRESH_TICK_KEY, prev + 1);
      })
      // 续写浮层开着时返回键先关浮层,不 pop 掉草稿页。
      .onBackPressed(() => this.consumeDraftsBack())
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
    } else if (name === AppRouteName.USER_PROFILE && isUserProfileRouteParam(param)) {
      NavDestination() {
        UserProfilePage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as UserProfileRouteParam).username,
          seedDisplayName: (param as UserProfileRouteParam).displayName ?? '',
          seedAvatarTemplate: (param as UserProfileRouteParam).avatarTemplate ?? '',
          seedUserId: (param as UserProfileRouteParam).userId ?? 0,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, title: string, postNumber?: number) => {
            this.openTopicDetailById(topicId, undefined, title, postNumber, postNumber !== undefined);
          },
          onOpenActivity: (username: string, filter: string, title: string) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.ACTIVITY, buildActivityRouteParam(username, filter, title)));
          },
          onOpenBadges: (username: string, badgeCount: number) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.BADGES, buildBadgesRouteParam(username, badgeCount)));
          },
          onOpenSolved: (username: string, solvedCount: number) => {
            this.navPathStack.pushPath(new NavPathInfo(AppRouteName.SOLVED, buildSolvedRouteParam(username, solvedCount)));
          },
          // 互动圈头像可点:递归 push 同一路由,栈自然记住来路。
          onOpenUser: (username: string, displayName: string, avatarTemplate: string, userId: number) => {
            this.openUserProfile(username, displayName, avatarTemplate, userId);
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
    } else if (name === AppRouteName.SOLVED && isSolvedRouteParam(param)) {
      NavDestination() {
        SolvedPostsPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          username: (param as SolvedRouteParam).username,
          solvedCount: (param as SolvedRouteParam).solvedCount,
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
      hostReadyEpoch: this.hostReadyEpoch,
      accountUser: this.currentUser ?? this.getAnonymousUser(),
      isLoggedIn: this.currentUser !== undefined,
      isCheckingSession: this.isCheckingSession,
      hasCheckedSession: this.hasCheckedSession,
      onAccountClick: () => {
        this.handleAccountClick();
      },
      // 左滑跟手拉出个人中心:手势在 HomePage,导航栈在这里,故三个阶段由它上抛给宿主驱动。
      onProfileSwipeStart: () => {
        this.handleProfileSwipeStart();
      },
      onProfileSwipeUpdate: (progress: number) => {
        this.handleProfileSwipeUpdate(progress);
      },
      onProfileSwipeEnd: (progress: number, velocity: number) => {
        this.handleProfileSwipeEnd(progress, velocity);
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
        this.selectTopicFromMaster(topic.id, topic.slug, topic.title);
      },
      onOpenTopicById: (topicId: number) => {
        this.selectTopicFromMaster(topicId);
      },
      onOpenTopicAtPost: (topic: Topic, postNumber: number) => {
        this.selectTopicFromMaster(topic.id, topic.slug, topic.title, postNumber);
      },
      onOpenSites: () => {
        this.navPathStack.pushPath(new NavPathInfo(AppRouteName.SITES, buildSitesRouteParam('drawer')));
      },
      onOpenSite: (url: string, title: string, siteId: string) => {
        this.openWebPage(url, title, siteId);
      }
    })
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    // 视差:跟手期间首页左移+压暗,补上自绘转场缺失的层次感
    // (系统默认转场自带这层,一旦用 customNavContentTransition 接管就得自己画,否则首页完全静止)。
    // 百分比相对自身宽度,不必测屏宽。手势闸关闭时恒复位,点头像那条路不受影响。
    .translate({ x: this.profileSwipeActive ? `${-SWIPE_PARALLAX_RATIO * 100 * this.profileSwipeProgress}%` : 0 })
    .brightness(this.profileSwipeActive ? 1 - SWIPE_PARALLAX_DIM * this.profileSwipeProgress : 1)
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

  // 左栏(navBar)发起的选帖。宽屏 Split 下左栏与右栏并排常驻、列表一直可点,若沿用 push
  // 就是每点一次往右栏摞一层([占位,详情,详情,…]),返回键要按十几次才退得出,且旧详情页
  // 连同各自的 Web / 公式引擎全悬着不释放。故宽屏改走「清回占位基座 + 压入新详情」:
  // 栈深恒为 2,点一百次也是 2,返回一次即回占位空态。
  // 窄屏(手机 / 平板竖屏)是 Stack 单栏,详情盖满屏、左栏根本点不到,原样 push,与改前完全一致。
  private selectTopicFromMaster(topicId: number, slug?: string, title?: string, targetPostNumber?: number, highlightTarget?: boolean): void {
    if (!this.appIsWide) {
      this.openTopicDetailById(topicId, slug, title, targetPostNumber, highlightTarget);
      return;
    }
    // 点的就是右栏正显示的那一帖 → 短路。否则白白重建详情页:Web 重载、滚动位置归零。
    if (this.isTopicOnTop(topicId, targetPostNumber)) {
      return;
    }
    Log.i(`${LOG_TAG} master select topicId=${topicId} target=${targetPostNumber ?? 0} depth=${this.navPathStack.size()}`);
    this.resetWideContentToPlaceholder();
    // 两次栈操作同帧合并,占位页拿不到渲染机会,不会闪;分栏换选中项本也不该有推入动效。
    this.navPathStack.pushPath(new NavPathInfo(
      AppRouteName.TOPIC_DETAIL,
      buildTopicDetailRouteParam(topicId, slug, title ? title : '', targetPostNumber, highlightTarget)
    ), false);
  }

  // 把右栏清成只剩占位基座。占位不在栈里(竖屏期间被 removeByName 清掉、转回横屏时 size()≠0
  // 未补垫的遗留栈)则就地重建——反正本就要整个换掉右栏内容,顺手自愈这条路径。
  private resetWideContentToPlaceholder(): void {
    const baseIndex: number = this.navPathStack.getAllPathName().indexOf(AppRouteName.PLACEHOLDER);
    if (baseIndex >= 0) {
      this.navPathStack.popToIndex(baseIndex, false);
    } else {
      this.navPathStack.clear(false);
      this.navPathStack.pushPathByName(AppRouteName.PLACEHOLDER, undefined, false);
    }
  }

  // 右栏栈顶是否已是目标帖。定位楼号也要一致——点未读徽标是要跳到另一楼,不算同一目标。
  private isTopicOnTop(topicId: number, targetPostNumber?: number): boolean {
    const names: string[] = this.navPathStack.getAllPathName();
    const topIndex: number = names.length - 1;
    if (topIndex < 0 || names[topIndex] !== AppRouteName.TOPIC_DETAIL) {
      return false;
    }
    const param: Object | undefined = this.navPathStack.getParamByIndex(topIndex) as Object | undefined;
    if (!isTopicDetailRouteParam(param)) {
      return false;
    }
    const top: TopicDetailRouteParam = param as TopicDetailRouteParam;
    return top.topicId === topicId && top.targetPostNumber === targetPostNumber;
  }

  // 统一的链接点击入口:经 LinkRouter 判断——站内帖子链接提取 topicId 跳原生详情页,
  // 站内用户主页链接(含正文 @提及)跳原生他人主页,其余(外站、站内其他页)一律打开通用 WebView。
  private handleOpenLink(url: string): void {
    const target: LinkTarget = LinkRouter.resolve(url);
    if (target.kind === LinkTargetKind.TOPIC && target.topicId !== undefined) {
      Log.i(`${LOG_TAG} link -> native topic detail topicId=${target.topicId}`);
      this.openTopicDetailById(target.topicId);
      return;
    }
    if (target.kind === LinkTargetKind.USER && target.username !== undefined) {
      Log.i(`${LOG_TAG} link -> native user profile username=${target.username}`);
      // 资料由主页自己按 username 拉,这里没有 displayName/头像可透传。
      this.openUserProfile(target.username, '', '', 0);
      return;
    }
    if (target.kind === LinkTargetKind.DOWNLOAD) {
      this.startDownload(target.url);
      return;
    }
    this.openWebPage(target.url);
  }

  private handlePushNotificationRoute(route: PushNotificationRoute): void {
    PushNotificationNavigationEventBus.clearPending(route.id);
    const target: LinkTarget = LinkRouter.resolve(route.url);
    Log.i(`${LOG_TAG} push route path=${describePushNotificationRoute(route)} kind=${target.kind}`);
    if (target.kind === LinkTargetKind.TOPIC && target.topicId !== undefined) {
      // 走 selectTopicFromMaster 而非 openTopicDetailById:宽屏(平板横屏)下它会先清回占位基座
      // 再压栈,栈深恒为 2。否则连点多条推送会把详情页一层层摞上去,要按同样次数返回键才退得出来,
      // 且每层的 Web/MathJax 引擎都悬着不释放。窄屏时它内部自动回退到 openTopicDetailById。
      this.selectTopicFromMaster(target.topicId, undefined, route.title, target.postNumber, target.postNumber !== undefined);
      // 点推送即视为已看这条通知:把它标为已读并把铃铛未读数减 1。即发即忘,不阻塞打开帖子。
      this.markPushNotificationRead(target.topicId, target.postNumber);
      return;
    }
    if (target.kind === LinkTargetKind.USER && target.username !== undefined) {
      this.openUserProfile(target.username, '', '', 0);
      return;
    }
    this.openWebPage(target.url, route.title);
  }

  // 点推送即视为看过这条通知:反查该帖对应通知并标记已读,同时把铃铛未读数乐观减 1。
  // 委托给 notificationService(它持有 bridge 与未读数总线)。即发即忘,不阻塞打开帖子。
  private markPushNotificationRead(topicId: number, postNumber?: number): void {
    this.notificationService.markPushNotificationRead(topicId, postNumber);
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

  private async enableSystemPush(): Promise<PushRegistrationResult> {
    return this.ensureSystemPush(true);
  }

  private async refreshSystemPushStatus(): Promise<PushStatusResult> {
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    const user: User | undefined = this.currentUser;
    if (!context || user === undefined || user.id <= 0 || user.username.length === 0) {
      return { enabled: false, message: '请先登录 linux.do' };
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    if (!stored.desiredEnabled || PushSubscriptionStore.toRegistration(stored) === undefined) {
      return { enabled: false, message: '未开启' };
    }

    // 只报状态,不重注册。以前这里跑的是完整 ensure(取 token→中继→linux.do 写请求),
    // 于是离线或中继暂时不可达时进一次设置页,就把开关误翻成"关闭"——而服务端订阅其实还在。
    // 订阅的保活/自愈交给 reconcilePushSubscription 在后台静默做,不参与本页开关的显示。
    const permission: PushNotificationPermissionResult = await this.pushPermissionService.checkEnabled();
    if (!permission.enabled) {
      // 订阅还在,只是系统通知权限被关了:开关保持"开",但把原因说清楚。
      return { enabled: true, message: permission.message };
    }

    return {
      enabled: true,
      message: '已开启'
    };
  }

  private async ensureSystemPush(requestPermission: boolean): Promise<PushRegistrationResult> {
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (!context) {
      return {
        success: false,
        message: '通知权限申请失败: 缺少 AbilityContext'
      };
    }
    const user: User | undefined = this.currentUser;
    if (user === undefined || user.id <= 0 || user.username.length === 0) {
      return {
        success: false,
        message: '请先登录 linux.do 账号'
      };
    }
    // 中继地址来自随包配置(不进版本控制)或用户自填。自行编译且没配的话推送不可用,
    // 这里明确说清楚,免得用户以为是网络或账号问题。
    if (!isPushRelayConfigured(context)) {
      return {
        success: false,
        message: '未配置推送中继,请在设置中填写中继地址'
      };
    }

    const permission: PushNotificationPermissionResult = requestPermission
      ? await this.pushPermissionService.ensureEnabled(context)
      : await this.pushPermissionService.checkEnabled();
    if (!permission.enabled) {
      return {
        success: false,
        message: permission.message
      };
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    const relayUser: PushRelayUser = {
      userId: user.id,
      username: user.username
    };
    const result: PushRegistrationResult = await this.pushSubscriptionServiceRef(context).enable(relayUser, stored.subId);
    if (result.success && result.endpoint !== undefined && result.p256dh !== undefined && result.auth !== undefined) {
      PushSubscriptionStore.saveEnabled(context, user.id, {
        subId: result.subId,
        endpoint: result.endpoint,
        p256dh: result.p256dh,
        auth: result.auth
      });
    }
    return result;
  }

  private async disableSystemPush(): Promise<PushRegistrationResult> {
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    const user: User | undefined = this.currentUser;
    if (!context || user === undefined || user.id <= 0 || user.username.length === 0) {
      return { success: false, message: '请先登录 linux.do 账号' };
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    const registration: PushRelayRegistration | undefined = PushSubscriptionStore.toRegistration(stored);
    if (registration === undefined) {
      PushSubscriptionStore.saveDisabled(context, user.id);
      return { success: true, message: '推送订阅已关闭' };
    }
    const relayUser: PushRelayUser = {
      userId: user.id,
      username: user.username
    };
    const result: PushRegistrationResult = await this.pushSubscriptionServiceRef(context).disable(registration, relayUser);
    if (result.success) {
      PushSubscriptionStore.saveDisabled(context, user.id);
    }
    return result;
  }

  // 推送保活/自愈:订阅不是"开一次永久有效"——中继连续投递失败超 1 天会被 Discourse 删掉
  // (MAX_ERRORS),设备 token 也会因重装/恢复出厂/系统刷新而轮换,两种情况都会让推送静默失效。
  // 故在登录态落定与 token 轮换时,对"用户开过推送"的账号静默重跑一遍订阅登记。
  // 这套动作本就幂等:中继按 (deviceToken, user) 复用同一 subId,linux.do 同 endpoint 重复
  // subscribe 也不会重复建,所以代价很小。
  // 全程静默:这是后台自愈而非用户发起的操作,失败不弹 toast、不翻设置页开关。
  private async reconcilePushSubscription(force: boolean): Promise<void> {
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    const user: User | undefined = this.currentUser;
    if (!context || user === undefined || user.id <= 0 || user.username.length === 0) {
      return;
    }
    if (this.pushReconcileInFlight) {
      return;
    }

    const accountKey: string = `${user.id}`;
    if (accountKey !== this.pushReconcileAccountKey) {
      // 换号(或本次启动首次落定):重置重试预算。
      this.pushReconcileAttempts = 0;
    } else if (!force && this.pushReconcileAttempts >= PUSH_RECONCILE_MAX_ATTEMPTS) {
      // 同一账号已连续失败到上限:停手,等下次启动或 token 轮换再说,免得每轮会话轮询都打网络。
      return;
    }

    // 只兑现用户自己开过的推送,绝不擅自替用户开启。
    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    if (!stored.desiredEnabled) {
      this.pushReconcileAccountKey = accountKey;
      return;
    }
    if (!force && accountKey === this.pushReconcileAccountKey && this.pushReconcileAttempts === 0) {
      // 本账号本次启动已自愈成功过,无须重复。
      return;
    }

    this.pushReconcileInFlight = true;
    this.pushReconcileAccountKey = accountKey;
    // 调用方是即发即忘(不 await),异常不能逃逸成未处理拒绝;失败一律按"本次自愈没成"记账。
    try {
      const result: PushRegistrationResult = await this.ensureSystemPush(false);
      if (result.success) {
        this.pushReconcileAttempts = 0;
        Log.i(`${LOG_TAG} push reconcile ok userId=${user.id} force=${force}`);
        return;
      }
      this.pushReconcileAttempts++;
      Log.i(`${LOG_TAG} push reconcile failed userId=${user.id} attempts=${this.pushReconcileAttempts} message=${result.message}`);
    } catch (err) {
      this.pushReconcileAttempts++;
      Log.i(`${LOG_TAG} push reconcile exception userId=${user.id} attempts=${this.pushReconcileAttempts} error=${JSON.stringify(err)}`);
    } finally {
      this.pushReconcileInFlight = false;
    }
  }

  // 服务依赖惰性构造:this.bridge 是父注入的 prop,字段初始化器里取到的是空壳,须调用时再读。
  // 中继地址/密钥每次都重新解析:用户可能刚在设置页改过自建地址,缓存住会用错服务器。
  private pushSubscriptionServiceRef(context: common.Context): PushSubscriptionService {
    const config: PushRelayConfig = resolvePushRelayConfig(context);
    this.pushSubscriptionService = new PushSubscriptionService(
      this.bridge,
      new HarmonyPushTokenProvider(),
      new HttpPushRelayClient(config.baseUrl, config.apiKey)
    );
    return this.pushSubscriptionService;
  }

  // 登出前清理系统推送。必须在 AuthService.logout 之前跑完:linux.do 退订要带登录 cookie,
  // 登出后就退不掉了,那条订阅会连同中继里的 deviceToken 一起留存——本机继续收到该账号的
  // 私信/回复推送(换号后亦然,属跨账号泄露),而设置页此时因未登录连开关都点不动。
  // 失败不阻断登出:中继解绑成功即可,之后中继返回 410,Discourse 自行删除订阅。
  private async disableSystemPushForLogout(): Promise<void> {
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    const user: User | undefined = this.currentUser;
    if (!context || user === undefined || user.id <= 0) {
      return;
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    const registration: PushRelayRegistration | undefined = PushSubscriptionStore.toRegistration(stored);
    if (registration === undefined) {
      // 没有有效订阅:仅把本地开关落回关闭,避免重新登录后误显示"已开启"。
      if (stored.desiredEnabled) {
        PushSubscriptionStore.saveDisabled(context, user.id);
      }
      return;
    }

    Log.i(`${LOG_TAG} logout push cleanup start userId=${user.id} subId=${stored.subId}`);
    await this.pushSubscriptionServiceRef(context).disableForLogout(registration, {
      userId: user.id,
      username: user.username
    });
    // 无论两侧结果如何都清本地:登出后已无登录态可重试,留着只会让 UI 显示错误的"已开启"。
    PushSubscriptionStore.saveDisabled(context, user.id);
    Log.i(`${LOG_TAG} logout push cleanup done userId=${user.id}`);
  }

  private async sendTestSystemPush(): Promise<PushStatusResult> {
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    const user: User | undefined = this.currentUser;
    if (!context || user === undefined || user.id <= 0 || user.username.length === 0) {
      return { enabled: false, message: '请先登录 linux.do 账号' };
    }

    const ensureResult: PushRegistrationResult = await this.ensureSystemPush(false);
    if (!ensureResult.success) {
      return {
        enabled: false,
        message: ensureResult.message
      };
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    const registration: PushRelayRegistration | undefined = PushSubscriptionStore.toRegistration(stored);
    if (registration === undefined || (registration.subId ?? '').length === 0) {
      return { enabled: false, message: '推送订阅参数无效' };
    }

    const relayUser: PushRelayUser = {
      userId: user.id,
      username: user.username
    };
    return this.pushSubscriptionServiceRef(context).sendTest(registration, relayUser);
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Log.i(`${LOG_TAG} toast failed: ${message}`);
    }
  }

  private openWebPage(url: string, title?: string, siteId?: string): void {
    if (!url || url.length === 0) {
      return;
    }
    Log.i(`${LOG_TAG} open web page host=${url.replace(/^https?:\/\/([^\/?#]+).*$/i, '$1')}`);
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.WEB, buildWebRouteParam(url, title, siteId)));
  }

  // 缓存站点 favicon:仅对「我的站点」打开的页面(带 siteId)落盘,其余一律丢弃。
  // 引擎每次加载都会回调,故站点换 logo 后下次打开即自动更新。失败只记日志——图标是锦上添花,
  // 拿不到就回退默认图标,不该打扰用户。
  private cacheSiteFavicon(siteId: string | undefined, favicon: image.PixelMap): void {
    if (!siteId || siteId.length === 0) {
      return;
    }
    SiteIconStore.save(getContext(this), siteId, favicon);
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
  // 窗口常驻全屏布局(ImmersiveWindow),浮层在 Navigation 之外天然铺满物理屏——无须切窗口模式、
  // 无须背景补偿。这里只做一件窗口级小事:预览期间隐藏状态栏(时间/电量不印在图上),关闭时恢复。
  // 全屏布局下系统栏显隐不引起任何布局变化,且隐藏触发的插图归零事件被 suppress 丢弃,
  // 背景 padding 全程一个值,不存在可闪的重排。
  private openImageViewer(images: ViewerImage[], startIndex: number): void {
    this.viewerImages = images;
    this.viewerStartIndex = startIndex;
    // 镜像可见态:预览打开期间系统返回键由 Index @Entry 拦截(翻回上一张/首图关闭)。
    AppStorage.setOrCreate(IMAGE_VIEWER_VISIBLE_KEY, true);
    // 先暂停插图同步再隐藏,归零事件不落到背景 padding 上。
    ImmersiveWindow.suppressInsetSync(true);
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.viewerWindow = win;
      win.setWindowSystemBarEnable(['navigation']).catch(() => {});
      // 底部手势条图标改白,黑底上可见。
      win.setWindowSystemBarProperties({
        navigationBarContentColor: '#FFFFFF'
      }).catch(() => {});
    }).catch(() => {});
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.showImageViewer = true;
    });
  }

  // 详情页返回键统一入口:先看全屏编辑器浮层(可见则 bump tick 交详情页一镜回落),再看图片预览。
  // 都没开返回 false 放行默认 pop(弹掉详情页)。挂在详情页 NavDestination 的 onBackPressed 上。
  // 草稿页的续写浮层打开时消费返回键(bump tick 让 DraftsPage 关浮层);未开则放行默认 pop。
  private consumeDraftsBack(): boolean {
    const visible: boolean = (AppStorage.get(DRAFTS_COMPOSER_VISIBLE_KEY) as boolean | undefined) ?? false;
    if (visible) {
      const prev: number = (AppStorage.get(DRAFTS_COMPOSER_BACK_TICK_KEY) as number | undefined) ?? 0;
      AppStorage.setOrCreate(DRAFTS_COMPOSER_BACK_TICK_KEY, prev + 1);
      return true;
    }
    return false;
  }

  private consumeTopicDetailBack(): boolean {
    const composerVisible: boolean = (AppStorage.get(COMPOSER_OVERLAY_VISIBLE_KEY) as boolean | undefined) ?? false;
    if (composerVisible) {
      const prev: number = (AppStorage.get(COMPOSER_OVERLAY_BACK_TICK_KEY) as number | undefined) ?? 0;
      AppStorage.setOrCreate(COMPOSER_OVERLAY_BACK_TICK_KEY, prev + 1);
      return true;
    }
    return this.consumeViewerBack();
  }

  // 图片预览打开时消费返回键:bump 信号计数,交 ImageViewer 决定翻回上一张还是关闭;
  // 未打开时返回 false 放行默认 pop。挂在详情页 NavDestination 的 onBackPressed 上。
  private consumeViewerBack(): boolean {
    if (!this.showImageViewer) {
      return false;
    }
    const prev: number = (AppStorage.get(IMAGE_VIEWER_BACK_TICK_KEY) as number | undefined) ?? 0;
    AppStorage.setOrCreate(IMAGE_VIEWER_BACK_TICK_KEY, prev + 1);
    return true;
  }

  private closeImageViewer(): void {
    AppStorage.setOrCreate(IMAGE_VIEWER_VISIBLE_KEY, false);
    const win: window.Window | undefined = this.viewerWindow;
    if (win !== undefined) {
      // 恢复状态栏显示;图标色统一走 ImmersiveWindow 按当前主题基线恢复。
      win.setWindowSystemBarEnable(['status', 'navigation']).catch(() => {});
      const dark: boolean = (AppStorage.get(APP_IS_DARK_STORAGE_KEY) as boolean | undefined) ?? false;
      ImmersiveWindow.applyBarContentColor(dark);
      this.viewerWindow = undefined;
    }
    // 恢复插图同步:状态栏重新出现触发的 avoidAreaChange 会把插图写回(与预览前同值,padding 不动)。
    ImmersiveWindow.suppressInsetSync(false);
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
    // 宿主真就绪:自增信号驱动首页重拉列表。看门狗/失败路径已提前把 isArkWebReady 置真、烧掉了
    // false→true 跳变,单靠 @Watch(isArkWebReady) 无法在真就绪时唤醒列表(会卡在失败态直到手点重试);
    // 这个独立计数专门补上「真就绪 → 自愈列表」这条路径。
    this.hostReadyEpoch++;
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

  // 他人主页:点任意头像(帖子作者、互动圈、通知等)进来。
  // displayName/avatarTemplate 由调用方顺手透传,资料请求回来前先渲染,避免首屏跳动。
  // 点自己的头像不进这里——「我的」页有登出/设置/草稿,是另一个页面。
  private openUserProfile(username: string, displayName: string, avatarTemplate: string, userId: number): void {
    if (username.length === 0) {
      return;
    }
    if (this.currentUser !== undefined && username === this.currentUser.username) {
      this.openProfilePage();
      return;
    }
    this.navPathStack.pushPath(new NavPathInfo(AppRouteName.USER_PROFILE,
      buildUserProfileRouteParam(username, displayName, avatarTemplate, userId)));
  }

  // 从 User 对象开头像入口:各处调用点手里拿的都是 User,省得每处都拆字段。
  private openUserProfileFor(user?: User): void {
    if (!user || user.username.length === 0) {
      return;
    }
    this.openUserProfile(user.username, user.displayName ? user.displayName : '',
      user.avatarTemplate ? user.avatarTemplate : '', user.id);
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
        // 登录态已落定:此刻才拿得到 userId,兑现该账号此前开过的推送订阅(保活/自愈)。
        // 内部按账号去重,不会每轮轮询都跑。
        this.reconcilePushSubscription(false);
      } else {
        this.notificationService.stop();
        // 登出/换号:清掉自愈基准,让下一个账号登录时重新兑现自己的订阅。
        this.pushReconcileAccountKey = '';
        this.pushReconcileAttempts = 0;
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
    // 盾已过:收起详情页右上角的过盾快捷入口(不等下一次 timings 上报成功才收,免得图标空挂着)。
    ChallengeShortcutEventBus.notifyCleared();
    this.closeChallengePage();
    // 反馈:已过盾时验证页会秒关(源站 404 即通过),给个 toast 免得用户以为闪退/没反应。
    this.showToast('已通过 Cloudflare 验证');
  }
}
