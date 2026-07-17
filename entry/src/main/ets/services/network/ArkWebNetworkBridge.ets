import { Log } from '../logging/Log';
import webview from '@ohos.web.webview';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { ChallengeEventBus } from '../challenge/ChallengeEventBus';
import { DownloadEventBus } from '../content/DownloadEventBus';
import { detectChallenge } from './ChallengeDetector';
import { FileLogger } from '../logging/FileLogger';
import { ChallengeState, JsonNetworkClient, JsonRequestOptions, NetworkErrorCode, NetworkResult } from './NetworkTypes';

const REQUEST_ID_TOKEN: string = '__ARKDO_REQUEST_ID__';
// 媒体下载兜底超时:委托始终不回调(如 URL 无效/挑战未过)时,自愈拒绝以免播放器永久转圈。
const MEDIA_DOWNLOAD_TIMEOUT_MS: number = 120000;
const BODY_LOG_CHUNK_SIZE: number = 3000;
// 响应体转储上限:仅对挑战/错误/异常响应保留头部证据(判定是挑战页还是数据),截断以控制日志体积。
const BODY_LOG_MAX_CHARS: number = 1500;

function logNetwork(message: string): void {
  Log.i(`[ArkDO][Network] ${message}`);
}

function logNetworkBody(message: string): void {
  Log.i(`[ArkDO][Network][Body] ${message}`);
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
  // POST 诊断:本次使用的 CSRF token 来源(session/meta/none)与长度,用于定位 403 是否为 CSRF 不匹配。
  csrfSource?: string;
  csrfLength?: number;
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

// 一次下载意图:委托的 getUrl() 会被重写成跟随 302 后的 CDN 直链,无法按 URL 回认。
// 故每次发起下载按顺序入队一个意图,onBeforeDownload 按序出队即可辨别当前下载是媒体还是附件、
// 以及媒体对应的原始 URL(下载在单线程 native 队列中按发起顺序回调)。
class DownloadIntent {
  isMedia: boolean;
  url: string;

  constructor(isMedia: boolean, url: string) {
    this.isMedia = isMedia;
    this.url = url;
  }
}

// 一次媒体下载的等待者:委托完成/失败后按原始 URL 找到它并 resolve 本地路径 / reject。
class MediaDownloadWaiter {
  resolve: (path: string) => void;
  reject: (reason: Object) => void;
  timeoutId: number;

  constructor(resolve: (path: string) => void, reject: (reason: Object) => void, timeoutId: number) {
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

/** 经 host webview 取到的二进制资源(头像等):base64 是原始字节的 base64,失败时 ok=false。 */
export interface ImageFetchResult {
  ok: boolean;
  base64: string;
  contentType: string;
}

export class ArkWebNetworkBridge implements JsonNetworkClient {
  private executor?: ArkWebJsonExecutor;
  private webviewExecutor?: WebviewJsonExecutor;
  // host webview 是否正在被 loadUrl 重载。重载期间注入的 fetch 会落在正被销毁的文档上,
  // 因此排队等待,直到重载后的 onPageEnd 再执行。默认 false = 就绪,不影响正常请求。
  private reloading: boolean = false;
  private readyWaiters: Array<() => void> = [];
  // host webview 控制器与其原生下载委托:附件下载走它,天然带会话 Cookie、自动跟随 302 到 CDN、不受 CORS 限制。
  private controller?: webview.WebviewController;
  private downloadContext?: Context;
  private downloadDelegateReady: boolean = false;
  // 媒体下载(音视频)复用同一下载委托。CF 会对非浏览器客户端(fetch/http/AVPlayer)返回 403,
  // 唯有 host webview(Chromium)下载能过盾、跟 302、带 cookie。按 URL 缓存本地路径 + 并发去重;
  // guid→url 用于在委托完成回调里把结果对回到正确的等待者(而非走附件的「用系统打开」通用流程)。
  private mediaWaiters: Map<string, MediaDownloadWaiter> = new Map();
  private mediaInflight: Map<string, Promise<string>> = new Map();
  private mediaGuidUrl: Map<string, string> = new Map();
  private mediaCache: Map<string, string> = new Map();
  // 下载意图 FIFO:按发起顺序入队,onBeforeDownload 出队辨别媒体/附件。
  private downloadIntents: DownloadIntent[] = [];

  attachController(controller: webview.WebviewController): void {
    this.controller = controller;
    this.setExecutor(this.ensureWebviewExecutor(controller));
    this.configureDownloadDelegate();
  }

  // 清空媒体缓存目录(音视频下到 filesDir/media_cache)。冷启动时调用,避免缓存无限增长;
  // 同会话内文件保留以便重复播放不重复下载。不碰附件目录 download(那是用户主动下的文件)。
  static clearMediaCacheDir(context: Context): void {
    const dir: string = `${context.filesDir}/media_cache`;
    try {
      if (fs.accessSync(dir)) {
        fs.rmdirSync(dir);
        Log.i(`[ArkDO][Network] media cache cleared dir=${dir}`);
      }
    } catch (error) {
      Log.i(`[ArkDO][Network] media cache clear failed error=${JSON.stringify(error)}`);
    }
  }

  // 记录用于保存下载文件的沙箱上下文(filesDir)。在 host 就绪前由页面注入一次。
  setDownloadContext(context: Context): void {
    this.downloadContext = context;
    this.configureDownloadDelegate();
  }

  // 触发一次附件下载。成功交给 host webview 的下载委托,结果经 DownloadEventBus 上抛。
  startDownload(url: string): boolean {
    if (!this.controller) {
      Log.i('[ArkDO][Network] startDownload skipped: controller not ready');
      return false;
    }
    this.downloadIntents.push(new DownloadIntent(false, url));
    try {
      this.controller.startDownload(url);
      return true;
    } catch (error) {
      this.downloadIntents.pop();
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Network] startDownload failed code=${err.code} msg=${err.message}`);
      return false;
    }
  }

  // 触发一次媒体下载(音视频),返回下到沙箱后的本地文件路径。走 host webview 下载委托过 CF。
  // 已下过的直接命中缓存;进行中的复用同一 Promise(去重),避免重复播放重复下载。
  downloadMedia(url: string): Promise<string> {
    const cached: string | undefined = this.mediaCache.get(url);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const pending: Promise<string> | undefined = this.mediaInflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    if (!this.controller) {
      return Promise.reject(new Error('宿主尚未就绪'));
    }
    const promise: Promise<string> = new Promise<string>((resolve: (path: string) => void, reject: (reason: Object) => void) => {
      const timeoutId: number = setTimeout(() => {
        this.settleMediaFailure(url, new Error('媒体下载超时'));
      }, MEDIA_DOWNLOAD_TIMEOUT_MS);
      this.mediaWaiters.set(url, new MediaDownloadWaiter(resolve, reject, timeoutId));
    });
    this.mediaInflight.set(url, promise);
    this.downloadIntents.push(new DownloadIntent(true, url));
    try {
      this.controller.startDownload(url);
    } catch (error) {
      this.downloadIntents.pop();
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Network] downloadMedia start failed code=${err.code}`);
      this.settleMediaFailure(url, new Error('媒体下载启动失败'));
    }
    return promise;
  }

  private settleMediaSuccess(url: string, path: string): void {
    this.mediaInflight.delete(url);
    this.mediaCache.set(url, path);
    const waiter: MediaDownloadWaiter | undefined = this.mediaWaiters.get(url);
    if (waiter) {
      this.mediaWaiters.delete(url);
      clearTimeout(waiter.timeoutId);
      waiter.resolve(path);
    }
  }

  private settleMediaFailure(url: string, reason: Object): void {
    this.mediaInflight.delete(url);
    const waiter: MediaDownloadWaiter | undefined = this.mediaWaiters.get(url);
    if (waiter) {
      this.mediaWaiters.delete(url);
      clearTimeout(waiter.timeoutId);
      waiter.reject(reason);
    }
  }

  // 给 host 控制器挂下载委托:onBeforeDownload 选沙箱保存路径并启动;完成/失败经 DownloadEventBus 通知页面
  // (媒体下载则对回到 downloadMedia 的等待者)。需控制器与保存上下文都就绪,且只挂一次。
  private configureDownloadDelegate(): void {
    if (this.downloadDelegateReady || !this.controller || !this.downloadContext) {
      return;
    }
    const context: Context = this.downloadContext;
    const attachmentDir: string = `${context.filesDir}/download`;
    const mediaDir: string = `${context.filesDir}/media_cache`;
    try {
      const delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
      delegate.onBeforeDownload((item: webview.WebDownloadItem) => {
        // 先按发起顺序出队意图:委托的 getUrl() 已是 CDN 直链,无法回认,故靠 FIFO 顺序辨别媒体/附件。
        const intent: DownloadIntent | undefined = this.downloadIntents.shift();
        const isMedia: boolean = intent !== undefined && intent.isMedia;
        // 媒体下到独立目录(便于整目录清理、不误删用户附件);附件仍到 download。
        const dir: string = isMedia ? mediaDir : attachmentDir;
        try {
          if (!fs.accessSync(dir)) {
            fs.mkdirSync(dir);
          }
        } catch (error) {
          const err: BusinessError = error as BusinessError;
          Log.i(`[ArkDO][Network] download dir failed code=${err.code}`);
        }
        const suggested: string = item.getSuggestedFileName();
        const fileName: string = suggested && suggested.length > 0 ? suggested : `download_${item.getGuid()}`;
        item.start(`${dir}/${fileName}`);
        // 媒体:用 guid 记住它对应的原始 URL(media 等待者以原始 URL 为键)。
        if (isMedia && intent) {
          this.mediaGuidUrl.set(item.getGuid(), intent.url);
        }
      });
      delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
        const fullPath: string = item.getFullPath();
        const guid: string = item.getGuid();
        const mediaUrl: string | undefined = this.mediaGuidUrl.get(guid);
        if (mediaUrl !== undefined) {
          this.mediaGuidUrl.delete(guid);
          Log.i(`[ArkDO][Network] media download finished path=${fullPath}`);
          this.settleMediaSuccess(mediaUrl, fullPath);
          return;
        }
        const fileName: string = fullPath.substring(fullPath.lastIndexOf('/') + 1);
        DownloadEventBus.notify({ success: true, fileName, filePath: fullPath, message: `已下载：${fileName}` });
      });
      delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
        const guid: string = item.getGuid();
        const mediaUrl: string | undefined = this.mediaGuidUrl.get(guid);
        if (mediaUrl !== undefined) {
          this.mediaGuidUrl.delete(guid);
          Log.i('[ArkDO][Network] media download failed');
          this.settleMediaFailure(mediaUrl, new Error('媒体下载失败'));
          return;
        }
        const suggested: string = item.getSuggestedFileName();
        DownloadEventBus.notify({ success: false, fileName: suggested, filePath: '', message: '下载失败' });
      });
      this.controller.setDownloadDelegate(delegate);
      this.downloadDelegateReady = true;
      Log.i('[ArkDO][Network] download delegate configured');
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Network] configure download delegate failed code=${err.code}`);
    }
  }

  // host webview 开始 loadUrl 重载：关闭门闩，随后的注入式 fetch 排队等待。
  markHostReloading(): void {
    this.reloading = true;
  }

  // 主动重载 host 首页:一次真实页面导航,让 CF 挑战 JS 在真浏览器环境里运行以拿 cf_clearance
  // (fetch 拿到的挑战页无法执行 JS)。用于挑战恢复协调器静默过盾;onPageEnd 会放行排队的 fetch。
  reloadHost(): boolean {
    if (!this.controller) {
      Log.i('[ArkDO][Network] reloadHost skipped: controller not ready');
      return false;
    }
    try {
      this.markHostReloading();
      this.controller.loadUrl(AppConstants.HOST_BOOTSTRAP_URL);
      return true;
    } catch (error) {
      // loadUrl 抛异常时不会有后续 onPageEnd,立即放行等待者以免请求悬住。
      this.markHostReady();
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Network] reloadHost failed code=${err.code}`);
      return false;
    }
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
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, 'GET', options);
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

  /**
   * 经 host webview 取二进制资源(头像)并回传 base64。原生 Image/DownloadManager 走系统 netstack,
   * TLS 握手时明文 SNi=linux.do 被 RST 封锁(只有 webview 能用 ECH 藏 SNI 过盾),故头像必须走这条路。
   * 在 host 文档内 fetch → arrayBuffer → base64,复用 onJsonResult 回调通道。失败返回 ok=false。
   */
  async getImageBase64(target: string): Promise<ImageFetchResult> {
    if (!this.executor) {
      return { ok: false, base64: '', contentType: '' };
    }
    await this.whenHostReady();
    try {
      const rawResult: string = await this.executor.run(this.createImageFetchScript(target));
      const envelope: WebFetchEnvelope = JSON.parse(rawResult) as WebFetchEnvelope;
      const status: number = envelope.statusCode ? envelope.statusCode : 0;
      const body: string = envelope.body ? envelope.body : '';
      if (status >= 200 && status < 300 && body.length > 0) {
        return { ok: true, base64: body, contentType: envelope.contentType ? envelope.contentType : '' };
      }
      return { ok: false, base64: '', contentType: '' };
    } catch (error) {
      return { ok: false, base64: '', contentType: '' };
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
      const referrer: string = options?.referrer ? options.referrer : '';
      const rawResult: string = await this.executor.run(this.createFormScript('POST', requestPath, body, referrer));
      logNetwork(`POST ${requestPath} raw envelope received length=${rawResult.length} referrer=${referrer}`);
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, 'POST', options);
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

  async postJson(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    logNetwork(`POST(json) ${requestPath} start bodyLength=${body.length}`);

    if (!this.executor) {
      logNetwork(`POST(json) ${requestPath} skipped: ArkWeb host is not ready`);
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
      const referrer: string = options?.referrer ? options.referrer : '';
      const rawResult: string = await this.executor.run(this.createPostJsonScript(requestPath, body, referrer));
      logNetwork(`POST(json) ${requestPath} raw envelope received length=${rawResult.length} referrer=${referrer}`);
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, 'POST', options);
    } catch (error) {
      logNetwork(`POST(json) ${requestPath} failed before response envelope`);
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

  // 上传图片到 /uploads.json:base64 是压缩后图片字节的 base64。脚本在 host 文档内 atob 还原字节 →
  // Blob → FormData → fetch(过 CF、带 cookie)。CSRF 复用同源逻辑;不手动设 Content-Type(FormData 自带 boundary)。
  async uploadImage(base64: string, fileName: string, mimeType: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = '/uploads.json';
    logNetwork(`UPLOAD ${requestPath} start fileName=${fileName} base64Length=${base64.length}`);

    if (!this.executor) {
      logNetwork(`UPLOAD ${requestPath} skipped: ArkWeb host is not ready`);
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
      const referrer: string = options?.referrer ? options.referrer : '';
      const rawResult: string = await this.executor.run(this.createUploadScript(base64, fileName, mimeType, referrer));
      logNetwork(`UPLOAD ${requestPath} raw envelope received length=${rawResult.length}`);
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, 'POST', options);
    } catch (error) {
      logNetwork(`UPLOAD ${requestPath} failed before response envelope`);
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NETWORK_FAILURE,
          message: 'ArkWeb 上传失败。',
          requiresChallenge: false
        }
      };
    }
  }

  async putJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    logNetwork(`PUT ${requestPath} start`);

    if (!this.executor) {
      logNetwork(`PUT ${requestPath} skipped: ArkWeb host is not ready`);
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
      const referrer: string = options?.referrer ? options.referrer : '';
      const rawResult: string = await this.executor.run(this.createPutScript(requestPath, referrer));
      logNetwork(`PUT ${requestPath} raw envelope received length=${rawResult.length} referrer=${referrer}`);
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, 'PUT', options);
    } catch (error) {
      logNetwork(`PUT ${requestPath} failed before response envelope`);
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

  async putForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    return this.sendFormWithBody('PUT', path, body, options);
  }

  async deleteForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    return this.sendFormWithBody('DELETE', path, body, options);
  }

  // PUT/DELETE + form body 的公共实现(投票/撤销投票用)。与 postForm 同源取 CSRF、带 cookie,
  // 仅 HTTP method 不同。
  private async sendFormWithBody(method: string, path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    const requestPath: string = this.normalizePath(path);
    logNetwork(`${method} ${requestPath} start bodyLength=${body.length}`);

    if (!this.executor) {
      logNetwork(`${method} ${requestPath} skipped: ArkWeb host is not ready`);
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
      const referrer: string = options?.referrer ? options.referrer : '';
      const rawResult: string = await this.executor.run(this.createFormScript(method, requestPath, body, referrer));
      logNetwork(`${method} ${requestPath} raw envelope received length=${rawResult.length} referrer=${referrer}`);
      return this.convertEnvelope(requestPath, JSON.parse(rawResult) as WebFetchEnvelope, method, options);
    } catch (error) {
      logNetwork(`${method} ${requestPath} failed before response envelope`);
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

  // 二进制取图脚本:fetch 头像 → arrayBuffer → base64(分块 fromCharCode 避免大数组爆栈)。
  // 支持跨源:CDN(cdn/s3.ldstatic.com)回 ACAO=linux.do 具体源且无 Allow-Credentials,故跨源必须
  // credentials:'omit'(带 cookie 会被 CORS 拒),同源仍 include。cache:'default' 命中 webview HTTP 缓存。
  private createImageFetchScript(target: string): string {
    const encodedTarget: string = JSON.stringify(target);

    return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL(${encodedTarget}, window.location.origin);
      const sameOrigin = requestUrl.origin === window.location.origin;
      const fail = (error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0, contentType: '', body: '', errorMessage: String(error)
        }));
      };
      fetch(requestUrl.toString(), {
        credentials: sameOrigin ? 'include' : 'omit',
        cache: 'default',
        headers: { 'Accept': 'image/*' }
      }).then((response) => {
        response.arrayBuffer().then((buf) => {
          const bytes = new Uint8Array(buf);
          let binary = '';
          const chunk = 8192;
          for (let i = 0; i < bytes.length; i += chunk) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
          }
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            body: btoa(binary)
          }));
        }).catch(fail);
      }).catch(fail);
      return requestId;
    })();`;
  }

  // 表单请求脚本(POST/PUT/DELETE + application/x-www-form-urlencoded body)。method 由入参决定。
  private createFormScript(method: string, path: string, body: string, referrer: string): string {
    const encodedPath: string = JSON.stringify(path);
    const encodedBody: string = JSON.stringify(body);
    const encodedReferrer: string = JSON.stringify(referrer);
    const encodedMethod: string = JSON.stringify(method);

    // 同源脚本:先取 CSRF token(优先 /session/csrf.json,兜底页面 meta),再带头发请求。
    // cookie 靠 credentials:'include' 自动携带;结果照旧走 window.ArkDOBridge.onJsonResult。
    return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL(${encodedPath}, window.location.origin);
      let csrfSource = 'none';
      let csrfLength = 0;
      const fail = (error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0,
          contentType: '',
          body: '',
          errorMessage: String(error),
          csrfSource: csrfSource,
          csrfLength: csrfLength
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
        let csrf = token;
        csrfSource = token ? 'session' : 'none';
        if (!csrf) {
          csrf = metaCsrf();
          csrfSource = csrf ? 'meta' : 'none';
        }
        csrfLength = csrf ? csrf.length : 0;
        const fetchOptions = {
          method: ${encodedMethod},
          credentials: 'include',
          cache: 'no-store',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Accept': '*/*',
            'X-CSRF-Token': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'X-SILENCE-LOGGER': 'true',
            'Discourse-Background': 'true',
            'Discourse-Present': 'true',
            'Discourse-Logged-In': 'true'
          },
          body: ${encodedBody}
        };
        // 把 Referer 设成同源帖子页(对齐官方请求),让 CF 不再把这条后台请求当异常。
        const _ref = ${encodedReferrer};
        if (_ref) {
          fetchOptions.referrer = _ref;
          fetchOptions.referrerPolicy = 'strict-origin-when-cross-origin';
        }
        return fetch(requestUrl.toString(), fetchOptions);
      }).then((response) => {
        response.text().then((body) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            body: body,
            csrfSource: csrfSource,
            csrfLength: csrfLength
          }));
        }).catch(fail);
      }).catch(fail);
      return requestId;
    })();`;
  }

  // 发表评论/回复:POST /posts,Content-Type application/json,body 为 JSON 字符串。
  // 头部对齐抓包的关键字段:x-csrf-token、x-requested-with、discourse-present、discourse-logged-in、accept:*/*。
  // cookie 靠 credentials:'include' 自动携带;CSRF 同源优先 /session/csrf.json,兜底页面 meta。
  private createPostJsonScript(path: string, body: string, referrer: string): string {
    const encodedPath: string = JSON.stringify(path);
    const encodedBody: string = JSON.stringify(body);
    const encodedReferrer: string = JSON.stringify(referrer);

    return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL(${encodedPath}, window.location.origin);
      let csrfSource = 'none';
      let csrfLength = 0;
      const fail = (error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0,
          contentType: '',
          body: '',
          errorMessage: String(error),
          csrfSource: csrfSource,
          csrfLength: csrfLength
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
        let csrf = token;
        csrfSource = token ? 'session' : 'none';
        if (!csrf) {
          csrf = metaCsrf();
          csrfSource = csrf ? 'meta' : 'none';
        }
        csrfLength = csrf ? csrf.length : 0;
        const fetchOptions = {
          method: 'POST',
          credentials: 'include',
          cache: 'no-store',
          headers: {
            'Content-Type': 'application/json',
            'Accept': '*/*',
            'X-CSRF-Token': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'Discourse-Present': 'true',
            'Discourse-Logged-In': 'true'
          },
          body: ${encodedBody}
        };
        const _ref = ${encodedReferrer};
        if (_ref) {
          fetchOptions.referrer = _ref;
          fetchOptions.referrerPolicy = 'strict-origin-when-cross-origin';
        }
        return fetch(requestUrl.toString(), fetchOptions);
      }).then((response) => {
        response.text().then((body) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            body: body,
            csrfSource: csrfSource,
            csrfLength: csrfLength
          }));
        }).catch(fail);
      }).catch(fail);
      return requestId;
    })();`;
  }

  // 图片上传脚本:base64 → Uint8Array → Blob → FormData,POST /uploads.json。
  // 复用同源 CSRF(优先 /session/csrf.json,兜底 meta)+ credentials:'include' 带 cookie。
  // 关键:FormData 不能手动设 Content-Type,否则丢失 multipart boundary 导致后端解析失败。
  // 字段对齐 Discourse composer 上传:upload_type=composer、name、type、file。
  private createUploadScript(base64: string, fileName: string, mimeType: string, referrer: string): string {
    const encodedBase64: string = JSON.stringify(base64);
    const encodedFileName: string = JSON.stringify(fileName);
    const encodedMimeType: string = JSON.stringify(mimeType);
    const encodedReferrer: string = JSON.stringify(referrer);

    return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL('/uploads.json', window.location.origin);
      let csrfSource = 'none';
      let csrfLength = 0;
      const fail = (error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0,
          contentType: '',
          body: '',
          errorMessage: String(error),
          csrfSource: csrfSource,
          csrfLength: csrfLength
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
        let csrf = token;
        csrfSource = token ? 'session' : 'none';
        if (!csrf) {
          csrf = metaCsrf();
          csrfSource = csrf ? 'meta' : 'none';
        }
        csrfLength = csrf ? csrf.length : 0;
        const binary = atob(${encodedBase64});
        const len = binary.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) { bytes[i] = binary.charCodeAt(i); }
        const blob = new Blob([bytes], { type: ${encodedMimeType} });
        const fd = new FormData();
        fd.append('upload_type', 'composer');
        fd.append('relativePath', 'null');
        fd.append('name', ${encodedFileName});
        fd.append('type', ${encodedMimeType});
        fd.append('file', blob, ${encodedFileName});
        const fetchOptions = {
          method: 'POST',
          credentials: 'include',
          cache: 'no-store',
          headers: {
            'Accept': '*/*',
            'X-CSRF-Token': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'Discourse-Present': 'true',
            'Discourse-Logged-In': 'true'
          },
          body: fd
        };
        const _ref = ${encodedReferrer};
        if (_ref) {
          fetchOptions.referrer = _ref;
          fetchOptions.referrerPolicy = 'strict-origin-when-cross-origin';
        }
        return fetch(requestUrl.toString(), fetchOptions);
      }).then((response) => {
        response.text().then((body) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            body: body,
            csrfSource: csrfSource,
            csrfLength: csrfLength
          }));
        }).catch(fail);
      }).catch(fail);
      return requestId;
    })();`;
  }

  // discourse-reactions 的 toggle 是 PUT + 空 body。复用 POST 那套同源取 CSRF + 带 cookie 的逻辑,
  // 仅改 method 为 PUT、不带 body、不设 Content-Type(对齐官方请求的空 body)。
  private createPutScript(path: string, referrer: string): string {
    const encodedPath: string = JSON.stringify(path);
    const encodedReferrer: string = JSON.stringify(referrer);

    return `(() => {
      const requestId = '${REQUEST_ID_TOKEN}';
      const requestUrl = new URL(${encodedPath}, window.location.origin);
      let csrfSource = 'none';
      let csrfLength = 0;
      const fail = (error) => {
        window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
          statusCode: 0,
          contentType: '',
          body: '',
          errorMessage: String(error),
          csrfSource: csrfSource,
          csrfLength: csrfLength
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
        let csrf = token;
        csrfSource = token ? 'session' : 'none';
        if (!csrf) {
          csrf = metaCsrf();
          csrfSource = csrf ? 'meta' : 'none';
        }
        csrfLength = csrf ? csrf.length : 0;
        const fetchOptions = {
          method: 'PUT',
          credentials: 'include',
          cache: 'no-store',
          headers: {
            'Accept': '*/*',
            'X-CSRF-Token': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'X-SILENCE-LOGGER': 'true',
            'Discourse-Background': 'true',
            'Discourse-Present': 'true',
            'Discourse-Logged-In': 'true'
          }
        };
        const _ref = ${encodedReferrer};
        if (_ref) {
          fetchOptions.referrer = _ref;
          fetchOptions.referrerPolicy = 'strict-origin-when-cross-origin';
        }
        return fetch(requestUrl.toString(), fetchOptions);
      }).then((response) => {
        response.text().then((body) => {
          window.ArkDOBridge.onJsonResult(requestId, JSON.stringify({
            statusCode: response.status,
            contentType: response.headers.get('content-type') || '',
            body: body,
            csrfSource: csrfSource,
            csrfLength: csrfLength
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

  private convertEnvelope(path: string, envelope: WebFetchEnvelope, method: string, options?: JsonRequestOptions): NetworkResult<string> {
    // POST 专属诊断:打印本次 CSRF token 的来源与长度,用于比对成功/403 时 token 是否不同,定位 CSRF 问题。
    if (method === 'POST') {
      const csrfSource: string = envelope.csrfSource ? envelope.csrfSource : 'unknown';
      const csrfLength: number = envelope.csrfLength ? envelope.csrfLength : 0;
      logNetwork(`POST ${path} csrf source=${csrfSource} length=${csrfLength}`);
    }

    if (envelope.errorMessage) {
      logNetwork(`${method} ${path} envelope error=${envelope.errorMessage}`);
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
    logNetwork(`${method} ${path} response status=${statusCode} contentType=${contentType} bodyLength=${body.length} challenge=${challengeState}`);
    this.logResponseBody(path, contentType, body, method, statusCode, challengeState);

    if (challengeState !== ChallengeState.NONE) {
      logNetwork(`${method} ${path} requires challenge state=${challengeState}`);
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
      logNetwork(`${method} ${path} unexpected status=${statusCode}`);
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

    logNetwork(`${method} ${path} success status=${statusCode} bodyLength=${body.length}`);
    return result;
  }

  private logResponseBody(path: string, contentType: string, body: string, method: string, statusCode: number, challengeState: ChallengeState): void {
    // 成功的 JSON 响应体积大且无排查价值(status 行已记 bodyLength);仅在挑战/错误/异常响应时转储。
    if (!this.shouldLogResponseBody(contentType, body, statusCode, challengeState)) {
      return;
    }

    const formattedBody: string = this.formatBodyForLog(contentType, body);
    // 详细日志开关(设置里可开):开启时完整转储不截断,用于深挖某个具体响应;默认截断控制体积。
    const loggedBody: string = FileLogger.isVerbose() || formattedBody.length <= BODY_LOG_MAX_CHARS
      ? formattedBody
      : `${formattedBody.substring(0, BODY_LOG_MAX_CHARS)}...(truncated ${formattedBody.length - BODY_LOG_MAX_CHARS} chars)`;
    const chunkCount: number = Math.max(1, Math.ceil(loggedBody.length / BODY_LOG_CHUNK_SIZE));

    logNetworkBody(`${method} ${path} body begin contentType=${contentType} rawLength=${body.length} loggedLength=${loggedBody.length} chunks=${chunkCount}`);
    if (loggedBody.length === 0) {
      logNetworkBody(`${method} ${path} body chunk 1/1: `);
    }

    for (let start: number = 0; start < loggedBody.length; start += BODY_LOG_CHUNK_SIZE) {
      const chunkIndex: number = Math.floor(start / BODY_LOG_CHUNK_SIZE) + 1;
      const chunk: string = loggedBody.substring(start, start + BODY_LOG_CHUNK_SIZE);
      logNetworkBody(`${method} ${path} body chunk ${chunkIndex}/${chunkCount}: ${chunk}`);
    }
    logNetworkBody(`${method} ${path} body end`);
  }

  // 是否值得转储响应体:挑战页/HTTP 错误/成功但非 JSON 的意外响应(可能是未识别的软拦截页)才留;
  // 成功 JSON 和空体(如 timings 上报)一律跳过——这两类占日志体积绝大头且无排查价值。
  private shouldLogResponseBody(contentType: string, body: string, statusCode: number, challengeState: ChallengeState): boolean {
    if (FileLogger.isVerbose()) {
      return true;
    }
    if (challengeState !== ChallengeState.NONE || statusCode >= 400) {
      return true;
    }
    if (body.length === 0) {
      return false;
    }
    return contentType.toLowerCase().indexOf('application/json') < 0;
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
