import { AppConstants } from '../../common/constants/AppConstants';

export enum LinkTargetKind {
  // 站内帖子链接:提取 topicId 后跳原生详情页,不进通用 WebView。
  TOPIC = 'topic',
  // 站内附件下载链接(/uploads/):触发原生下载,不进 WebView(否则空白页)。
  DOWNLOAD = 'download',
  // 站内用户主页链接(/u/<username>,正文里的 @提及 就是这个):跳原生他人主页。
  USER = 'user',
  // 其他一切链接(外站、站内非帖子页):进通用 WebView。
  WEB = 'web'
}

export interface LinkTarget {
  kind: LinkTargetKind;
  url: string;
  topicId?: number;
  postNumber?: number;
  username?: string;
}

// /u/ 下并非用户主页的保留段(注册激活、改密、邮箱确认等),这些仍走 WebView。
const USER_PATH_RESERVED: string[] = [
  'account-created', 'activate-account', 'password-reset', 'confirm-email-token',
  'authorize-email', 'admin-login', 'email-login', 'second-factor',
  'confirm-old-email', 'confirm-new-email'
];

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

      // 用户主页:/u/<username>[/summary|/activity|...]。正文的 @提及 (<a class="mention" href="/u/x">)
      // 走的就是这条,应跳原生他人主页而不是 WebView。
      const userMatch: RegExpMatchArray | null = path.match(/^\/u\/([^\/?#]+)/i);
      if (userMatch) {
        const username: string = LinkRouter.decodeSegment(userMatch[1]);
        if (LinkRouter.isUsername(username)) {
          return { kind: LinkTargetKind.USER, url, username };
        }
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

  // Discourse 用户名字符集:字母数字加 . _ -。保留段(激活/改密链接)不算用户名。
  private static isUsername(segment: string): boolean {
    if (segment.length === 0 || !/^[A-Za-z0-9._-]+$/.test(segment)) {
      return false;
    }
    return USER_PATH_RESERVED.indexOf(segment.toLowerCase()) < 0;
  }

  private static decodeSegment(segment: string): string {
    try {
      return decodeURIComponent(segment);
    } catch (err) {
      return segment;
    }
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
