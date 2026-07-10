import { Log } from '../logging/Log';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { ArkWebNetworkBridge, ImageFetchResult } from './ArkWebNetworkBridge';

const LOG_TAG: string = '[ArkDO][Avatar]';
// 并发取图上限:头像一次可能几十张,限流避免瞬间灌爆 host webview 的 runJavaScript 通道。
const MAX_CONCURRENCY: number = 5;
// 已解码 PixelMap 内存缓存上限:超出按插入序淘汰最旧(仅丢引用不 release,防止仍在显示的图被销毁崩溃)。
const MAX_CACHE_ENTRIES: number = 400;

/**
 * 头像 PixelMap 缓存。原生 Image 走系统 netstack 会被 SNI 封锁(TLS 握手 RST),
 * 故头像统一经 host webview(能藏 SNI 过盾)取字节,解码成 PixelMap 供 UserAvatar 显示。
 * 单例:UserAvatar 深层嵌套拿不到注入的 bridge,由 RootTabPage 在 host 就绪处 attachBridge 一次。
 */
export class AvatarImageCache {
  private static instance: AvatarImageCache = new AvatarImageCache();

  static getInstance(): AvatarImageCache {
    return AvatarImageCache.instance;
  }

  private bridge?: ArkWebNetworkBridge;
  private cache: Map<string, image.PixelMap> = new Map();
  private inflight: Map<string, Promise<image.PixelMap | undefined>> = new Map();
  private active: number = 0;
  private queue: Array<() => void> = [];

  /** 注入 host webview 的 bridge(唯一联通 host 文档的实例)。在 host 就绪处调用一次。 */
  attachBridge(bridge: ArkWebNetworkBridge): void {
    this.bridge = bridge;
  }

  /** 同步命中已解码缓存(供首帧直接显示,避免闪烁)。 */
  getCached(url: string): image.PixelMap | undefined {
    return this.cache.get(url);
  }

  /** 取头像 PixelMap:命中缓存直接返回;否则经 host webview 取字节并解码。失败返回 undefined。 */
  async load(url: string): Promise<image.PixelMap | undefined> {
    if (url.length === 0) {
      return undefined;
    }
    const cached: image.PixelMap | undefined = this.cache.get(url);
    if (cached) {
      return cached;
    }
    const pending: Promise<image.PixelMap | undefined> | undefined = this.inflight.get(url);
    if (pending) {
      return pending;
    }
    const task: Promise<image.PixelMap | undefined> = this.fetchAndDecode(url);
    this.inflight.set(url, task);
    try {
      return await task;
    } finally {
      this.inflight.delete(url);
    }
  }

  private async fetchAndDecode(url: string): Promise<image.PixelMap | undefined> {
    if (!this.bridge) {
      return undefined;
    }
    await this.acquire();
    try {
      // 直接把绝对 URL 交给 host 文档 fetch:同源(/user_avatar 等)与跨源 CDN(cdn/s3.ldstatic.com,
      // 回 ACAO=linux.do)都能读到字节,跨源分支在 bridge 脚本里用 credentials:'omit' 过 CORS。
      const result: ImageFetchResult = await this.bridge.getImageBase64(url);
      if (!result.ok) {
        return undefined;
      }
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(result.base64, util.Type.BASIC);
      // 切出精确字节区间再交给解码器,避免 base64 解码结果带偏移/多余尾字节。
      const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const source: image.ImageSource = image.createImageSource(buffer);
      const pixelMap: image.PixelMap = await source.createPixelMap();
      source.release();
      this.put(url, pixelMap);
      return pixelMap;
    } catch (error) {
      Log.i(`${LOG_TAG} decode failed url=${url} err=${JSON.stringify(error)}`);
      return undefined;
    } finally {
      this.release();
    }
  }

  private put(url: string, pixelMap: image.PixelMap): void {
    if (this.cache.size >= MAX_CACHE_ENTRIES) {
      const oldest: string | undefined = this.cache.keys().next().value;
      if (oldest !== undefined) {
        // 只移除引用不 release：被淘汰的图可能仍绑定在某个 Image 上,release 会崩溃,交给 GC。
        this.cache.delete(oldest);
      }
    }
    this.cache.set(url, pixelMap);
  }

  private acquire(): Promise<void> {
    if (this.active < MAX_CONCURRENCY) {
      this.active += 1;
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.queue.push((): void => {
        this.active += 1;
        resolve();
      });
    });
  }

  private release(): void {
    this.active -= 1;
    const next: (() => void) | undefined = this.queue.shift();
    if (next) {
      next();
    }
  }
}
