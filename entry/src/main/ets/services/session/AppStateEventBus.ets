const LOG_TAG: string = '[ArkDO][AppState]';

export type AppForegroundListener = (isForeground: boolean) => void;

// 应用前后台状态广播:EntryAbility.onForeground/onBackground 通知,
// 详情页订阅用于暂停/恢复阅读计时(对齐 Discourse 的 session.hasFocus)。
export class AppStateEventBus {
  private static listeners: Map<number, AppForegroundListener> = new Map();
  private static nextListenerId: number = 0;
  private static foreground: boolean = true;

  static subscribe(listener: AppForegroundListener): () => void {
    const listenerId: number = AppStateEventBus.nextListenerId;
    AppStateEventBus.nextListenerId++;
    AppStateEventBus.listeners.set(listenerId, listener);

    return () => {
      AppStateEventBus.listeners.delete(listenerId);
    };
  }

  static notifyForegroundChanged(isForeground: boolean): void {
    AppStateEventBus.foreground = isForeground;
    const listeners: AppForegroundListener[] = [];
    AppStateEventBus.listeners.forEach((listener: AppForegroundListener) => {
      listeners.push(listener);
    });

    console.info(`${LOG_TAG} foreground=${isForeground} listenerCount=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](isForeground);
      } catch (error) {
        console.info(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }

  static isForeground(): boolean {
    return AppStateEventBus.foreground;
  }
}
