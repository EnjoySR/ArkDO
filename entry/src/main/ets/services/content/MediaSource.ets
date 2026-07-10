import { AppConstants } from '../../common/constants/AppConstants';

// 帖子媒体源分流。linux.do 自家上传件(/uploads/short-url/*.xz)被 CF 挡且 302 到跨源 CDN,AVPlayer/http
// 都拿不到字节,唯有 host webview 下载委托能过盾,须先下到沙箱再播;其余外站绝对直链(第三方文件床等)
// 是普通公开文件,AVPlayer / Video 组件直接喂 URL 流式播放即可,不必也不该走下载委托(会因跨源无上下文而挂死)。
export class MediaSource {
  // 该媒体 URL 是否需要走 host webview 下载委托过盾。判定:属于 linux.do 源(与 BASE_URL 同域)才需要;
  // 其它绝对 http(s) URL 直连。空串或相对路径 / 其它 scheme 一律按需要过盾处理——相对路径几乎只可能是
  // linux.do 自家资源,保守走下载委托更安全。
  static needsDownloadBridge(url: string): boolean {
    const src: string = url ? url.trim() : '';
    if (src.length === 0) {
      return true;
    }
    const lower: string = src.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return MediaSource.hostOf(lower) === MediaSource.hostOf(AppConstants.BASE_URL.toLowerCase());
    }
    return true;
  }

  // 从绝对 URL 抽出主机名(去 scheme、路径与端口),用于同域判定。
  private static hostOf(url: string): string {
    const schemeEnd: number = url.indexOf('://');
    const start: number = schemeEnd >= 0 ? schemeEnd + 3 : 0;
    let end: number = url.length;
    const slash: number = url.indexOf('/', start);
    if (slash >= 0) {
      end = slash;
    }
    const authority: string = url.substring(start, end);
    const colon: number = authority.indexOf(':');
    return colon >= 0 ? authority.substring(0, colon) : authority;
  }
}
