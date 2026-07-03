export class AppConstants {
  static readonly APP_NAME: string = 'ArkDO';
  static readonly BASE_URL: string = 'https://linux.do';
  static readonly LOGIN_PATH: string = '/login';
  static readonly LOGIN_URL: string = 'https://linux.do/login';
  static readonly CHALLENGE_PATH: string = '/challenge';
  static readonly CHALLENGE_URL: string = 'https://linux.do/challenge';
  static readonly DEFAULT_TIMEOUT_MS: number = 15000;
  // Cloudflare 会校验 UA，且 cf_clearance 与请求时的 UA 绑定。验证页与后台请求页必须使用
  // 完全一致的真实浏览器 UA，否则验证页拿到的 cf_clearance 在后台 fetch 时会被判定失效。
  static readonly DEFAULT_USER_AGENT: string =
    'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
}
