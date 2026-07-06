import { AppRouteName, buildNotificationsRouteParam, buildProfileRouteParam, buildTopicDetailRouteParam, buildWebRouteParam, isTopicDetailRouteParam, isWebRouteParam, TopicDetailRouteParam, WebRouteParam } from '../../navigation/AppRoutes';
import { LinkRouter, LinkTarget, LinkTargetKind } from '../../services/content/LinkRouter';
import { DownloadService } from '../../services/content/DownloadService';
import { DownloadEventBus, DownloadResult } from '../../services/content/DownloadEventBus';
import { common } from '@kit.AbilityKit';
import { Topic } from '../../models/Topic';
import { User } from '../../models/User';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../../services/challenge/ChallengeEventBus';
import { AuthService } from '../../services/auth/AuthService';
import { NotificationService } from '../../services/notification/NotificationService';
import { NotificationEventBus } from '../../services/notification/NotificationEventBus';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { ArkWebHost } from '../components/ArkWebHost';
import { ensureFaIconsLoaded } from '../components/FaIcon';
import { ensureTagIconsLoaded } from '../components/TagIconRegistry';
import { CfChallengePage } from './CfChallengePage';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { NotificationPage } from './NotificationPage';
import { ProfilePage } from './ProfilePage';
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
  @State private isArkWebReady: boolean = false;
  @State private currentUser?: User = undefined;
  @State private isCheckingSession: boolean = false;
  @State private hasCheckedSession: boolean = false;
  private bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private notificationService: NotificationService = new NotificationService(this.bridge);
  private navPathStack: NavPathStack = new NavPathStack();
  private sessionCheckSequence: number = 0;
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private handledChallengeVersion: number = ChallengeEventBus.getCurrentVersion();
  private unsubscribeChallengeRequired?: () => void = undefined;
  private unsubscribeSessionChanged?: () => void = undefined;
  private unsubscribeDownload?: () => void = undefined;

  aboutToAppear(): void {
    this.ensureIconSymbolsLoaded();
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
      this.RootNavigation()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet($$this.isSheetVisible, this.RootSheetBuilder, {
      height: '90%',
      dragBar: true,
      showClose: true,
      maskColor: '#33000000',
      backgroundColor: '#FFFFFF',
      preferType: SheetType.BOTTOM,
      enableOutsideInteractive: false,
      onDisappear: () => {
        this.activeSheet = RootSheet.NONE;
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
    } else if (name === AppRouteName.NOTIFICATIONS) {
      NavDestination() {
        NotificationPage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onBack: () => {
            this.popNavigation();
          },
          onOpenTopic: (topicId: number, slug: string | undefined, title: string) => {
            this.openTopicDetailById(topicId, slug, title);
          }
        })
      }
      .hideTitleBar(true)
    } else if (name === AppRouteName.PROFILE) {
      NavDestination() {
        ProfilePage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onLoginClick: () => {
            this.openLoginPage();
          }
        })
      }
      .hideTitleBar(true)
    } else {
      NavDestination() {
        Column() {
          Text('页面不存在')
            .fontSize(18)
            .fontColor('#111827')
          Button('返回')
            .margin({ top: 16 })
            .onClick(() => {
              this.popNavigation();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FFFFFF')
      }
      .hideTitleBar(true)
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
      onOpenNotifications: () => {
        this.navPathStack.pushPath(new NavPathInfo(AppRouteName.NOTIFICATIONS, buildNotificationsRouteParam('homeBell')));
      },
      onTopicClick: (topic: Topic) => {
        this.openTopicDetail(topic);
      },
      onOpenTopicById: (topicId: number) => {
        this.openTopicDetailById(topicId);
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
  private openTopicDetailById(topicId: number, slug?: string, title?: string): void {
    console.info(`${LOG_TAG} open topic detail topicId=${topicId} title=${title ? title : ''}`);
    this.navPathStack.pushPath(new NavPathInfo(
      AppRouteName.TOPIC_DETAIL,
      buildTopicDetailRouteParam(topicId, slug, title ? title : '')
    ));
  }

  // 统一的链接点击入口:经 LinkRouter 判断——站内帖子链接提取 topicId 跳原生详情页,
  // 其余(外站、站内非帖子页)一律打开通用 WebView。
  private handleOpenLink(url: string): void {
    const target: LinkTarget = LinkRouter.resolve(url);
    if (target.kind === LinkTargetKind.TOPIC && target.topicId !== undefined) {
      console.info(`${LOG_TAG} link -> native topic detail topicId=${target.topicId}`);
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
      console.info(`${LOG_TAG} toast failed: ${message}`);
    }
  }

  private openWebPage(url: string, title?: string): void {
    if (!url || url.length === 0) {
      return;
    }
    console.info(`${LOG_TAG} open web page host=${url.replace(/^https?:\/\/([^\/?#]+).*$/i, '$1')}`);
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
      console.info(`${LOG_TAG} icon symbols load skipped: no host context`);
      return;
    }

    const iconCount: number = ensureFaIconsLoaded(hostContext.resourceManager);
    const tagIconCount: number = ensureTagIconsLoaded(hostContext.resourceManager);
    console.info(`${LOG_TAG} icon assets loaded symbols=${iconCount} tagIcons=${tagIconCount}`);
  }

  private handleLoginSuccess(): void {
    // 会话变化会触发 host webview 重载,先关闭就绪门闩,确保随后并发的 fetch 排队到重载完成后。
    this.bridge.markHostReloading();
    SessionEventBus.notifySessionChanged();
    this.checkCurrentUser();
    this.closeLoginPage();
  }

  private handleAccountClick(): void {
    if (this.currentUser) {
      this.openProfilePage();
      return;
    }
    this.openLoginPage();
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
      this.currentUser = result.data;
      console.info(`${LOG_TAG} current user checked loggedIn=${this.currentUser !== undefined} username=${this.currentUser?.username ?? ''} hasAvatar=${this.currentUser?.avatarTemplate !== undefined}`);
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

    this.currentUser = undefined;
    this.notificationService.stop();
    console.info(`${LOG_TAG} current user check failed status=${result.statusCode} challenge=${result.challengeState}`);
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
    console.info(`${LOG_TAG} challenge required version=${event.version} source=${event.source} status=${event.statusCode} state=${event.challengeState}`);
    console.info(`${DIAG_TAG} stage=rootChallengeRequired version=${event.version} source=${event.source} status=${event.statusCode} state=${event.challengeState} activeSheet=${this.activeSheet} sheetVisible=${this.isSheetVisible}`);
    if (this.isSheetVisible) {
      return;
    }

    this.activeSheet = RootSheet.CHALLENGE;
    this.isSheetVisible = true;
    console.info(`${DIAG_TAG} stage=rootChallengeOpen version=${event.version}`);
  }

  private handleChallengeResolved(): void {
    console.info(`${LOG_TAG} challenge resolved`);
    console.info(`${DIAG_TAG} stage=rootChallengeResolved sheetVisible=${this.isSheetVisible}`);
    this.closeChallengePage();
    // 会话变化会触发 host webview 重载,先关闭就绪门闩,确保随后并发的 fetch 排队到重载完成后。
    this.bridge.markHostReloading();
    SessionEventBus.notifySessionChanged();
    this.checkCurrentUser();
  }
}
