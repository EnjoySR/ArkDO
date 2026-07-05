import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { WebSessionManager } from '../../services/web/WebSessionManager';

const LOG_TAG: string = '[ArkDO][ArkWebHost]';

@Component
export struct ArkWebHost {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  onReady: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private hasNotifiedReady: boolean = false;
  private isControllerReady: boolean = false;
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('ArkWebHost');
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.reloadBaseUrl(version);
      });
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
  }

  build() {
    Web({ src: AppConstants.BASE_URL, controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .databaseAccess(true)
      .onlineImageAccess(true)
      .imageAccess(true)
      .mixedMode(MixedMode.All)
      .cacheMode(CacheMode.Default)
      .javaScriptProxy(this.bridge.createJavaScriptProxy(this.controller))
      .onControllerAttached(() => {
        WebSessionManager.applyUserAgent(this.controller, 'ArkWebHost');
      })
      .onPageEnd(() => {
        this.isControllerReady = true;
        WebSessionManager.saveCookies('ArkWebHost');
        this.bridge.attachController(this.controller);
        this.bridge.markHostReady();
        this.syncSessionVersion();
        if (!this.hasNotifiedReady) {
          this.hasNotifiedReady = true;
          this.onReady();
        }
      })
      .width(1)
      .height(1)
      .opacity(0.01)
  }

  private reloadBaseUrl(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    if (!this.isControllerReady) {
      console.info(`${LOG_TAG} session changed before controller ready version=${version}`);
      return;
    }

    try {
      this.handledSessionVersion = version;
      console.info(`${LOG_TAG} reload base url for session version=${version}`);
      // 重载开始前先关门:注入式 fetch 会排队等到重载后的 onPageEnd 再执行,避免落在被销毁的文档上。
      this.bridge.markHostReloading();
      this.controller.loadUrl(AppConstants.BASE_URL);
    } catch (error) {
      // loadUrl 抛异常时不会有后续 onPageEnd,需立即放行等待者以免请求悬住。
      this.bridge.markHostReady();
      console.info(`${LOG_TAG} reload base url failed version=${version} error=${JSON.stringify(error)}`);
    }
  }

  private syncSessionVersion(): void {
    this.reloadBaseUrl(SessionEventBus.getCurrentVersion());
  }
}
