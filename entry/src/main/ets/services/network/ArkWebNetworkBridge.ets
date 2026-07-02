import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { detectChallenge } from './ChallengeDetector';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from './NetworkTypes';

const REQUEST_ID_TOKEN: string = '__ARKDO_REQUEST_ID__';

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
      return;
    }

    clearTimeout(pendingRequest.timeoutId);
    this.pendingRequests.delete(requestId);
    pendingRequest.resolve(payload);
  }

  private rejectRequest(requestId: string, message: string): void {
    const pendingRequest: PendingJsonRequest | undefined = this.pendingRequests.get(requestId);
    if (!pendingRequest) {
      return;
    }

    clearTimeout(pendingRequest.timeoutId);
    this.pendingRequests.delete(requestId);
    pendingRequest.reject(message);
  }
}

export class ArkWebNetworkBridge implements JsonNetworkClient {
  private executor?: ArkWebJsonExecutor;
  private webviewExecutor?: WebviewJsonExecutor;

  attachController(controller: webview.WebviewController): void {
    this.setExecutor(this.ensureWebviewExecutor(controller));
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

  async getJson(path: string): Promise<NetworkResult<string>> {
    if (!this.executor) {
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

    try {
      const rawResult: string = await this.executor.run(this.createFetchScript(path));
      return this.convertEnvelope(JSON.parse(rawResult) as WebFetchEnvelope);
    } catch (error) {
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
    const requestPath: string = this.normalizePath(path);
    const encodedPath: string = JSON.stringify(requestPath);

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

  private convertEnvelope(envelope: WebFetchEnvelope): NetworkResult<string> {
    if (envelope.errorMessage) {
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

    if (challengeState !== ChallengeState.NONE) {
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

    return result;
  }
}
