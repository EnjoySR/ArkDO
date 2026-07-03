import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { CookiePresenceSnapshot } from '../../services/web/WebSessionManager';
import { WebSessionManager } from '../../services/web/WebSessionManager';

const LOG_TAG: string = '[ArkDO][Login]';
const CHALLENGE_POLL_INTERVAL_MS: number = 1000;
const MAX_CHALLENGE_POLL_COUNT: number = 90;

@Component
export struct LoginPage {
  onClose: () => void = () => {};
  onLoginSuccess: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private challengePollTimer: number = -1;
  private challengePollCount: number = 0;
  private hasReloadedAfterChallenge: boolean = false;

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('LoginPage');
  }

  aboutToDisappear(): void {
    this.stopChallengeCookiePolling();
  }

  build() {
    Column() {
      Row() {
        Blank()
        Text('登录')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
        Blank()
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')
      .border({
        width: { bottom: 1 },
        color: '#E5E7EB'
      })

      Web({ src: AppConstants.LOGIN_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .cacheMode(CacheMode.Default)
        .onPageBegin((event: OnPageBeginEvent) => {
          console.info(`${LOG_TAG} page begin url=${event.url}`);
        })
        .onPageEnd((event: OnPageEndEvent) => {
          console.info(`${LOG_TAG} page end url=${event.url}`);
          WebSessionManager.saveCookies('LoginPage');
          this.logCfClearanceSnapshot('pageEnd');
          if (this.isLikelyLoggedInUrl(event.url)) {
            console.info(`${LOG_TAG} login success detected url=${event.url}`);
            this.stopChallengeCookiePolling();
            this.onLoginSuccess();
          }
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          console.info(`${LOG_TAG} load error url=${this.safeRequestUrl(event.request)} code=${this.safeErrorCode(event.error)} info=${this.safeErrorInfo(event.error)}`);
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          const url: string = this.safeRequestUrl(event.request);
          const statusCode: number = this.safeResponseCode(event.response);
          console.info(`${LOG_TAG} http error url=${url} status=${statusCode} reason=${this.safeReasonMessage(event.response)}`);
          if (this.isChallengeRelatedHttpError(url, statusCode)) {
            this.startChallengeCookiePolling();
          }
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
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

  private startChallengeCookiePolling(): void {
    if (this.challengePollTimer >= 0 || this.hasReloadedAfterChallenge) {
      return;
    }

    this.challengePollCount = 0;
    console.info(`${LOG_TAG} cf_clearance polling start`);
    this.challengePollTimer = setInterval(() => {
      this.challengePollCount++;
      const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
      if (snapshot.hasCookie) {
        console.info(`${LOG_TAG} cf_clearance detected, reload login`);
        WebSessionManager.saveCookies('LoginPage');
        this.stopChallengeCookiePolling();
        this.reloadLoginAfterChallenge();
        return;
      }

      if (this.challengePollCount % 5 === 0) {
        console.info(`${LOG_TAG} cf_clearance pending attempt=${this.challengePollCount}/${MAX_CHALLENGE_POLL_COUNT} cookieHeaderLength=${snapshot.headerLength}`);
      }

      if (this.challengePollCount >= MAX_CHALLENGE_POLL_COUNT) {
        console.info(`${LOG_TAG} cf_clearance polling timeout`);
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
      console.info(`${LOG_TAG} reload login failed error=${JSON.stringify(error)}`);
    }
  }

  private logCfClearanceSnapshot(stage: string): void {
    const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
    console.info(`${LOG_TAG} cf_clearance snapshot stage=${stage} exists=${snapshot.hasCookie} cookieHeaderLength=${snapshot.headerLength}`);
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
