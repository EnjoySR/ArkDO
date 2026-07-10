import webview from '@ohos.web.webview';
import { image } from '@kit.ImageKit';
import { buffer } from '@kit.ArkTS';
import { display } from '@kit.ArkUI';
import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][MathRender]';
// 离屏页里 window.ArkDOMath 的方法名(供 JS 回调)。
const BRIDGE_NAME: string = 'ArkDOMath';
// 单条公式渲染兜底超时:超时即失败,渲染层退回显示裸 LaTeX。
const RENDER_TIMEOUT_MS: number = 8000;
// 引擎空闲多久后销毁(离开含公式帖子后不立刻拆,避免来回进出频繁重建)。
const IDLE_DISPOSE_MS: number = 20000;
// PixelMap LRU 上限:数学重贴也就几十个公式,足够。
const CACHE_CAPACITY: number = 128;
// AppStorage 门控 key:refCount>0 时置 true,RootTabPage 据此挂载/卸载离屏 Web。
export const MATH_HOST_ACTIVE_KEY: string = 'mathHostActive';

// 一条公式的渲染产物。cssWidth/cssHeight 为逻辑尺寸(vp),pixelMap 是 dpr 倍的清晰位图;
// depth 是基线以下的下沉量(vp),供行内 ImageSpan 对齐参考。
export interface MathImage {
  pixelMap: image.PixelMap;
  cssWidth: number;
  cssHeight: number;
  depth: number;
}

class PendingRender {
  resolve: (value: MathImage) => void;
  reject: (reason: Object) => void;
  timeoutId: number;

  constructor(resolve: (value: MathImage) => void, reject: (reason: Object) => void, timeoutId: number) {
    this.resolve = resolve;
    this.reject = reject;
    this.timeoutId = timeoutId;
  }
}

// 暴露给离屏页 JS 的回调对象。页面出图后调用 onResult / 出错调用 onError。
class MathBridgeProxy {
  private service: MathRenderService;

  constructor(service: MathRenderService) {
    this.service = service;
  }

  onResult(requestId: string, pngBase64: string, width: number, height: number, depth: number): void {
    this.service.handleResult(requestId, pngBase64, width, height, depth);
  }

  onError(requestId: string, message: string): void {
    this.service.handleError(requestId, message);
  }
}

// 单例离屏公式引擎:一个只加载本地 KaTeX/MathJax 页的 Web,LaTeX -> PNG -> PixelMap,LRU 缓存。
// 与网络 host(ArkWebHost)完全分家:不随 session 重载、不在网络路径上、懒挂载空闲卸载。
export class MathRenderService {
  private static instance?: MathRenderService;

  private controller?: webview.WebviewController;
  private proxy: MathBridgeProxy = new MathBridgeProxy(this);
  private ready: boolean = false;
  private seq: number = 0;
  private dpr: number = 2;
  private readonly pending: Map<string, PendingRender> = new Map();
  // 已就绪前入队的请求,attachController 后统一下发。
  private readonly queued: Array<() => void> = [];
  // key -> 产物 的 LRU;key -> 进行中 Promise 的去重表。
  private readonly cache: Map<string, MathImage> = new Map();
  private readonly inflight: Map<string, Promise<MathImage>> = new Map();
  private refCount: number = 0;
  private idleTimer: number = -1;

  static getInstance(): MathRenderService {
    if (!MathRenderService.instance) {
      MathRenderService.instance = new MathRenderService();
    }
    return MathRenderService.instance;
  }

  // 缓存 key:行内/块级 + dpr + 源码。行内与块级 displayMode 不同,须分开缓存。
  static keyOf(latex: string, display: boolean, dpr: number): string {
    return `${display ? 'd' : 'i'}|${dpr}|${latex}`;
  }

  createProxy(controller: webview.WebviewController): JavaScriptProxy {
    return {
      object: this.proxy,
      name: BRIDGE_NAME,
      methodList: ['onResult', 'onError'],
      controller: controller
    };
  }

  // 离屏页 onPageEnd 调用:控制器就绪,放行排队请求。
  attachController(controller: webview.WebviewController): void {
    this.controller = controller;
    this.ready = true;
    try {
      this.dpr = Math.min(3, Math.max(1, Math.round(display.getDefaultDisplaySync().densityPixels)));
    } catch (error) {
      this.dpr = 2;
    }
    Log.i(`${LOG_TAG} host ready dpr=${this.dpr} queued=${this.queued.length}`);
    const waiters: Array<() => void> = this.queued.splice(0, this.queued.length);
    for (let i: number = 0; i < waiters.length; i++) {
      waiters[i]();
    }
  }

  private detachController(): void {
    this.controller = undefined;
    this.ready = false;
    // 卸载时把仍在等待的请求全部失败掉,避免永久悬住。
    const ids: string[] = Array.from(this.pending.keys());
    for (let i: number = 0; i < ids.length; i++) {
      this.handleError(ids[i], 'math host detached');
    }
    this.queued.splice(0, this.queued.length);
  }

  // 帖子进入时 retain / 离开时 release。refCount 0->1 触发挂载,回到 0 后延迟卸载。
  retain(): void {
    this.refCount++;
    if (this.idleTimer >= 0) {
      clearTimeout(this.idleTimer);
      this.idleTimer = -1;
    }
    AppStorage.setOrCreate(MATH_HOST_ACTIVE_KEY, true);
  }

  release(): void {
    this.refCount = Math.max(0, this.refCount - 1);
    if (this.refCount > 0) {
      return;
    }
    if (this.idleTimer >= 0) {
      clearTimeout(this.idleTimer);
    }
    this.idleTimer = setTimeout(() => {
      this.idleTimer = -1;
      if (this.refCount === 0) {
        this.detachController();
        AppStorage.setOrCreate(MATH_HOST_ACTIVE_KEY, false);
        Log.i(`${LOG_TAG} host disposed (idle)`);
      }
    }, IDLE_DISPOSE_MS);
  }

  getDpr(): number {
    return this.dpr;
  }

  getCached(latex: string, display: boolean): MathImage | undefined {
    return this.cache.get(MathRenderService.keyOf(latex, display, this.dpr));
  }

  // 渲染一条公式。命中缓存/进行中则复用;否则待就绪后下发 runJavaScript,页面回调再解码成 PixelMap。
  render(latex: string, display: boolean): Promise<MathImage> {
    const key: string = MathRenderService.keyOf(latex, display, this.dpr);
    const cached: MathImage | undefined = this.cache.get(key);
    if (cached) {
      return Promise.resolve(cached);
    }
    const pendingInflight: Promise<MathImage> | undefined = this.inflight.get(key);
    if (pendingInflight) {
      return pendingInflight;
    }

    const promise: Promise<MathImage> = new Promise<MathImage>(
      (resolve: (value: MathImage) => void, reject: (reason: Object) => void) => {
        const dispatch = (): void => {
          if (!this.controller) {
            reject(new Error('math host not ready'));
            return;
          }
          const requestId: string = `m${this.seq}`;
          this.seq++;
          const timeoutId: number = setTimeout(() => {
            this.handleError(requestId, 'render timeout');
          }, RENDER_TIMEOUT_MS);
          this.pending.set(requestId, new PendingRender(resolve, reject, timeoutId));
          const script: string =
            `renderMath(${JSON.stringify(requestId)},${JSON.stringify(latex)},${display ? 'true' : 'false'},${this.dpr})`;
          try {
            this.controller.runJavaScript(script).catch(() => {
              this.handleError(requestId, 'runJavaScript failed');
            });
          } catch (error) {
            this.handleError(requestId, 'runJavaScript threw');
          }
        };

        if (this.ready) {
          dispatch();
        } else {
          this.queued.push(dispatch);
        }
      });

    // inflight 记录 key(而非 requestId),以便同一公式并发请求去重。
    const tracked: Promise<MathImage> = promise
      .then((img: MathImage) => {
        this.inflight.delete(key);
        this.putCache(key, img);
        return img;
      })
      .catch((reason: Object) => {
        this.inflight.delete(key);
        throw reason as Error;
      });
    this.inflight.set(key, tracked);
    return tracked;
  }

  handleResult(requestId: string, pngBase64: string, width: number, height: number, depth: number): void {
    const entry: PendingRender | undefined = this.pending.get(requestId);
    if (!entry) {
      return;
    }
    this.pending.delete(requestId);
    clearTimeout(entry.timeoutId);
    try {
      const bytes: buffer.Buffer = buffer.from(pngBase64, 'base64');
      const ab: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length);
      const source: image.ImageSource = image.createImageSource(ab);
      source.createPixelMap()
        .then((pm: image.PixelMap) => {
          entry.resolve({ pixelMap: pm, cssWidth: width, cssHeight: height, depth: depth });
        })
        .catch((error: Object) => {
          Log.i(`${LOG_TAG} createPixelMap failed ${JSON.stringify(error)}`);
          entry.reject(error);
        });
    } catch (error) {
      Log.i(`${LOG_TAG} decode png failed ${JSON.stringify(error)}`);
      entry.reject(error as Object);
    }
  }

  handleError(requestId: string, message: string): void {
    const entry: PendingRender | undefined = this.pending.get(requestId);
    if (!entry) {
      return;
    }
    this.pending.delete(requestId);
    clearTimeout(entry.timeoutId);
    Log.i(`${LOG_TAG} render failed id=${requestId} msg=${message}`);
    entry.reject(new Error(message));
  }

  private putCache(key: string, img: MathImage): void {
    this.cache.set(key, img);
    if (this.cache.size <= CACHE_CAPACITY) {
      return;
    }
    // Map 迭代按插入序:删最旧一个即 LRU 近似(不追求命中后置顶,数学场景足够)。
    const oldest: string | undefined = this.cache.keys().next().value;
    if (oldest !== undefined) {
      this.cache.delete(oldest);
    }
  }
}
