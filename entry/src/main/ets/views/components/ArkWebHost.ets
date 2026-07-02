import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';

@Component
export struct ArkWebHost {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  onReady: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private hasNotifiedReady: boolean = false;

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
  }

  build() {
    Web({ src: AppConstants.BASE_URL, controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .javaScriptProxy(this.bridge.createJavaScriptProxy(this.controller))
      .onPageEnd(() => {
        this.bridge.attachController(this.controller);
        if (!this.hasNotifiedReady) {
          this.hasNotifiedReady = true;
          this.onReady();
        }
      })
      .width(1)
      .height(1)
      .opacity(0.01)
  }
}
