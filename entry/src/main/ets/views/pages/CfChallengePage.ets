import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { CookiePresenceSnapshot, WebSessionManager } from '../../services/web/WebSessionManager';

const LOG_TAG: string = '[ArkDO][ChallengePage]';
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';
const CHALLENGE_POLL_INTERVAL_MS: number = 1000;
const MAX_CHALLENGE_POLL_COUNT: number = 90;

@Component
export struct CfChallengePage {
  onClose: () => void = () => {};
  onChallengeResolved: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private challengePollTimer: number = -1;
  private challengePollCount: number = 0;
  private hasResolved: boolean = false;

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('CfChallengePage');
    this.hasResolved = false;
    this.challengePollCount = 0;
    this.logDiagnostic('appear', 'start');
    this.startChallengeCookiePolling();
  }

  aboutToDisappear(): void {
    this.logDiagnostic('disappear', 'stop');
    this.stopChallengeCookiePolling();
  }

  build() {
    Column() {
      Row() {
        Button('关闭')
          .fontSize(15)
          .fontColor('#2563EB')
          .backgroundColor('#F3F4F6')
          .height(36)
          .padding({ left: 16, right: 16 })
          .borderRadius(18)
          .onClick(() => {
            this.onClose();
          })

        Text('Cloudflare 验证')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .margin({ left: 16 })
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')
      .border({
        width: { bottom: 1 },
        color: '#E5E7EB'
      })

      Web({ src: AppConstants.CHALLENGE_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .cacheMode(CacheMode.Default)
        .onPageBegin((event: OnPageBeginEvent) => {
          console.info(`${LOG_TAG} page begin url=${this.safeUrlLabel(event.url)}`);
          this.logDiagnostic('pageBegin', `url=${this.safeUrlLabel(event.url)}`);
          this.startChallengeCookiePolling();
        })
        .onPageEnd((event: OnPageEndEvent) => {
          console.info(`${LOG_TAG} page end url=${this.safeUrlLabel(event.url)}`);
          WebSessionManager.saveCookies('CfChallengePage');
          this.logDiagnostic('pageEnd', `url=${this.safeUrlLabel(event.url)}`);
          this.resolveIfCfClearanceExists('pageEnd');
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          const url: string = this.safeRequestUrl(event.request);
          const code: number = this.safeErrorCode(event.error);
          console.info(`${LOG_TAG} load error url=${this.safeUrlLabel(url)} code=${code} info=${this.safeErrorInfo(event.error)}`);
          this.logDiagnostic('loadError', `url=${this.safeUrlLabel(url)} code=${code}`);
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          const url: string = this.safeRequestUrl(event.request);
          const statusCode: number = this.safeResponseCode(event.response);
          console.info(`${LOG_TAG} http error url=${this.safeUrlLabel(url)} status=${statusCode} reason=${this.safeReasonMessage(event.response)}`);
          this.logDiagnostic('httpError', `url=${this.safeUrlLabel(url)} status=${statusCode}`);
          this.startChallengeCookiePolling();
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  private startChallengeCookiePolling(): void {
    if (this.challengePollTimer >= 0 || this.hasResolved) {
      return;
    }

    this.challengePollCount = 0;
    console.info(`${LOG_TAG} cf_clearance polling start`);
    this.logDiagnostic('pollStart', 'start');
    this.challengePollTimer = setInterval(() => {
      this.challengePollCount++;
      if (this.resolveIfCfClearanceExists('polling')) {
        return;
      }

      if (this.challengePollCount % 5 === 0) {
        const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
        console.info(`${LOG_TAG} cf_clearance pending attempt=${this.challengePollCount}/${MAX_CHALLENGE_POLL_COUNT} cookieHeaderLength=${snapshot.headerLength}`);
        this.logDiagnostic('pollPending', `attempt=${this.challengePollCount}/${MAX_CHALLENGE_POLL_COUNT}`);
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

  private resolveIfCfClearanceExists(stage: string): boolean {
    if (this.hasResolved) {
      return true;
    }

    const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
    if (!snapshot.hasCookie) {
      return false;
    }

    this.hasResolved = true;
    console.info(`${LOG_TAG} cf_clearance detected stage=${stage} cookieHeaderLength=${snapshot.headerLength}`);
    this.logDiagnostic('resolvedByCookie', `stage=${stage}`);
    WebSessionManager.saveCookies('CfChallengePage');
    this.stopChallengeCookiePolling();
    this.onChallengeResolved();
    return true;
  }

  private logDiagnostic(stage: string, detail: string): void {
    const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
    console.info(`${DIAG_TAG} stage=${stage} hasCfClearance=${snapshot.hasCookie} cookieHeaderLength=${snapshot.headerLength} pollCount=${this.challengePollCount} timerActive=${this.challengePollTimer >= 0} hasResolved=${this.hasResolved} ${detail}`);
  }

  private safeUrlLabel(url: string): string {
    if (url.length === 0) {
      return 'empty';
    }

    if (url.startsWith(AppConstants.CHALLENGE_URL)) {
      return 'linuxdo_challenge';
    }
    if (url === AppConstants.BASE_URL || url === `${AppConstants.BASE_URL}/`) {
      return 'linuxdo_home';
    }
    if (url.startsWith(AppConstants.LOGIN_URL)) {
      return 'linuxdo_login';
    }
    if (url.startsWith(AppConstants.BASE_URL)) {
      return 'linuxdo_other';
    }
    if (url.indexOf('challenges.cloudflare.com') >= 0) {
      return 'cloudflare_challenge_resource';
    }
    if (url.indexOf('cloudflare') >= 0) {
      return 'cloudflare_other';
    }
    return 'other';
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
