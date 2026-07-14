import { Log } from '../../services/logging/Log';
import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { WebSessionManager } from '../../services/web/WebSessionManager';

const LOG_TAG: string = '[ArkDO][ArkWebHost]';
// 冷启动看门狗:宿主首屏在此时长内仍未就绪(onErrorReceive 也没抓到,例如慢速僵死连接),
// 兜底判失败并解锁 UI,让用户不必干等 DNS/连接超时(可长达 30s+)就能进设置开 DoH/代理自救。
const BOOT_WATCHDOG_MS: number = 12000;

@Component
export struct ArkWebHost {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  onReady: () => void = () => {};
  // 宿主首屏加载失败(主框架网络错误/看门狗超时)时回调:通知外层解锁 UI 进入降级可导航态。
  onLoadFailed: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private hasNotifiedReady: boolean = false;
  private isControllerReady: boolean = false;
  // 控制器是否已附着到 Web 组件。附着后即可安全 loadUrl 重载,无需等首屏加载完成——
  // 这是让"首屏失败后开 DoH 仍能重载"成立的关键(旧逻辑误等 isControllerReady 而永不重载)。
  private isControllerAttached: boolean = false;
  // 失败只上报一次,避免主框架多次 errorReceive / 看门狗叠加重复解锁。
  private hasReportedFailure: boolean = false;
  private bootWatchdogTimer: number = -1;
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;

  aboutToAppear(): void {
    // 计时锚点③:宿主 webview 开始初始化并加载 BASE_URL。到 onPageEnd 就绪之间即为桥初始化耗时。
    Log.i(`${LOG_TAG} stage=hostInitStart ts=${Date.now()}`);
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('ArkWebHost');
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.reloadBaseUrl(version);
      });
    }
    this.startBootWatchdog();
  }

  aboutToDisappear(): void {
    this.clearBootWatchdog();
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
  }

  build() {
    Web({ src: AppConstants.HOST_BOOTSTRAP_URL, controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .databaseAccess(true)
      .onlineImageAccess(true)
      .imageAccess(true)
      .mixedMode(MixedMode.All)
      .cacheMode(CacheMode.Default)
      .javaScriptProxy(this.bridge.createJavaScriptProxy(this.controller))
      .onControllerAttached(() => {
        this.isControllerAttached = true;
        WebSessionManager.applyUserAgent(this.controller, 'ArkWebHost');
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        // 主框架网络错误(ERR_NAME_NOT_RESOLVED / ERR_CONNECTION_REFUSED / ERR_TIMED_OUT 等):
        // DoH 关 + 无代理时 DNS 被污染/连接被拒,首屏根本到不了。仅在首屏尚未就绪时判失败,
        // 立即解锁 UI(而非干等超时),让用户进设置开 DoH 自救。子资源错误与就绪后错误一律忽略。
        if (this.hasNotifiedReady) {
          return;
        }
        const isMainFrame: boolean = event.request.isMainFrame();
        if (!isMainFrame) {
          return;
        }
        Log.i(`${LOG_TAG} main frame error code=${event.error.getErrorCode()} info=${event.error.getErrorInfo()}`);
        this.reportLoadFailed('errorReceive');
      })
      .onPageBegin(() => {
        // 计时锚点③.5:导航已提交(DNS+CF+首字节完成,开始收正文)。切分建连阶段与页面渲染阶段。
        if (!this.hasNotifiedReady) {
          Log.i(`${LOG_TAG} stage=hostPageBegin ts=${Date.now()}`);
        }
      })
      .onPageEnd(() => {
        // 计时锚点④:宿主 webview 首页加载完成,fetch 桥就绪(首次才通知 onReady)。
        if (!this.hasNotifiedReady) {
          Log.i(`${LOG_TAG} stage=hostPageEndReady ts=${Date.now()}`);
        }
        this.isControllerReady = true;
        this.clearBootWatchdog();
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

    // 只要控制器已附着即可 loadUrl 重载,不等首屏加载完成:否则首屏失败(不可达)后
    // isControllerReady 永为 false,用户开 DoH 触发的重载会被这里挡掉 → 帖子/登录态死活刷不回来,
    // 只能重启。改判 isControllerAttached 后,开 DoH 能真正重导航,新 DNS 立即生效。
    if (!this.isControllerAttached) {
      Log.i(`${LOG_TAG} session changed before controller attached version=${version}`);
      return;
    }

    try {
      this.handledSessionVersion = version;
      Log.i(`${LOG_TAG} reload base url for session version=${version}`);
      // 重载前重开看门狗:上次首屏若已失败,这次(通常是开了 DoH)得重新盯着能否就绪。
      if (!this.hasNotifiedReady) {
        this.startBootWatchdog();
      }
      // 重载开始前先关门:注入式 fetch 会排队等到重载后的 onPageEnd 再执行,避免落在被销毁的文档上。
      this.bridge.markHostReloading();
      this.controller.loadUrl(AppConstants.HOST_BOOTSTRAP_URL);
    } catch (error) {
      // loadUrl 抛异常时不会有后续 onPageEnd,需立即放行等待者以免请求悬住。
      this.bridge.markHostReady();
      Log.i(`${LOG_TAG} reload base url failed version=${version} error=${JSON.stringify(error)}`);
    }
  }

  private syncSessionVersion(): void {
    this.reloadBaseUrl(SessionEventBus.getCurrentVersion());
  }

  // 首屏就绪前若主框架报错或看门狗超时,判定加载失败:放行排队的注入 fetch(令其快速失败暴露
  // "加载失败/重试"),并回调外层解锁 UI。首屏一旦就绪(hasNotifiedReady)便不再上报。
  private reportLoadFailed(reason: string): void {
    if (this.hasNotifiedReady || this.hasReportedFailure) {
      return;
    }
    this.hasReportedFailure = true;
    this.clearBootWatchdog();
    Log.i(`${LOG_TAG} stage=hostLoadFailed reason=${reason} ts=${Date.now()}`);
    this.bridge.markHostReady();
    this.onLoadFailed();
  }

  private startBootWatchdog(): void {
    this.clearBootWatchdog();
    // 允许下一轮(如开 DoH 后的重载)重新判定,故重开看门狗时清掉失败一次性闸。
    this.hasReportedFailure = false;
    this.bootWatchdogTimer = setTimeout(() => {
      this.bootWatchdogTimer = -1;
      this.reportLoadFailed('watchdog');
    }, BOOT_WATCHDOG_MS);
  }

  private clearBootWatchdog(): void {
    if (this.bootWatchdogTimer >= 0) {
      clearTimeout(this.bootWatchdogTimer);
      this.bootWatchdogTimer = -1;
    }
  }
}
