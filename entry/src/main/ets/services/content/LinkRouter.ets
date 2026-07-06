import { AppConstants } from '../../common/constants/AppConstants';

export enum LinkTargetKind {
  // 站内帖子链接:提取 topicId 后跳原生详情页,不进通用 WebView。
  TOPIC = 'topic',
  // 站内附件下载链接(/uploads/):触发原生下载,不进 WebView(否则空白页)。
  DOWNLOAD = 'download',
  // 其他一切链接(外站、站内非帖子页):进通用 WebView。
  WEB = 'web'
}

export interface LinkTarget {
  kind: LinkTargetKind;
  url: string;
  topicId?: number;
  postNumber?: number;
}

// 点击链接前的统一路由判断:识别站内帖子链接,让详情页走原生跳转;其余交给通用 WebView。
export class LinkRouter {
  // 站内帖子 URL:https://linux.do/t/<slug 可选>/<topicId>[/<postNumber>]
  // slug 段可有可无(旧链接可能是 /t/12345);topicId 必为数字,postNumber 可选。
  static resolve(rawUrl: string): LinkTarget {
    const url: string = rawUrl ? rawUrl.trim() : '';
    if (url.length === 0) {
      return { kind: LinkTargetKind.WEB, url };
    }

    if (LinkRouter.isSameHost(url)) {
      const path: string = LinkRouter.pathOf(url);

      // 附件下载:/uploads/short-url/... 或 /uploads/default/...。服务端返回 Content-Disposition,
      // 用 WebView 打开只会空白,应触发原生下载(带登录 Cookie)。
      if (/^\/uploads\//i.test(path)) {
        return { kind: LinkTargetKind.DOWNLOAD, url };
      }

      const match: RegExpMatchArray | null = path.match(/^\/t\/(?:[^\/]+\/)?(\d+)(?:\/(\d+))?/);
      if (match) {
        const topicId: number = parseInt(match[1], 10);
        if (!isNaN(topicId) && topicId > 0) {
          const target: LinkTarget = {
            kind: LinkTargetKind.TOPIC,
            url,
            topicId
          };
          if (match[2]) {
            const postNumber: number = parseInt(match[2], 10);
            if (!isNaN(postNumber) && postNumber > 0) {
              target.postNumber = postNumber;
            }
          }
          return target;
        }
      }
    }

    return { kind: LinkTargetKind.WEB, url };
  }

  private static isSameHost(url: string): boolean {
    const host: string = LinkRouter.hostOf(url);
    if (host.length === 0) {
      return false;
    }
    const baseHost: string = LinkRouter.hostOf(AppConstants.BASE_URL);
    return host === baseHost;
  }

  private static hostOf(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/?#]+)/i);
    return match ? match[1].toLowerCase() : '';
  }

  private static pathOf(url: string): string {
    const withoutScheme: string = url.replace(/^https?:\/\/[^\/?#]+/i, '');
    const cut: number = withoutScheme.search(/[?#]/);
    const path: string = cut >= 0 ? withoutScheme.substring(0, cut) : withoutScheme;
    return path.length > 0 ? path : '/';
  }
}
