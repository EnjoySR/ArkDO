import { AppRouteName, buildProfileRouteParam, buildTopicDetailRouteParam, isTopicDetailRouteParam, TopicDetailRouteParam } from '../../navigation/AppRoutes';
import { Topic } from '../../models/Topic';
import { User } from '../../models/User';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../../services/challenge/ChallengeEventBus';
import { AuthService } from '../../services/auth/AuthService';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { ArkWebHost } from '../components/ArkWebHost';
import { ensureFaIconsLoaded } from '../components/FaIcon';
import { ensureTagIconsLoaded } from '../components/TagIconRegistry';
import { CfChallengePage } from './CfChallengePage';
import { HomePage } from './HomePage';
import { LoginPage } from './LoginPage';
import { ProfilePage } from './ProfilePage';
import { TopicDetailPage } from './TopicDetailPage';

const LOG_TAG: string = '[ArkDO][Root]';
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';

@Component
export struct RootTabPage {
  @State private isLoginPageVisible: boolean = false;
  @State private isChallengePageVisible: boolean = false;
  @State private isArkWebReady: boolean = false;
  @State private currentUser?: User = undefined;
  @State private isCheckingSession: boolean = false;
  @State private hasCheckedSession: boolean = false;
  private bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private navPathStack: NavPathStack = new NavPathStack();
  private sessionCheckSequence: number = 0;
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private handledChallengeVersion: number = ChallengeEventBus.getCurrentVersion();
  private unsubscribeChallengeRequired?: () => void = undefined;
  private unsubscribeSessionChanged?: () => void = undefined;

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
  }

  aboutToDisappear(): void {
    if (this.unsubscribeChallengeRequired) {
      this.unsubscribeChallengeRequired();
      this.unsubscribeChallengeRequired = undefined;
    }
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
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
    .bindSheet($$this.isLoginPageVisible, this.LoginSheetBuilder, {
      height: '90%',
      dragBar: true,
      showClose: true,
      maskColor: '#33000000',
      backgroundColor: '#FFFFFF',
      preferType: SheetType.BOTTOM,
      enableOutsideInteractive: false
    })
    .bindSheet($$this.isChallengePageVisible, this.ChallengeSheetBuilder, {
      height: '90%',
      dragBar: true,
      showClose: true,
      maskColor: '#33000000',
      backgroundColor: '#FFFFFF',
      preferType: SheetType.BOTTOM,
      enableOutsideInteractive: false
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
  private LoginSheetBuilder() {
    LoginPage({
      onClose: () => {
        this.closeLoginPage();
      },
      onLoginSuccess: () => {
        this.handleLoginSuccess();
      }
    })
  }

  @Builder
  private ChallengeSheetBuilder() {
    CfChallengePage({
      bridge: this.bridge,
      onClose: () => {
        this.closeChallengePage();
      },
      onChallengeResolved: () => {
        this.handleChallengeResolved();
      }
    })
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
      onTopicClick: (topic: Topic) => {
        this.openTopicDetail(topic);
      }
    })
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  private openLoginPage(): void {
    this.isLoginPageVisible = true;
  }

  private closeLoginPage(): void {
    this.isLoginPageVisible = false;
  }

  private closeChallengePage(): void {
    this.isChallengePageVisible = false;
  }

  private openTopicDetail(topic: Topic): void {
    console.info(`${LOG_TAG} open topic detail topicId=${topic.id} title=${topic.title}`);
    this.navPathStack.pushPath(new NavPathInfo(
      AppRouteName.TOPIC_DETAIL,
      buildTopicDetailRouteParam(topic.id, topic.slug, topic.title)
    ));
  }

  private popNavigation(): void {
    this.navPathStack.pop();
  }

  private handleArkWebReady(): void {
    this.isArkWebReady = true;
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
      return;
    }

    this.currentUser = undefined;
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
    console.info(`${DIAG_TAG} stage=rootChallengeRequired version=${event.version} source=${event.source} status=${event.statusCode} state=${event.challengeState} challengeVisible=${this.isChallengePageVisible} loginVisible=${this.isLoginPageVisible}`);
    if (this.isChallengePageVisible || this.isLoginPageVisible) {
      return;
    }

    this.isChallengePageVisible = true;
    console.info(`${DIAG_TAG} stage=rootChallengeOpen version=${event.version}`);
  }

  private handleChallengeResolved(): void {
    console.info(`${LOG_TAG} challenge resolved`);
    console.info(`${DIAG_TAG} stage=rootChallengeResolved challengeVisible=${this.isChallengePageVisible}`);
    this.closeChallengePage();
    SessionEventBus.notifySessionChanged();
    this.checkCurrentUser();
  }
}
