import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][PushTokenUpdate]';

export type PushTokenUpdateListener = () => void;

// 设备 Push Token 轮换事件。监听只能挂在 UIAbility 上(pushService.on('tokenUpdate', ability, cb)
// 要求传 Ability 实例),但重新登记订阅需要 RootTabPage 手里的登录态与用户信息,故用事件总线接力。
// pending 兜住"token 在 RootTabPage 挂载前就更新了"的情况,避免这次轮换被漏掉。
export class PushTokenUpdateEventBus {
  private static listeners: Map<number, PushTokenUpdateListener> = new Map();
  private static nextListenerId: number = 0;
  private static pending: boolean = false;

  static subscribe(listener: PushTokenUpdateListener): () => void {
    const listenerId: number = PushTokenUpdateEventBus.nextListenerId;
    PushTokenUpdateEventBus.nextListenerId++;
    PushTokenUpdateEventBus.listeners.set(listenerId, listener);

    return () => {
      PushTokenUpdateEventBus.listeners.delete(listenerId);
    };
  }

  static publish(): void {
    PushTokenUpdateEventBus.pending = true;
    const listeners: PushTokenUpdateListener[] = [];
    PushTokenUpdateEventBus.listeners.forEach((listener: PushTokenUpdateListener) => {
      listeners.push(listener);
    });

    Log.i(`${LOG_TAG} publish listeners=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (error) {
        Log.i(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }

  // 取走待处理标记:有则返回 true 并清空,保证一次轮换只被消费一次。
  static takePending(): boolean {
    const pending: boolean = PushTokenUpdateEventBus.pending;
    PushTokenUpdateEventBus.pending = false;
    return pending;
  }

  static clearPending(): void {
    PushTokenUpdateEventBus.pending = false;
  }
}
