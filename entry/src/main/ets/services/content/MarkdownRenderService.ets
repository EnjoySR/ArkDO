import webview from '@ohos.web.webview';
import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][MarkdownRender]';
// 离屏页里 window.ArkDOMd 的方法名(供 JS 回调)。
const BRIDGE_NAME: string = 'ArkDOMd';
// 单次编译兜底超时:超时即失败,预览退回显示提示。
const RENDER_TIMEOUT_MS: number = 5000;

class PendingRender {
  resolve: (html: string) => void;
  reject: (reason: Object) => void;
  timeoutId: number;

  constructor(resolve: (html: string) => void, reject: (reason: Object) => void, timeoutId: number) {
    this.resolve = resolve;
    this.reject = reject;
    this.timeoutId = timeoutId;
  }
}

// 暴露给离屏页 JS 的回调对象。页面编译完成调 onResult / 出错调 onError。
class MarkdownBridgeProxy {
  private service: MarkdownRenderService;

  constructor(service: MarkdownRenderService) {
    this.service = service;
  }

  onResult(requestId: string, html: string): void {
    this.service.handleResult(requestId, html);
  }

  onError(requestId: string, message: string): void {
    this.service.handleError(requestId, message);
  }
}

// 离屏 markdown 编译引擎:一个只加载本地 render.html(markdown-it)的 Web,raw → HTML 字符串。
// 与 math 引擎同架构,但更轻:回传纯字符串,无出图/缓存。由持有它的页面内嵌隐藏 Web 驱动其生命周期
// (createProxy 绑回调、onPageEnd 调 attachController、页面销毁调 detach),非全局单例。
export class MarkdownRenderService {
  private controller?: webview.WebviewController;
  private proxy: MarkdownBridgeProxy = new MarkdownBridgeProxy(this);
  private ready: boolean = false;
  private seq: number = 0;
  private readonly pending: Map<string, PendingRender> = new Map();
  // 就绪前入队的请求,attachController 后统一下发。
  private readonly queued: Array<() => void> = [];

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
    Log.i(`${LOG_TAG} host ready queued=${this.queued.length}`);
    const waiters: Array<() => void> = this.queued.splice(0, this.queued.length);
    for (let i: number = 0; i < waiters.length; i++) {
      waiters[i]();
    }
  }

  // 页面销毁时调用:置空控制器并把仍在等待的请求全部失败掉,避免永久悬住。
  detach(): void {
    this.controller = undefined;
    this.ready = false;
    const ids: string[] = Array.from(this.pending.keys());
    for (let i: number = 0; i < ids.length; i++) {
      this.handleError(ids[i], 'markdown host detached');
    }
    this.queued.splice(0, this.queued.length);
  }

  // 编译一段 markdown 为 HTML。待就绪后下发 runJavaScript,页面回调再 resolve。
  render(raw: string): Promise<string> {
    return new Promise<string>((resolve: (html: string) => void, reject: (reason: Object) => void) => {
      const dispatch = (): void => {
        if (!this.controller) {
          reject(new Error('markdown host not ready'));
          return;
        }
        const requestId: string = `md${this.seq}`;
        this.seq++;
        const timeoutId: number = setTimeout(() => {
          this.handleError(requestId, 'render timeout');
        }, RENDER_TIMEOUT_MS);
        this.pending.set(requestId, new PendingRender(resolve, reject, timeoutId));
        const script: string = `renderMarkdown(${JSON.stringify(requestId)},${JSON.stringify(raw)})`;
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
  }

  handleResult(requestId: string, html: string): void {
    const entry: PendingRender | undefined = this.pending.get(requestId);
    if (!entry) {
      return;
    }
    this.pending.delete(requestId);
    clearTimeout(entry.timeoutId);
    entry.resolve(html);
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
}
