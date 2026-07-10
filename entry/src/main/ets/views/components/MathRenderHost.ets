import webview from '@ohos.web.webview';
import { Log } from '../../services/logging/Log';
import { MathRenderService } from '../../services/content/MathRenderService';

const LOG_TAG: string = '[ArkDO][MathRenderHost]';

// 离屏公式引擎的 Web 载体:只加载本地 render.html(MathJax),1×1、透明、被上层完全遮挡。
// 与 ArkWebHost 无关——不导航站点、不随 session 重载、不在网络路径上。仅在有公式帖打开时挂载。
@Component
export struct MathRenderHost {
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
  }

  build() {
    Web({ src: $rawfile('mathjax/render.html'), controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .imageAccess(true)
      .javaScriptProxy(MathRenderService.getInstance().createProxy(this.controller))
      .onPageEnd(() => {
        Log.i(`${LOG_TAG} render page loaded`);
        MathRenderService.getInstance().attachController(this.controller);
      })
      // 离屏出图不需要可见/满视口(canvas.toDataURL 与布局可见性无关),1×1 透明即可,几乎不占合成。
      .width(1)
      .height(1)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
  }
}
