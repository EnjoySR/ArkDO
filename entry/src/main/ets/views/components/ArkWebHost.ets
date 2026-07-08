import { Log } from '../../services/logging/Log';
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
      // 满视口 + 近透明:host 在 Stack 底层被上层不透明 UI 完全遮挡,视觉无变化;但给 CF 挑战
      // JS 一个真实浏览器视口(1×1 会被判机器人),非交互挑战才可能在此静默跑通并种下 cf_clearance。
      .width('100%')
      .height('100%')
      .opacity(0.01)
  }

  private reloadBaseUrl(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    if (!this.isControllerReady) {
      Log.i(`${LOG_TAG} session changed before controller ready version=${version}`);
      return;
    }

    try {
      this.handledSessionVersion = version;
      Log.i(`${LOG_TAG} reload base url for session version=${version}`);
      // 重载开始前先关门:注入式 fetch 会排队等到重载后的 onPageEnd 再执行,避免落在被销毁的文档上。
      this.bridge.markHostReloading();
      this.controller.loadUrl(AppConstants.BASE_URL);
    } catch (error) {
      // loadUrl 抛异常时不会有后续 onPageEnd,需立即放行等待者以免请求悬住。
      this.bridge.markHostReady();
      Log.i(`${LOG_TAG} reload base url failed version=${version} error=${JSON.stringify(error)}`);
    }
  }

  private syncSessionVersion(): void {
    this.reloadBaseUrl(SessionEventBus.getCurrentVersion());
  }
}
