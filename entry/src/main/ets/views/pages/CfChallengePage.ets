import { Log } from '../../services/logging/Log';
import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { isChallengeCompletionResponse } from '../../services/challenge/ChallengeCompletionDetector';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { CookiePresenceSnapshot, WebSessionManager } from '../../services/web/WebSessionManager';

const LOG_TAG: string = '[ArkDO][ChallengePage]';
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';
const CHALLENGE_POLL_INTERVAL_MS: number = 1000;
const MAX_CHALLENGE_POLL_COUNT: number = 90;
// 挑战脚本资源(challenges.cloudflare.com)加载失败后的重载:该域在部分网络下时通时不通,
// 失败即隔 2s 重载挑战页赌下一次能通,最多 3 次,避免用户对着加载页干等。
const CHALLENGE_RELOAD_DELAY_MS: number = 2000;
const MAX_CHALLENGE_RELOADS: number = 3;

@Component
export struct CfChallengePage {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  onClose: () => void = () => {};
  onChallengeResolved: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private challengePollTimer: number = -1;
  private challengePollCount: number = 0;
  private hasResolved: boolean = false;
  // 弹层打开时的 cf_clearance 值快照:失效旧 cookie 仍残留,只有值变化才是 CF 真发了新通行证。
  private initialCfClearance: string = '';
  // 挑战资源(challenges.cloudflare.com)加载失败时的自动重载次数,赌网络下一次能通。
  private challengeReloadCount: number = 0;
  // 【测量】是否观察到 CF 人机验证控件资源(challenges.cloudflare.com)被加载——CF 真发起挑战的铁证。
  private sawChallengeWidget: boolean = false;

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
    WebSessionManager.configureCookieAccess('CfChallengePage');
    this.hasResolved = false;
    this.challengePollCount = 0;
    this.challengeReloadCount = 0;
    this.sawChallengeWidget = false;
    this.initialCfClearance = WebSessionManager.getCfClearanceValue();
    this.logDiagnostic('appear', 'start');
    this.startChallengeCookiePolling();
  }

  aboutToDisappear(): void {
    this.logDiagnostic('disappear', 'stop');
    this.stopChallengeCookiePolling();
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Text('Cloudflare 验证')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Row() {
          Button('关闭')
            .fontSize(15)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.fill_subtle'))
            .height(36)
            .padding({ left: 16, right: 16 })
            .borderRadius(18)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.page_bg'))
      .border({
        width: { bottom: 1 },
        color: $r('app.color.border')
      })

      Web({ src: AppConstants.CHALLENGE_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .onControllerAttached(() => {
          WebSessionManager.applyUserAgent(this.controller, 'CfChallengePage');
        })
        .onPageBegin((event: OnPageBeginEvent) => {
          Log.i(`${LOG_TAG} page begin url=${this.safeUrlLabel(event.url)}`);
          this.logDiagnostic('pageBegin', `url=${this.safeUrlLabel(event.url)}`);
          this.startChallengeCookiePolling();
        })
        .onPageEnd((event: OnPageEndEvent) => {
          Log.i(`${LOG_TAG} page end url=${this.safeUrlLabel(event.url)}`);
          WebSessionManager.saveCookies('CfChallengePage');
          this.logDiagnostic('pageEnd', `url=${this.safeUrlLabel(event.url)}`);
          this.resolveIfCfClearanceExists('pageEnd');
        })
        // 【测量】每个子资源加载都会回调:命中 challenges.cloudflare.com 即证明 CF 真的弹了人机验证控件。
        .onResourceLoad((event: OnResourceLoadEvent) => {
          const label: string = this.safeUrlLabel(event.url);
          if (label === 'cloudflare_challenge_resource') {
            if (!this.sawChallengeWidget) {
              this.sawChallengeWidget = true;
              Log.i(`${LOG_TAG} CF challenge widget resource loaded — CF IS challenging`);
            }
            this.logDiagnostic('challengeWidgetSeen', `label=${label}`);
          } else if (label === 'cloudflare_other') {
            this.logDiagnostic('cloudflareResource', `label=${label}`);
          }
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          const url: string = this.safeRequestUrl(event.request);
          const code: number = this.safeErrorCode(event.error);
          Log.i(`${LOG_TAG} load error url=${this.safeUrlLabel(url)} code=${code} info=${this.safeErrorInfo(event.error)}`);
          this.logDiagnostic('loadError', `url=${this.safeUrlLabel(url)} code=${code}`);
          this.retryOnChallengeResourceFailure(url);
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          const url: string = this.safeRequestUrl(event.request);
          const statusCode: number = this.safeResponseCode(event.response);
          const isMainFrame: boolean = this.safeIsMainFrame(event.request);
          const cfMitigatedHeader: string = this.safeResponseHeader(event.response, 'cf-mitigated');
          Log.i(`${LOG_TAG} http error url=${this.safeUrlLabel(url)} status=${statusCode} mainFrame=${isMainFrame} cfMitigated=${this.safeHeaderLabel(cfMitigatedHeader)} reason=${this.safeReasonMessage(event.response)}`);
          // 【测量】打全 CF 关键响应头原始值 + 完整 url:cf-mitigated=challenge 表示 CF 在质询;
          // 过盾成功后回跳的 404,这里能看到 CF 带回来的完整 url(是否带 __cf_chl_ 查询参数)。
          Log.i(`${LOG_TAG} [MEASURE] status=${statusCode} url="${url}" cf-mitigated="${cfMitigatedHeader}" server="${this.safeResponseHeader(event.response, 'server')}" cf-ray="${this.safeResponseHeader(event.response, 'cf-ray')}"`);
          this.logDiagnostic('httpError', `url=${this.safeUrlLabel(url)} status=${statusCode} mainFrame=${isMainFrame} cfMitigated="${cfMitigatedHeader}"`);
          if (this.resolveIfChallengeCompletionResponse(url, statusCode, isMainFrame, cfMitigatedHeader)) {
            return;
          }
          this.startChallengeCookiePolling();
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  private startChallengeCookiePolling(): void {
    if (this.challengePollTimer >= 0 || this.hasResolved) {
      return;
    }

    this.challengePollCount = 0;
    Log.i(`${LOG_TAG} cf_clearance polling start`);
    this.logDiagnostic('pollStart', 'start');
    this.challengePollTimer = setInterval(() => {
      this.challengePollCount++;
      if (this.resolveIfCfClearanceExists('polling')) {
        return;
      }

      if (this.challengePollCount % 5 === 0) {
        const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
        Log.i(`${LOG_TAG} cf_clearance pending attempt=${this.challengePollCount}/${MAX_CHALLENGE_POLL_COUNT} cookieHeaderLength=${snapshot.headerLength}`);
        this.logDiagnostic('pollPending', `attempt=${this.challengePollCount}/${MAX_CHALLENGE_POLL_COUNT}`);
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

  private resolveIfCfClearanceExists(stage: string): boolean {
    if (this.hasResolved) {
      return true;
    }

    // "值变化"判定:仅凭存在性会被过期残留的旧 cf_clearance 误触发而秒关弹层;
    // 必须与打开弹层时的快照不同,才算 CF 真的发了新通行证。
    const current: string = WebSessionManager.getCfClearanceValue();
    if (current.length === 0 || current === this.initialCfClearance) {
      return false;
    }

    this.hasResolved = true;
    Log.i(`${LOG_TAG} cf_clearance changed stage=${stage}`);
    this.logDiagnostic('resolvedByCookie', `stage=${stage}`);
    WebSessionManager.saveCookies('CfChallengePage');
    this.stopChallengeCookiePolling();
    this.onChallengeResolved();
    return true;
  }

  // 挑战脚本资源加载失败时隔 2s 重载挑战页(限 3 次),赌该域下一次可达。
  private retryOnChallengeResourceFailure(url: string): void {
    if (this.hasResolved || this.safeUrlLabel(url) !== 'cloudflare_challenge_resource') {
      return;
    }
    if (this.challengeReloadCount >= MAX_CHALLENGE_RELOADS) {
      this.logDiagnostic('challengeResourceGaveUp', `count=${this.challengeReloadCount}`);
      return;
    }
    this.challengeReloadCount++;
    this.logDiagnostic('challengeResourceRetry', `count=${this.challengeReloadCount}`);
    setTimeout(() => {
      if (this.hasResolved) {
        return;
      }
      try {
        this.controller.refresh();
      } catch (error) {
        // 控制器未就绪等异常忽略,下一次资源失败还会再触发。
      }
    }, CHALLENGE_RELOAD_DELAY_MS);
  }

  private resolveIfChallengeCompletionResponse(url: string, statusCode: number, isMainFrame: boolean, cfMitigatedHeader: string): boolean {
    if (this.hasResolved) {
      return true;
    }

    if (!isChallengeCompletionResponse({
      url,
      statusCode,
      isMainFrame,
      cfMitigatedHeader
    })) {
      return false;
    }

    // 门槛:只认"CF 真挑战过之后"的 404 为过盾成功。sawChallengeWidget=false 说明 CF 根本没挑战、
    // 直接放行到源站的假 404(不需要过盾),此时不算过盾、不关窗,避免假报"已通过"。
    if (!this.sawChallengeWidget) {
      this.logDiagnostic('source404NoChallenge', `url=${this.safeUrlLabel(url)}`);
      return false;
    }

    this.hasResolved = true;
    Log.i(`${LOG_TAG} challenge resolved by source 404 url=${this.safeUrlLabel(url)} status=${statusCode} cfMitigated=${this.safeHeaderLabel(cfMitigatedHeader)}`);
    this.logDiagnostic('resolvedBySource404', `url=${this.safeUrlLabel(url)} status=${statusCode} cfMitigated=${this.safeHeaderLabel(cfMitigatedHeader)}`);
    WebSessionManager.saveCookies('CfChallengePage');
    this.stopChallengeCookiePolling();
    this.onChallengeResolved();
    return true;
  }

  private logDiagnostic(stage: string, detail: string): void {
    const snapshot: CookiePresenceSnapshot = WebSessionManager.getCookiePresenceSnapshot('cf_clearance');
    Log.i(`${DIAG_TAG} stage=${stage} hasCfClearance=${snapshot.hasCookie} cookieHeaderLength=${snapshot.headerLength} pollCount=${this.challengePollCount} timerActive=${this.challengePollTimer >= 0} hasResolved=${this.hasResolved} sawChallengeWidget=${this.sawChallengeWidget} ${detail}`);
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

  private safeIsMainFrame(request: WebResourceRequest): boolean {
    try {
      return request.isMainFrame();
    } catch (error) {
      return false;
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

  private safeResponseHeader(response: WebResourceResponse, headerName: string): string {
    try {
      const headers: Array<Header> = response.getResponseHeader();
      const target: string = headerName.toLowerCase();
      for (let index: number = 0; index < headers.length; index++) {
        if (headers[index].headerKey.toLowerCase() === target) {
          return headers[index].headerValue;
        }
      }
      return '';
    } catch (error) {
      return '';
    }
  }

  private safeHeaderLabel(value: string): string {
    if (value.length === 0) {
      return 'empty';
    }
    if (value.toLowerCase().indexOf('challenge') >= 0) {
      return 'challenge';
    }
    return 'present';
  }
}
