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
      console.info(`${LOG_TAG} cookie access enabled source=${source} thirdParty=${webview.WebCookieManager.isThirdPartyCookieAllowed()}`);
    } catch (error) {
      console.info(`${LOG_TAG} cookie access configure failed source=${source} error=${JSON.stringify(error)}`);
    }
  }

  static saveCookies(source: string): void {
    webview.WebCookieManager.saveCookieAsync()
      .then(() => {
        console.info(`${LOG_TAG} cookie save success source=${source}`);
      })
      .catch((error: Object) => {
        console.info(`${LOG_TAG} cookie save failed source=${source} error=${JSON.stringify(error)}`);
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
