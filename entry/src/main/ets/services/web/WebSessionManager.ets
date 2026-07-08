import { Log } from '../logging/Log';
import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';

const LOG_TAG: string = '[ArkDO][WebSession]';

export interface CookiePresenceSnapshot {
  hasCookie: boolean;
  headerLength: number;
}

export class WebSessionManager {
  static configureCookieAccess(source: string): void {
    try {
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
      Log.i(`${LOG_TAG} cookie access enabled source=${source} thirdParty=${webview.WebCookieManager.isThirdPartyCookieAllowed()}`);
    } catch (error) {
      Log.i(`${LOG_TAG} cookie access configure failed source=${source} error=${JSON.stringify(error)}`);
    }
  }

  static applyUserAgent(controller: webview.WebviewController, source: string): void {
    try {
      controller.setCustomUserAgent(AppConstants.DEFAULT_USER_AGENT);
      Log.i(`${LOG_TAG} user agent applied source=${source} ua=${AppConstants.DEFAULT_USER_AGENT}`);
    } catch (error) {
      Log.i(`${LOG_TAG} user agent apply failed source=${source} error=${JSON.stringify(error)}`);
    }
  }

  static saveCookies(source: string): void {
    webview.WebCookieManager.saveCookieAsync()
      .then(() => {
        Log.i(`${LOG_TAG} cookie save success source=${source}`);
      })
      .catch((error: Object) => {
        Log.i(`${LOG_TAG} cookie save failed source=${source} error=${JSON.stringify(error)}`);
      });
  }

  static hasCookie(cookieName: string): boolean {
    return WebSessionManager.getCookiePresenceSnapshot(cookieName).hasCookie;
  }

  static getCookiePresenceSnapshot(cookieName: string): CookiePresenceSnapshot {
    try {
      const cookieHeader: string = webview.WebCookieManager.fetchCookieSync(AppConstants.BASE_URL, false);
      return {
        hasCookie: WebSessionManager.containsCookie(cookieHeader, cookieName),
        headerLength: cookieHeader.length
      };
    } catch (error) {
      return {
        hasCookie: false,
        headerLength: 0
      };
    }
  }

  static hasCfClearance(): boolean {
    return WebSessionManager.hasCookie('cf_clearance');
  }

  // 取 cf_clearance 的值(不含名字)。挑战弹层用它做"值变化"判定:过期失效的旧 cookie 仍残留在
  // cookie 仓里,靠"存在性"会被误判为已解决而秒关弹层;只有值发生变化才是 CF 真的发了新通行证。
  static getCfClearanceValue(): string {
    try {
      const cookieHeader: string = webview.WebCookieManager.fetchCookieSync(AppConstants.BASE_URL, false);
      const prefix: string = 'cf_clearance=';
      const parts: string[] = cookieHeader.split(';');
      for (let index: number = 0; index < parts.length; index++) {
        const trimmed: string = parts[index].trim();
        if (trimmed.startsWith(prefix)) {
          return trimmed.substring(prefix.length);
        }
      }
      return '';
    } catch (error) {
      return '';
    }
  }

  private static containsCookie(cookieHeader: string, cookieName: string): boolean {
    const prefix: string = `${cookieName}=`;
    const parts: string[] = cookieHeader.split(';');
    for (let index: number = 0; index < parts.length; index++) {
      if (parts[index].trim().startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }
}
