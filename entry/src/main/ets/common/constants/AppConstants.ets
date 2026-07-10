export class AppConstants {
  static readonly APP_NAME: string = 'ArkDO';
  static readonly BASE_URL: string = 'https://linux.do';
  // host webview 引导页:桥只需一个 linux.do 同源文档(定 origin、带 cookie、供注入 fetch),
  // 无需首页那套重型 SPA。改加载极小的 /session/csrf.json,把冷启动首屏就绪从 ~30s 砍到建连级。
  // 同源、必然存在、顺带预热 CSRF;CF 挡时照样返回挑战 HTML 跑 JS 种 cf_clearance,过盾逻辑不变。
  static readonly HOST_BOOTSTRAP_URL: string = 'https://linux.do/session/csrf.json';
  // connect.linux.do:跨域(与 BASE_URL 不同源),经 SSO 复用 linux.do 会话自动登录。等级进度页专用。
  static readonly CONNECT_URL: string = 'https://connect.linux.do/';
  static readonly LOGIN_PATH: string = '/login';
  static readonly LOGIN_URL: string = 'https://linux.do/login';
  static readonly CHALLENGE_PATH: string = '/challenge';
  static readonly CHALLENGE_URL: string = 'https://linux.do/challenge';
  static readonly DEFAULT_TIMEOUT_MS: number = 15000;
  // host webview 因 session 变化被 loadUrl 重载时，注入式 fetch 会排队等待其 onPageEnd。
  // 该超时用于兜底：万一 onPageEnd 因异常始终不触发，等待者也不会永久悬住。
  static readonly HOST_RELOAD_READY_TIMEOUT_MS: number = 5000;
  // Cloudflare 会校验 UA，且 cf_clearance 与请求时的 UA 绑定。验证页与后台请求页必须使用
  // 完全一致的真实浏览器 UA，否则验证页拿到的 cf_clearance 在后台 fetch 时会被判定失效。
  static readonly DEFAULT_USER_AGENT: string =
    'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
}
