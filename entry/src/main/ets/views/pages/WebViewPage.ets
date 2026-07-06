import webview from '@ohos.web.webview';
import { WebSessionManager } from '../../services/web/WebSessionManager';

const LOG_TAG: string = '[ArkDO][WebViewPage]';

// 通用 WebView 页:承载点击链接后打开的任意网页(外站或站内非帖子页)。
// 复用 App 全局 CookieManager(与 host webview 同源),站内链接可带登录态。
@Component
export struct WebViewPage {
  url: string = '';
  pageTitle: string = '';
  onBack: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private displayTitle: string = '';
  @State private progress: number = 0;
  @State private isLoading: boolean = true;

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('WebViewPage');
    this.displayTitle = this.pageTitle.length > 0 ? this.pageTitle : this.hostOf(this.url);
  }

  build() {
    Column() {
      this.TitleBar()

      if (this.isLoading && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .color('#2563EB')
          .backgroundColor('#E5E7EB')
          .width('100%')
          .height(2)
      }

      Web({ src: this.url, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .onControllerAttached(() => {
          WebSessionManager.applyUserAgent(this.controller, 'WebViewPage');
        })
        .onTitleReceive((event: OnTitleReceiveEvent) => {
          // 仅当外部未指定标题时,用网页自身 title 兜底(避免覆盖 onebox 卡片带来的准确标题)。
          if (this.pageTitle.length === 0 && event && event.title && event.title.length > 0) {
            this.displayTitle = event.title;
          }
        })
        .onProgressChange((event: OnProgressChangeEvent) => {
          this.progress = event.newProgress;
        })
        .onPageEnd(() => {
          this.isLoading = false;
          WebSessionManager.saveCookies('WebViewPage');
        })
        .onErrorReceive(() => {
          this.isLoading = false;
        })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private TitleBar() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(26)
          .fontColor([Color.Black])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(38)
      .height(38)
      .backgroundColor('#E6E8E9')
      .onClick(() => {
        this.handleBack();
      })

      Column() {
        Text(this.displayTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.hostOf(this.url))
          .fontSize(12)
          .fontColor('#9CA3AF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 1 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#FFFFFF')
    .border({ width: { bottom: 0.5 }, color: '#E5E7EB' })
  }

  // 系统/侧滑返回优先在网页内回退一级;无历史时才退出本页。
  private handleBack(): void {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return;
      }
    } catch (error) {
      console.info(`${LOG_TAG} accessBackward failed: ${JSON.stringify(error)}`);
    }
    this.onBack();
  }

  private hostOf(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/?#]+)/i);
    return match ? match[1] : url;
  }
}
