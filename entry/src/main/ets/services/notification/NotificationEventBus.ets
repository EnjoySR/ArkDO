const LOG_TAG: string = '[ArkDO][NotificationBus]';

// 头像未读数快照。unread=常规未读(蓝点数字);highPriority=高优先级(私信等)。
// 头像铃铛 badge 显示的是 unread(可按需叠加 highPriority)。
export interface NotificationSnapshot {
  unread: number;
  highPriority: number;
}

export type NotificationListener = (snapshot: NotificationSnapshot) => void;

// 未读数事件总线:NotificationService(轮询)与 RootTabPage(会话事件)都发到这里,
// HomePage 订阅后驱动铃铛。保留 last 值,新订阅者可立即拿到当前数,避免首帧空窗。
export class NotificationEventBus {
  private static listeners: Map<number, NotificationListener> = new Map();
  private static nextListenerId: number = 0;
  private static last: NotificationSnapshot = { unread: 0, highPriority: 0 };

  static subscribe(listener: NotificationListener): () => void {
    const listenerId: number = NotificationEventBus.nextListenerId;
    NotificationEventBus.nextListenerId++;
    NotificationEventBus.listeners.set(listenerId, listener);

    return () => {
      NotificationEventBus.listeners.delete(listenerId);
    };
  }

  static publish(snapshot: NotificationSnapshot): void {
    NotificationEventBus.last = snapshot;
    const listeners: NotificationListener[] = [];
    NotificationEventBus.listeners.forEach((listener: NotificationListener) => {
      listeners.push(listener);
    });

    console.info(`${LOG_TAG} publish unread=${snapshot.unread} highPriority=${snapshot.highPriority} listeners=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](snapshot);
      } catch (error) {
        console.info(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }

  static current(): NotificationSnapshot {
    return NotificationEventBus.last;
  }
}
