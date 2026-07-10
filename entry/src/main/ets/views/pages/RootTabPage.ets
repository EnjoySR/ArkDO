import { Log } from '../../services/logging/Log';
import { ActivityRouteParam, AppRouteName, BadgesRouteParam, BookmarksRouteParam, buildActivityRouteParam, buildBadgesRouteParam, buildBookmarksRouteParam, buildDohSettingsRouteParam, buildLevelProgressRouteParam, buildNotificationsRouteParam, buildProfileRouteParam, buildSettingsRouteParam, buildTopicDetailRouteParam, buildWebRouteParam, isActivityRouteParam, isBadgesRouteParam, isBookmarksRouteParam, isTopicDetailRouteParam, isWebRouteParam, LevelProgressRouteParam, TopicDetailRouteParam, WebRouteParam } from '../../navigation/AppRoutes';
import { LinkRouter, LinkTarget, LinkTargetKind } from '../../services/content/LinkRouter';
import { DownloadService } from '../../services/content/DownloadService';
import { DownloadEventBus, DownloadResult } from '../../services/content/DownloadEventBus';
import { common } from '@kit.AbilityKit';
import { Topic } from '../../models/Topic';
import { User } from '../../models/User';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../../services/challenge/ChallengeEventBus';
import { ChallengeRecoveryCoordinator } from '../../services/challenge/ChallengeRecoveryCoordinator';
import { AuthService } from '../../services/auth/AuthService';
import { NotificationService } from '../../services/notification/NotificationService';
import { NotificationEventBus } from '../../services/notification/NotificationEventBus';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { AvatarImageCache } from '../../services/network/AvatarImageCache';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { ArkWebHost } from '../components/ArkWebHost';
import { MathRenderHost } from '../components/MathRenderHost';
import { ensureFaIconsLoaded } from '../components/FaIcon';
import { ensureTagIconsLoaded } from '../components/TagIconRegistry';
import { CfChallengePage } from './CfChallengePage';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { NotificationPage } from './NotificationPage';
import { ProfilePage } from './ProfilePage';
import { SettingsPage } from './SettingsPage';
import { DohSettingsPage } from './DohSettingsPage';
import { LevelProgressPage } from './LevelProgressPage';
import { BookmarksPage } from './BookmarksPage';
import { ActivityListPage } from './ActivityListPage';
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
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private handledChallengeVersion: number = ChallengeEventBus.getCurrentVersion();
  private unsubscribeChallengeRequired?: () => void = undefined;
  private unsubscribeSessionChanged?: () => void = undefined;
  private unsubscribeDownload?: () => void = undefined;
  // 挑战恢复协调器:优先后台静默过盾,失败才弹窗。惰性创建(需闭包引用本组件方法)。
  private challengeRecovery?: ChallengeRecoveryCoordinator = undefined;

  aboutToAppear(): void {
    this.ensureIconSymbolsLoaded();
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
  }

  build() {
    Stack() {
      ArkWebHost({
        bridge: this.bridge,
        onReady: () => {
          this.handleArkWebReady();
        }
      })
      // 公式离屏引擎:仅在有含数学公式的帖子打开时(refCount>0)才挂载,离开后空闲销毁。
      if (this.mathHostActive) {
        MathRenderHost()
      }
      this.RootNavigation()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.isSheetVisible, this.RootSheetBuilder, {
      height: '90%',
      dragBar: true,
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
          isLoggedIn: this.currentUser !== undefined,
          username: this.currentUser?.username ?? '',
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
          }
        })
      }
      .hideTitleBar(true)
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

  private handleArkWebReady(): void {
    this.isArkWebReady = true;
    // 注入沙箱上下文,让 host webview 的下载委托知道文件保存目录(filesDir/download)。
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context) {
      this.bridge.setDownloadContext(context);
    }
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
      this.currentUser = result.data;
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
