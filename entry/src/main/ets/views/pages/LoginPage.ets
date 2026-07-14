import { Log } from '../../services/logging/Log';
import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { CookiePresenceSnapshot } from '../../services/web/WebSessionManager';
import { WebSessionManager } from '../../services/web/WebSessionManager';

const LOG_TAG: string = '[ArkDO][Login]';
const CHALLENGE_POLL_INTERVAL_MS: number = 1000;
const MAX_CHALLENGE_POLL_COUNT: number = 90;
// 登录态轮询:Discourse SPA 登录成功走客户端路由跳转(pushState),不触发 onPageEnd,
// 单靠 URL 判定会漏检。改盯登录令牌 cookie `_t`(登出时无、登录后下发)兜住这条路径。
const LOGIN_POLL_INTERVAL_MS: number = 800;
const AUTH_COOKIE_NAME: string = '_t';

@Component
export struct LoginPage {
  onClose: () => void = () => {};
  onLoginSuccess: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private challengePollTimer: number = -1;
  private challengePollCount: number = 0;
  private hasReloadedAfterChallenge: boolean = false;
  // 登录态轮询:检测 `_t` cookie 从"无"变"有"即判定登录成功;单次守卫防与 onPageEnd 路径重复触发。
  private loginPollTimer: number = -1;
  private initialAuthCookiePresent: boolean = false;
  private hasSignaledLoginSuccess: boolean = false;

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('LoginPage');
    // 记录进入登录页时的登录令牌基线(常态为无),只在其后新出现时才判成功,避免误触发。
    this.initialAuthCookiePresent = WebSessionManager.hasCookie(AUTH_COOKIE_NAME);
    this.startLoginCookiePolling();
  }

  aboutToDisappear(): void {
    this.stopChallengeCookiePolling();
    this.stopLoginCookiePolling();
  }

  build() {
    Column() {
      Row() {
        Blank()
        Text('登录')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.page_bg'))
      .border({
        width: { bottom: 1 },
        color: $r('app.color.border')
      })

      Web({ src: AppConstants.LOGIN_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .cacheMode(CacheMode.Default)
        .onPageBegin((event: OnPageBeginEvent) => {
          Log.i(`${LOG_TAG} page begin url=${event.url}`);
        })
        .onPageEnd((event: OnPageEndEvent) => {
          Log.i(`${LOG_TAG} page end url=${event.url}`);
          WebSessionManager.saveCookies('LoginPage');
          this.logCfClearanceSnapshot('pageEnd');
          if (this.isLikelyLoggedInUrl(event.url)) {
            this.signalLoginSuccess('pageEnd', event.url);
          }
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          Log.i(`${LOG_TAG} load error url=${this.safeRequestUrl(event.request)} code=${this.safeErrorCode(event.error)} info=${this.safeErrorInfo(event.error)}`);
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          const url: string = this.safeRequestUrl(event.request);
          const statusCode: number = this.safeResponseCode(event.response);
          Log.i(`${LOG_TAG} http error url=${url} status=${statusCode} reason=${this.safeReasonMessage(event.response)}`);
          if (this.isChallengeRelatedHttpError(url, statusCode)) {
            this.startChallengeCookiePolling();
          }
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  private isChallengeRelatedHttpError(url: string, statusCode: number): boolean {
    if (statusCode !== 401 && statusCode !== 403 && statusCode !== 429) {
      return false;
    }
    return url.startsWith(AppConstants.LOGIN_URL) || url.indexOf('challenges.cloudflare.com') >= 0;
  }

  private isLikelyLoggedInUrl(url: string): boolean {
    if (!url.startsWith(AppConstants.BASE_URL)) {
      return false;
    }
    if (url.startsWith(AppConstants.LOGIN_URL) || url.startsWith(AppConstants.CHALLENGE_URL)) {
      return false;
    }
    return true;
  }

  // 登录态 cookie 轮询:登录页开着期间每 800ms 查一次 `_t`;新出现即判登录成功。
  // Discourse SPA 登录成功不必然触发 onPageEnd,这是补齐检测的主路径。页面关闭/成功即停。
  private startLoginCookiePolling(): void {
    if (this.loginPollTimer >= 0) {
      return;
    }
    this.loginPollTimer = setInterval(() => {
      const hasAuthCookie: boolean = WebSessionManager.hasCookie(AUTH_COOKIE_NAME);
      if (hasAuthCookie && !this.initialAuthCookiePresent) {
        this.signalLoginSuccess('cookiePoll', '');
      }
    }, LOGIN_POLL_INTERVAL_MS);
  }

  private stopLoginCookiePolling(): void {
    if (this.loginPollTimer < 0) {
      return;
    }
    clearInterval(this.loginPollTimer);
    this.loginPollTimer = -1;
  }

  // 登录成功统一出口:单次守卫,停掉两路轮询、落盘 cookie,再通知上层(关登录页 + 刷新会话)。
  private signalLoginSuccess(source: string, url: string): void {
    if (this.hasSignaledLoginSuccess) {
      return;
    }
    this.hasSignaledLoginSuccess = true;
    Log.i(`${LOG_TAG} login success signaled source=${source} url=${url}`);
    this.stopLoginCookiePolling();
    this.stopChallengeCookiePolling();
    WebSessionManager.saveCookies('LoginPage');
    this.onLoginSuccess();
  }

  private startChallengeCookiePolling(): void {
    if (this.challengePollTimer >= 0 || this.hasReloadedAfterChallenge) {
      return;
    }

    this.challengePollCount = 0;
    Log.i(`${LOG_TAG} cf_clearance polling start`);
    this.challengePollTimer = setInterval(() => {
      this.challengePollCount++;
      const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
      if (snapshot.hasCookie) {
        Log.i(`${LOG_TAG} cf_clearance detected, reload login`);
        WebSessionManager.saveCookies('LoginPage');
        this.stopChallengeCookiePolling();
        this.reloadLoginAfterChallenge();
        return;
      }

      if (this.challengePollCount % 5 === 0) {
        Log.i(`${LOG_TAG} cf_clearance pending attempt=${this.challengePollCount}/${MAX_CHALLENGE_POLL_COUNT} cookieHeaderLength=${snapshot.headerLength}`);
      }

      if (this.challengePollCount >= MAX_CHALLENGE_POLL_COUNT) {
        Log.i(`${LOG_TAG} cf_clearance polling timeout`);
        this.stopChallengeCookiePolling();
      }
    }, CHALLENGE_POLL_INTERVAL_MS);
  }

  private stopChallengeCookiePolling(): void {
    if (this.challengePollTimer < 0) {
      return;
    }
    clearInterval(this.challengePollTimer);
    this.challengePollTimer = -1;
  }

  private reloadLoginAfterChallenge(): void {
    if (this.hasReloadedAfterChallenge) {
      return;
    }

    this.hasReloadedAfterChallenge = true;
    try {
      this.controller.loadUrl(AppConstants.LOGIN_URL);
    } catch (error) {
      Log.i(`${LOG_TAG} reload login failed error=${JSON.stringify(error)}`);
    }
  }

  private logCfClearanceSnapshot(stage: string): void {
    const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
    Log.i(`${LOG_TAG} cf_clearance snapshot stage=${stage} exists=${snapshot.hasCookie} cookieHeaderLength=${snapshot.headerLength}`);
  }

  private safeRequestUrl(request: WebResourceRequest): string {
    try {
      return request.getRequestUrl();
    } catch (error) {
      return '';
    }
  }

  private safeErrorCode(error: WebResourceError): number {
    try {
      return error.getErrorCode();
    } catch (err) {
      return 0;
    }
  }

  private safeErrorInfo(error: WebResourceError): string {
    try {
      return error.getErrorInfo();
    } catch (err) {
      return '';
    }
  }

  private safeResponseCode(response: WebResourceResponse): number {
    try {
      return response.getResponseCode();
    } catch (error) {
      return 0;
    }
  }

  private safeReasonMessage(response: WebResourceResponse): string {
    try {
      return response.getReasonMessage();
    } catch (error) {
      return '';
    }
  }
}
