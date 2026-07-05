import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { ChallengeEventBus } from '../challenge/ChallengeEventBus';
import { detectChallenge } from './ChallengeDetector';
import { ChallengeState, JsonNetworkClient, JsonRequestOptions, NetworkErrorCode, NetworkResult } from './NetworkTypes';

const REQUEST_ID_TOKEN: string = '__ARKDO_REQUEST_ID__';
const BODY_LOG_CHUNK_SIZE: number = 3000;

function logNetwork(message: string): void {
  console.info(`[ArkDO][Network] ${message}`);
}

function logNetworkBody(message: string): void {
  console.info(`[ArkDO][Network][Body] ${message}`);
}

export interface ArkWebJsonExecutor {
  run(script: string): Promise<string>;
}

interface ArkWebResultReceiver {
  onJsonResult(requestId: string, payload: string): void;
}

interface WebFetchEnvelope {
  statusCode?: number;
  contentType?: string;
  body?: string;
  errorMessage?: string;
}

class PendingJsonRequest {
  resolve: (value: string) => void;
  reject: (reason: string) => void;
  timeoutId: number;

  constructor(resolve: (value: string) => void, reject: (reason: string) => void, timeoutId: number) {
    this.resolve = resolve;
    this.reject = reject;
    this.timeoutId = timeoutId;
  }
}

export class ArkWebCallbackProxy {
  private receiver: ArkWebResultReceiver;

  constructor(receiver: ArkWebResultReceiver) {
    this.receiver = receiver;
  }

  onJsonResult(requestId: string, payload: string): void {
    this.receiver.onJsonResult(requestId, payload);
  }
}

class WebviewJsonExecutor implements ArkWebJsonExecutor, ArkWebResultReceiver {
  private controller: webview.WebviewController;
  private callbackProxy: ArkWebCallbackProxy = new ArkWebCallbackProxy(this);
  private pendingRequests: Map<string, PendingJsonRequest> = new Map();
  private requestSequence: number = 0;

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  getCallbackProxy(): ArkWebCallbackProxy {
    return this.callbackProxy;
  }

  run(script: string): Promise<string> {
    const requestId: string = `arkdo_${this.requestSequence}`;
    this.requestSequence++;
    logNetwork(`ArkWeb executor start requestId=${requestId}`);

    return new Promise<string>((resolve: (value: string) => void, reject: (reason: string) => void) => {
      const timeoutId: number = setTimeout(() => {
        this.rejectRequest(requestId, 'ArkWeb 请求超时。');
      }, AppConstants.DEFAULT_TIMEOUT_MS);
      this.pendingRequests.set(requestId, new PendingJsonRequest(resolve, reject, timeoutId));

      try {
        this.controller.runJavaScript(script.replace(REQUEST_ID_TOKEN, requestId))
          .catch(() => {
            this.rejectRequest(requestId, 'ArkWeb 脚本执行失败。');
          });
      } catch (error) {
        this.rejectRequest(requestId, 'ArkWeb 脚本执行失败。');
      }
    });
  }

  onJsonResult(requestId: string, payload: string): void {
    const pendingRequest: PendingJsonRequest | undefined = this.pendingRequests.get(requestId);
    if (!pendingRequest) {
      logNetwork(`ArkWeb callback ignored requestId=${requestId}`);
      return;
    }

    logNetwork(`ArkWeb callback received requestId=${requestId} payloadLength=${payload.length}`);
    clearTimeout(pendingRequest.timeoutId);
    this.pendingRequests.delete(requestId);
    pendingRequest.resolve(payload);
  }

  private rejectRequest(requestId: string, message: string): void {
    const pendingRequest: PendingJsonRequest | undefined = this.pendingRequests.get(requestId);
    if (!pendingRequest) {
      return;
    }

    logNetwork(`ArkWeb executor reject requestId=${requestId} reason=${message}`);
    clearTimeout(pendingRequest.timeoutId);
    this.pendingRequests.delete(requestId);
    pendingRequest.reject(message);
  }
}

export class ArkWebNetworkBridge implements JsonNetworkClient {
  private executor?: ArkWebJsonExecutor;
  private webviewExecutor?: WebviewJsonExecutor;
  // host webview 是否正在被 loadUrl 重载。重载期间注入的 fetch 会落在正被销毁的文档上,
  // 因此排队等待,直到重载后的 onPageEnd 再执行。默认 false = 就绪,不影响正常请求。
  private reloading: boolean = false;
  private readyWaiters: Array<() => void> = [];

  attachController(controller: webview.WebviewController): void {
    this.setExecutor(this.ensureWebviewExecutor(controller));
  }

  // host webview 开始 loadUrl 重载：关闭门闩，随后的注入式 fetch 排队等待。
  markHostReloading(): void {
    this.reloading = true;
  }

  // host webview 重载完成（onPageEnd）：放行所有排队的 fetch，令其注入到刷新后的文档。
  markHostReady(): void {
    this.reloading = false;
    if (this.readyWaiters.length === 0) {
      return;
    }
    const waiters: Array<() => void> = this.readyWaiters;
    this.readyWaiters = [];
    for (let index: number = 0; index < waiters.length; index++) {
      waiters[index]();
    }
  }

  private whenHostReady(): Promise<void> {
    if (!this.reloading) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      // 兜底超时:万一重载信号丢失(onPageEnd 始终不触发),自愈放行并恢复就绪态,
      // 既不让本次请求永久悬住,也避免后续请求持续等待。
      const timeoutId: number = setTimeout(() => {
        this.markHostReady();
      }, AppConstants.HOST_RELOAD_READY_TIMEOUT_MS);
      this.readyWaiters.push(() => {
        clearTimeout(timeoutId);
        resolve();
      });
    });
  }

  createJavaScriptProxy(controller: webview.WebviewController): JavaScriptProxy {
    const executor: WebviewJsonExecutor = this.ensureWebviewExecutor(controller);
    return {
      object: executor.getCallbackProxy(),
      name: 'ArkDOBridge',
      methodList: ['onJsonResult'],
      controller: controller
    };
  }

  setExecutor(executor: ArkWebJsonExecutor): void {
    this.executor = executor;
  }

  async getJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    logNetwork(`GET ${requestPath} start`);

    if (!this.executor) {
      logNetwork(`GET ${requestPath} skipped: ArkWeb host is not ready`);
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: 'ArkWeb 宿主尚未就绪。',
          requiresChallenge: false
        }
      };
    }

    await this.whenHostReady();

    try {
      const rawResult: string = await this.executor.run(this.createFetchScript(requestPath));
      logNetwork(`GET ${requestPath} raw envelope received length=${rawResult.length}`);
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, options);
    } catch (error) {
      logNetwork(`GET ${requestPath} failed before response envelope`);
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: 'ArkWeb 请求失败。',
          requiresChallenge: false
        }
      };
    }
  }

  async postForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    logNetwork(`POST ${requestPath} start bodyLength=${body.length}`);

    if (!this.executor) {
      logNetwork(`POST ${requestPath} skipped: ArkWeb host is not ready`);
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: 'ArkWeb 宿主尚未就绪。',
          requiresChallenge: false
        }
      };
    }

    await this.whenHostReady();

    try {
      const rawResult: string = await this.executor.run(this.createPostFormScript(requestPath, body));
      logNetwork(`POST ${requestPath} raw envelope received length=${rawResult.length}`);
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, options);
    } catch (error) {
      logNetwork(`POST ${requestPath} failed before response envelope`);
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: 'ArkWeb 请求失败。',
          requiresChallenge: false
        }
      };
    }
  }

  private createFetchScript(path: string): string {
    const encodedPath: string = JSON.stringify(path);

    return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL(${encodedPath}, window.location.origin);
      requestUrl.searchParams.set('_arkdo_ts', Date.now().toString());
      fetch(requestUrl.toString(), {
        credentials: 'include',
        cache: 'no-store',
        headers: {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache'
        }
      }).then((response) => {
        response.text().then((body) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            body: body
          }));
        }).catch((error) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: 0,
            contentType: '',
            body: '',
            errorMessage: String(error)
          }));
        });
      }).catch((error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0,
          contentType: '',
          body: '',
          errorMessage: String(error)
        }));
      });
      return requestId;
    })();`;
  }

  private createPostFormScript(path: string, body: string): string {
    const encodedPath: string = JSON.stringify(path);
    const encodedBody: string = JSON.stringify(body);

    // 同源脚本:先取 CSRF token(优先 /session/csrf.json,兜底页面 meta),再带头 POST。
    // cookie 靠 credentials:'include' 自动携带;结果照旧走 window.ArkDOBridge.onJsonResult。
    return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL(${encodedPath}, window.location.origin);
      const fail = (error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0,
          contentType: '',
          body: '',
          errorMessage: String(error)
        }));
      };
      const metaCsrf = () => {
        const el = document.querySelector('meta[name="csrf-token"]');
        return el ? (el.getAttribute('content') || '') : '';
      };
      const readCsrf = () => {
        return fetch(new URL('/session/csrf.json', window.location.origin).toString(), {
          credentials: 'include',
          cache: 'no-store',
          headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
        }).then((r) => r.json()).then((j) => (j && j.csrf) ? j.csrf : '').catch(() => '');
      };
      Promise.resolve(readCsrf()).then((token) => {
        const csrf = token || metaCsrf();
        return fetch(requestUrl.toString(), {
          method: 'POST',
          credentials: 'include',
          cache: 'no-store',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Accept': 'application/json',
            'X-CSRF-Token': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'X-SILENCE-LOGGER': 'true',
            'Discourse-Background': 'true'
          },
          body: ${encodedBody}
        });
      }).then((response) => {
        response.text().then((body) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            body: body
          }));
        }).catch(fail);
      }).catch(fail);
      return requestId;
    })();`;
  }

  private ensureWebviewExecutor(controller: webview.WebviewController): WebviewJsonExecutor {
    if (!this.webviewExecutor) {
      this.webviewExecutor = new WebviewJsonExecutor(controller);
    }
    return this.webviewExecutor;
  }

  private normalizePath(path: string): string {
    if (path.startsWith('/')) {
      return path;
    }
    return `/${path}`;
  }

  private convertEnvelope(path: string, envelope: WebFetchEnvelope, options?: JsonRequestOptions): NetworkResult<string> {
    if (envelope.errorMessage) {
      logNetwork(`GET ${path} envelope error=${envelope.errorMessage}`);
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: envelope.errorMessage,
          requiresChallenge: false
        }
      };
    }

    const statusCode: number = envelope.statusCode ? envelope.statusCode : 0;
    const contentType: string = envelope.contentType ? envelope.contentType : '';
    const body: string = envelope.body ? envelope.body : '';
    const challengeState: ChallengeState = detectChallenge(statusCode, contentType, body);
    logNetwork(`GET ${path} response status=${statusCode} contentType=${contentType} bodyLength=${body.length} challenge=${challengeState}`);
    this.logResponseBody(path, contentType, body);

    if (challengeState !== ChallengeState.NONE) {
      logNetwork(`GET ${path} requires challenge state=${challengeState}`);
      if (options?.notifyChallenge !== false) {
        ChallengeEventBus.notifyChallengeRequired(path, statusCode, challengeState);
      }
      return {
        success: false,
        statusCode: statusCode,
        challengeState: challengeState,
        error: {
          code: NetworkErrorCode.CHALLENGE_REQUIRED,
          message: '需要完成可见 Cloudflare 验证后重试。',
          requiresChallenge: true
        }
      };
    }

    if (statusCode < 200 || statusCode >= 300) {
      logNetwork(`GET ${path} unexpected status=${statusCode}`);
      return {
        success: false,
        statusCode: statusCode,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.UNEXPECTED_RESPONSE,
          message: `Linux.do 返回 HTTP ${statusCode}。`,
          requiresChallenge: false
        }
      };
    }

    const result: NetworkResult<string> = {
      success: true,
      statusCode: statusCode,
      challengeState: ChallengeState.NONE,
      data: body
    };

    logNetwork(`GET ${path} success status=${statusCode} bodyLength=${body.length}`);
    return result;
  }

  private logResponseBody(path: string, contentType: string, body: string): void {
    const formattedBody: string = this.formatBodyForLog(contentType, body);
    const chunkCount: number = Math.ceil(formattedBody.length / BODY_LOG_CHUNK_SIZE);

    logNetworkBody(`GET ${path} body begin contentType=${contentType} rawLength=${body.length} formattedLength=${formattedBody.length} chunks=${chunkCount}`);
    if (formattedBody.length === 0) {
      logNetworkBody(`GET ${path} body chunk 1/1: `);
    }

    for (let start: number = 0; start < formattedBody.length; start += BODY_LOG_CHUNK_SIZE) {
      const chunkIndex: number = Math.floor(start / BODY_LOG_CHUNK_SIZE) + 1;
      const chunk: string = formattedBody.substring(start, start + BODY_LOG_CHUNK_SIZE);
      logNetworkBody(`GET ${path} body chunk ${chunkIndex}/${chunkCount}: ${chunk}`);
    }
    logNetworkBody(`GET ${path} body end`);
  }

  private formatBodyForLog(contentType: string, body: string): string {
    const normalizedContentType: string = contentType.toLowerCase();
    const trimmedBody: string = body.trim();
    const looksJson: boolean = normalizedContentType.indexOf('application/json') >= 0 ||
      trimmedBody.startsWith('{') ||
      trimmedBody.startsWith('[');

    if (!looksJson) {
      return body;
    }

    try {
      const parsedBody: Object = JSON.parse(body) as Object;
      const formattedBody: string = JSON.stringify(parsedBody, null, 2);
      return formattedBody;
    } catch (error) {
      return body;
    }
  }
}
