import { Topic } from '../../models/Topic';
import { User } from '../../models/User';
import { buildTopicDetailRouteParam, isTopicDetailRouteParam, TopicDetailRouteParam } from '../../navigation/AppRoutes';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { bumpTick, COMPOSER_OVERLAY_BACK_TICK_KEY, COMPOSER_OVERLAY_VISIBLE_KEY } from '../../common/constants/StorageKeys';
import { SearchOverlay } from './SearchOverlay';
import { ViewerImage } from './ImageViewer';
import { TopicDetailPage } from '../pages/TopicDetailPage';

const SEARCH_FLOW_TOPIC_DETAIL: string = 'searchTopicDetail';

@Component
export struct SearchFlow {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop isArkWebReady: boolean = false;
  @Prop currentUser: User = { id: 0, username: '' };
  @Prop @Watch('handleBackTickChanged') backTick: number = 0;
  @StorageProp(COMPOSER_OVERLAY_VISIBLE_KEY) private composerVisible: boolean = false;
  onClose: () => void = () => {};
  onOpenChallenge: () => void = () => {};
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onOpenUser: (user: User) => void = () => {};

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.navPathStack) {
      SearchOverlay({
        bridge: this.bridge,
        isArkWebReady: this.isArkWebReady,
        onClose: () => {
          this.closeSearchFlow();
        },
        onOpenTopic: (topic: Topic) => {
          this.openTopic(topic);
        }
      })
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.NavDestinationBuilder)
  }

  @Builder
  private NavDestinationBuilder(name: string, param: Object | undefined) {
    if (name === SEARCH_FLOW_TOPIC_DETAIL && isTopicDetailRouteParam(param)) {
      NavDestination() {
        TopicDetailPage({
          param: param as TopicDetailRouteParam,
          bridge: this.bridge,
          isArkWebReady: this.isArkWebReady,
          currentUser: this.currentUser,
          onBack: () => {
            this.popInternal();
          },
          onOpenChallenge: () => {
            this.onOpenChallenge();
          },
          onOpenImages: (images: ViewerImage[], startIndex: number) => {
            this.onOpenImages(images, startIndex);
          },
          onOpenLink: (url: string) => {
            this.leaveSearchAndOpenLink(url);
          },
          onOpenUser: (user: User) => {
            this.leaveSearchAndOpenUser(user);
          }
        })
      }
      .hideTitleBar(true)
      .onBackPressed(() => this.consumeTopicDetailBack())
      .backgroundColor($r('app.color.page_bg'))
    } else {
      NavDestination() {
        Column() {
          Text('页面不存在')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    }
  }

  private openTopic(topic: Topic): void {
    this.navPathStack.pushPath(new NavPathInfo(
      SEARCH_FLOW_TOPIC_DETAIL,
      buildTopicDetailRouteParam(topic.id, topic.slug, topic.title)
    ));
  }

  private handleBackTickChanged(): void {
    if (this.composerVisible) {
      bumpTick(COMPOSER_OVERLAY_BACK_TICK_KEY);
      return;
    }
    if (this.navPathStack.size() > 0) {
      this.popInternal();
      return;
    }
    // @Watch 正处于 AppStorage 状态刷新事务中，直接关闭会吞掉外层 opacity 动画。
    // 下一任务再进入与“取消”按钮相同的普通关闭路径，让淡出动画正常起播。
    setTimeout(() => {
      this.closeSearchFlow();
    }, 0);
  }

  private consumeTopicDetailBack(): boolean {
    if (this.composerVisible) {
      bumpTick(COMPOSER_OVERLAY_BACK_TICK_KEY);
      return true;
    }
    this.popInternal();
    return true;
  }

  private popInternal(): void {
    if (this.navPathStack.size() > 0) {
      this.navPathStack.pop();
    }
  }

  private closeSearchFlow(): void {
    this.onClose();
  }

  private leaveSearchAndOpenLink(url: string): void {
    this.onClose();
    this.onOpenLink(url);
  }

  private leaveSearchAndOpenUser(user: User): void {
    this.onClose();
    this.onOpenUser(user);
  }
}
