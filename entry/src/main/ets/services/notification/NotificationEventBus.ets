import { Log } from '../logging/Log';
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

    Log.i(`${LOG_TAG} publish unread=${snapshot.unread} highPriority=${snapshot.highPriority} listeners=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](snapshot);
      } catch (error) {
        Log.i(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }

  static current(): NotificationSnapshot {
    return NotificationEventBus.last;
  }

  // 标记已读一条通知后的乐观递减:仅当当前未读数 >0 才减 1。
  // 关键:未读为 0(或轮询尚未拿到真实值的空窗期)时一律不动——此时铃铛可能只是还没到 45s
  // 刷新,擅自减会得到负数或错误值,宁可等下一次轮询用服务端权威值覆盖。highPriority 同理。
  static decrementUnread(highPriority: boolean): void {
    const last: NotificationSnapshot = NotificationEventBus.last;
    if (last.unread <= 0) {
      return;
    }
    const nextHigh: number = highPriority && last.highPriority > 0 ? last.highPriority - 1 : last.highPriority;
    NotificationEventBus.publish({ unread: last.unread - 1, highPriority: nextHigh });
  }
}
