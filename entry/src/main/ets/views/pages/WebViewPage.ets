import { Log } from '../../services/logging/Log';
import webview from '@ohos.web.webview';
import { image } from '@kit.ImageKit';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { WebSessionManager } from '../../services/web/WebSessionManager';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { showToast as promptToast } from '../../common/utils/Toast';

const LOG_TAG: string = '[ArkDO][WebViewPage]';

// 通用 WebView 页:承载点击链接后打开的任意网页(外站或站内非帖子页)。
// 复用 App 全局 CookieManager(与 host webview 同源),站内链接可带登录态。
@Component
export struct WebViewPage {
  // 窗口常驻全屏布局:根列自行避让状态栏(padding 在带背景的根列上,背景填满状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  url: string = '';
  pageTitle: string = '';
  onBack: () => void = () => {};
  // 引擎解析出页面 favicon 时回调。本页不关心它有什么用——是否留存由宿主决定
  // (「我的站点」拿去缓存成站点图标,随手点开的帖子外链则直接丢弃)。
  onFaviconReceived: (favicon: image.PixelMap) => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private displayTitle: string = '';
  @State private progress: number = 0;
  @State private isLoading: boolean = true;
  // 主框架加载失败:盖一层错误页,否则用户面对的是一片白屏,只会以为 App 坏了。
  // 对「我的站点」尤其要紧——DoH 只治 DNS 污染,遇上 IP 封锁/TLS 阻断照样打不开。
  @State private hasError: boolean = false;
  @State private errorDetail: string = '';

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
          .color($r('app.color.brand'))
          .backgroundColor($r('app.color.border'))
          .width('100%')
          .height(2)
      }

      Stack() {
        Web({ src: this.url, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .databaseAccess(true)
          .onlineImageAccess(true)
          .imageAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.Default)
          .width('100%')
          .height('100%')
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
          // 引擎自己下载并解码的 favicon:走 ArkWeb 网络栈(吃 DoH)且不受 CORS 限制,
          // 是被污染站点唯一能拿到图标的路径。同一页面可能回调多次(多个 <link rel=icon>),后到覆盖先到。
          .onFaviconReceived((event: OnFaviconReceivedEvent) => {
            if (event && event.favicon) {
              this.onFaviconReceived(event.favicon);
            }
          })
          // 新一轮导航开始:清掉上一次的错误页(重试成功时靠它把错误页揭掉)。
          .onPageBegin(() => {
            this.hasError = false;
            this.errorDetail = '';
          })
          .onPageEnd(() => {
            this.isLoading = false;
            WebSessionManager.saveCookies('WebViewPage');
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            this.handleErrorReceive(event);
          })

        if (this.hasError) {
          this.ErrorView()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.sysTopInset })
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private TitleBar() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([$r('app.color.text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.surface_muted'))
      .onClick(() => {
        this.handleBack();
      })

      Column() {
        Text(this.displayTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.hostOf(this.url))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 1 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 刷新:OAuth 回跳卡住、页面半死时的第一手段,故给独立按钮而非藏进菜单。
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(19)
          .fontColor([$r('app.color.text_secondary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.reload();
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(19)
          .fontColor([$r('app.color.text_secondary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .bindMenu([
        {
          value: '复制链接',
          action: () => {
            this.copyLink();
          }
        },
        {
          value: '用浏览器打开',
          action: () => {
            this.openInBrowser();
          }
        }
      ])
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
    .border({ width: { bottom: 0.5 }, color: $r('app.color.border') })
  }

  // 加载失败盖在 Web 之上。除了报错,还要替用户回答"为什么打不开、现在能干什么":
  // DoH 治不了封锁,故给「用浏览器打开」当逃生口(有代理的浏览器还有机会)。
  @Builder
  private ErrorView() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(44)
        .fontColor([$r('app.color.text_faint')])

      Text('无法打开此页面')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 14 })

      Text(this.hostOf(this.currentUrl()))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })

      Text('DoH 只能绕开域名污染。若站点被封锁或需要代理,可以试试用系统浏览器打开。')
        .fontSize(12)
        .fontColor($r('app.color.text_faint'))
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })
        .padding({ left: 32, right: 32 })

      Row({ space: 12 }) {
        Button('重试')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.ld_accent'))
          .height(40)
          .padding({ left: 28, right: 28 })
          .borderRadius(20)
          .onClick(() => {
            this.reload();
          })

        Button('用浏览器打开')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .height(40)
          .padding({ left: 20, right: 20 })
          .borderRadius(20)
          .onClick(() => {
            this.openInBrowser();
          })
      }
      .margin({ top: 22 })

      if (this.errorDetail.length > 0) {
        Text(this.errorDetail)
          .fontSize(11)
          .fontColor($r('app.color.text_faint'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 18 })
          .padding({ left: 32, right: 32 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
  }

  // 只认主框架错误:子资源(图片、统计脚本、第三方 CDN)失败在真实网页里太常见,
  // 拿它整页报错会把本来能用的页面误伤成错误页。
  private handleErrorReceive(event: OnErrorReceiveEvent): void {
    this.isLoading = false;
    if (!event || !event.request || !event.request.isMainFrame()) {
      return;
    }
    this.errorDetail = event.error ? event.error.getErrorInfo() : '';
    this.hasError = true;
    Log.i(`${LOG_TAG} main frame error host=${this.hostOf(this.currentUrl())} info=${this.errorDetail}`);
  }

  private reload(): void {
    this.hasError = false;
    this.errorDetail = '';
    this.isLoading = true;
    this.progress = 0;
    try {
      this.controller.refresh();
    } catch (error) {
      // 首次加载就失败时页面无历史可刷,退回按原 url 重新载入。
      Log.i(`${LOG_TAG} refresh failed, fallback to loadUrl: ${JSON.stringify(error)}`);
      try {
        this.controller.loadUrl(this.url);
      } catch (err) {
        Log.i(`${LOG_TAG} loadUrl failed: ${JSON.stringify(err)}`);
      }
    }
  }

  private copyLink(): void {
    const link: string = this.currentUrl();
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, link);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.showToast('链接已复制');
      }).catch((err: BusinessError) => {
        Log.i(`${LOG_TAG} copy link failed code=${err.code}`);
        this.showToast('复制失败');
      });
    } catch (error) {
      Log.i(`${LOG_TAG} copy link threw: ${JSON.stringify(error)}`);
      this.showToast('复制失败');
    }
  }

  // 逃生口:DoH 治不了的封锁交给系统浏览器(用户那边可能有代理)。
  private openInBrowser(): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: this.currentUrl()
      };
      (getContext(this) as common.UIAbilityContext).startAbility(want).catch((err: BusinessError) => {
        Log.i(`${LOG_TAG} open in browser failed code=${err.code} msg=${err.message}`);
        this.showToast('没有可用的浏览器');
      });
    } catch (error) {
      Log.i(`${LOG_TAG} open in browser threw: ${JSON.stringify(error)}`);
      this.showToast('没有可用的浏览器');
    }
  }

  // 当前地址:页面可能已经跳转过(OAuth 回跳尤其如此),复制/外开要以引擎的实际地址为准。
  private currentUrl(): string {
    try {
      const current: string = this.controller.getUrl();
      return current && current.length > 0 ? current : this.url;
    } catch (error) {
      return this.url;
    }
  }

  private showToast(message: string): void {
    promptToast(this.getUIContext(), message);
  }

  // 系统/侧滑返回优先在网页内回退一级;无历史时才退出本页。
  private handleBack(): void {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return;
      }
    } catch (error) {
      Log.i(`${LOG_TAG} accessBackward failed: ${JSON.stringify(error)}`);
    }
    this.onBack();
  }

  private hostOf(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/?#]+)/i);
    return match ? match[1] : url;
  }
}
