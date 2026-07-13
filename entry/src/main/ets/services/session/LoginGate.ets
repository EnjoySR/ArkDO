import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][LoginGate]';
const STORAGE_KEY_LOGGED_IN: string = 'arkdoIsLoggedIn';

export type RequireLoginListener = () => void;

// 登录闸门:全局登录态(AppStorage) + 「请求登录」事件总线。
// 各处写操作(点赞/评论/投票/收藏/通知已读等)在发网络请求前调 ensureLoggedIn():
// 已登录放行;未登录广播一次请求 → RootTabPage 弹出登录页,并返回 false 让调用方就地拦截,不再发请求。
// 登录态真源仍是 RootTabPage 的会话检查,这里只做一份可全局读取的镜像(深层 NavDestination 够不到 @Prop)。
export class LoginGate {
  private static listeners: Map<number, RequireLoginListener> = new Map();
  private static nextListenerId: number = 0;

  // 由 RootTabPage 在 /session/current.json 检查「成功」后同步写入(CF 盾/网络失败不改,保持上次态)。
  static setLoggedIn(loggedIn: boolean): void {
    AppStorage.setOrCreate<boolean>(STORAGE_KEY_LOGGED_IN, loggedIn);
  }

  static isLoggedIn(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEY_LOGGED_IN) === true;
  }

  // 写操作前置闸门:已登录返回 true 放行;未登录返回 false 并请求弹登录页。
  static ensureLoggedIn(): boolean {
    if (LoginGate.isLoggedIn()) {
      return true;
    }
    Log.i(`${LOG_TAG} write action blocked: not logged in, request login sheet`);
    LoginGate.requestLogin();
    return false;
  }

  static requestLogin(): void {
    const listeners: RequireLoginListener[] = [];
    LoginGate.listeners.forEach((listener: RequireLoginListener) => {
      listeners.push(listener);
    });
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (error) {
        Log.i(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }

  static subscribe(listener: RequireLoginListener): () => void {
    const listenerId: number = LoginGate.nextListenerId;
    LoginGate.nextListenerId++;
    LoginGate.listeners.set(listenerId, listener);
    return () => {
      LoginGate.listeners.delete(listenerId);
    };
  }
}
