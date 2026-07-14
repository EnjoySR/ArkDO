import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][LoginGate]';
const STORAGE_KEY_LOGGED_IN: string = 'arkdoIsLoggedIn';

export type RequireLoginListener = () => void;
// 登录态由「未登录」翻成「已登录」时触发:供已在场的页面(如详情页)补做只在登录后才能起的动作。
export type LoginStateListener = () => void;

// 登录闸门:全局登录态(持久化 AppStorage) + 「请求登录」事件总线。
// 各处写操作(点赞/评论/投票/收藏/通知已读等)在发网络请求前调 ensureLoggedIn():
// 已登录放行;未登录广播一次请求 → RootTabPage 弹出登录页,并返回 false 让调用方就地拦截,不再发请求。
// 登录态真源仍是 RootTabPage 的会话检查,这里只做一份可全局读取的镜像(深层 NavDestination 够不到 @Prop)。
export class LoginGate {
  private static listeners: Map<number, RequireLoginListener> = new Map();
  private static nextListenerId: number = 0;
  private static loginStateListeners: Map<number, LoginStateListener> = new Map();
  private static nextLoginStateListenerId: number = 0;

  // 由 EntryAbility.onCreate 在任何页面读取 AppStorage 之前调用一次:把登录态镜像双向绑定到磁盘。
  // 冷启动即从磁盘恢复上次「检查成功」的登录态,否则默认 false → 已登录用户在首个 /session/current.json
  // 回来前(尤其命中 CF 盾时更久)被误判为游客:阅读计时器不启动(已读丢失)、写操作被静默拦截并强弹登录页。
  static initPersist(): void {
    PersistentStorage.persistProp<boolean>(STORAGE_KEY_LOGGED_IN, false);
  }

  // 由 RootTabPage 在 /session/current.json 检查「成功」后同步写入(CF 盾/网络失败不改,保持上次态)。
  // 从非登录翻成登录时广播一次:让已在场页面补启登录后才可用的逻辑(如详情页阅读追踪)。
  static setLoggedIn(loggedIn: boolean): void {
    const wasLoggedIn: boolean = LoginGate.isLoggedIn();
    AppStorage.setOrCreate<boolean>(STORAGE_KEY_LOGGED_IN, loggedIn);
    if (loggedIn && !wasLoggedIn) {
      LoginGate.notifyBecameLoggedIn();
    }
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

  // 订阅「登录态翻真」:返回取消订阅句柄。信号严格对齐 isLoggedIn 由 false→true 的那一刻,
  // 回调里读 isLoggedIn() 必为 true(不同于 SessionEventBus:会话变化事件早于 setLoggedIn 写入)。
  static subscribeBecameLoggedIn(listener: LoginStateListener): () => void {
    const listenerId: number = LoginGate.nextLoginStateListenerId;
    LoginGate.nextLoginStateListenerId++;
    LoginGate.loginStateListeners.set(listenerId, listener);
    return () => {
      LoginGate.loginStateListeners.delete(listenerId);
    };
  }

  private static notifyBecameLoggedIn(): void {
    const listeners: LoginStateListener[] = [];
    LoginGate.loginStateListeners.forEach((listener: LoginStateListener) => {
      listeners.push(listener);
    });
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (error) {
        Log.i(`${LOG_TAG} login-state listener failed error=${JSON.stringify(error)}`);
      }
    }
  }
}
