import { CommonModifier, SymbolGlyphModifier } from '@ohos.arkui.modifier';
import { AppRouteName, buildTopicDetailRouteParam, isTopicDetailRouteParam, TopicDetailRouteParam } from '../../navigation/AppRoutes';
import { Topic } from '../../models/Topic';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../../services/challenge/ChallengeEventBus';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
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

class FloatingTabBarModifier extends CommonModifier {
  applyNormalAttribute(instance: CommonAttribute): void {
    instance
      .margin({ bottom: 18 })
      .borderRadius(34)
      .shadow({
        radius: 24,
        color: '#24000000',
        offsetY: 8
      })
  }
}

enum RootTab {
  HOME = 0,
  PROFILE = 1
}

@Component
export struct RootTabPage {
  @State private selectedTab: number = RootTab.HOME;
  @State private isLoginPageVisible: boolean = false;
  @State private isChallengePageVisible: boolean = false;
  @State private isArkWebReady: boolean = false;
  private bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  private navPathStack: NavPathStack = new NavPathStack();
  private handledChallengeVersion: number = ChallengeEventBus.getCurrentVersion();
  private unsubscribeChallengeRequired?: () => void = undefined;

  aboutToAppear(): void {
    this.ensureIconSymbolsLoaded();
    if (!this.unsubscribeChallengeRequired) {
      this.unsubscribeChallengeRequired = ChallengeEventBus.subscribe((event: ChallengeRequiredEvent) => {
        this.handleChallengeRequired(event);
      });
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribeChallengeRequired) {
      this.unsubscribeChallengeRequired();
      this.unsubscribeChallengeRequired = undefined;
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
      this.RootTabs()
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
  private RootTabs() {
    Tabs({
      barPosition: BarPosition.End,
      index: this.selectedTab,
      barModifier: new FloatingTabBarModifier()
    }) {
      TabContent() {
        HomePage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onTopicClick: (topic: Topic) => {
            this.openTopicDetail(topic);
          }
        })
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.buildBottomTabBar(
        $r('sys.symbol.house'),
        $r('sys.symbol.house_fill'),
        '首页'
      ))

      TabContent() {
        ProfilePage({
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          onLoginClick: () => {
            this.openLoginPage();
          }
        })
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .tabBar(this.buildBottomTabBar(
        $r('sys.symbol.person'),
        $r('sys.symbol.person_fill'),
        '我的'
      ))
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .barHeight(68, true)
    .barWidth('76%')
    .barMode(BarMode.Fixed)
    .barOverlap(true)
    .barBackgroundColor('#E6FFFFFF')
    .barBackgroundBlurStyle(BlurStyle.Regular)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onChange((index: number) => {
      this.selectTab(index);
    })
  }

  private selectTab(tab: number): void {
    this.selectedTab = tab;
  }

  private buildTabSymbol(icon: Resource, color: ResourceColor): SymbolGlyphModifier {
    const modifier: SymbolGlyphModifier = new SymbolGlyphModifier(icon);
    modifier.fontSize(24);
    modifier.fontColor([color]);
    modifier.renderingStrategy(SymbolRenderingStrategy.SINGLE);
    return modifier;
  }

  private buildBottomTabBar(normalIcon: Resource, selectedIcon: Resource, label: string): BottomTabBarStyle {
    return BottomTabBarStyle
      .of({
        normal: this.buildTabSymbol(normalIcon, '#99182431'),
        selected: this.buildTabSymbol(selectedIcon, '#FF2563EB')
      }, label)
      .labelStyle({
        selectedColor: '#2563EB',
        unselectedColor: '#4B5563',
        font: {
          size: 11,
          weight: FontWeight.Medium
        }
      })
      .padding({ top: 6, bottom: 5, left: 8, right: 8 });
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
    this.closeLoginPage();
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
  }
}
