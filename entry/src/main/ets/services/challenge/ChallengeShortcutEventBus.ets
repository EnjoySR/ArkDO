import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][ChallengeShortcut]';

export type ChallengeShortcutListener = (blocked: boolean) => void;

// 「阅读时是否正被盾拦着」的信号通道。
//
// 为什么需要它:timings 上报是 notifyChallenge:false 的后台请求——撞盾时故意不弹验证页
// (否则用户滑着帖子会被突然打断)。代价是撞盾完全静默,用户只看到蓝点不消失、不知道发生了什么,
// 想过盾还得翻进很深的入口。故把「撞盾」这个事实单独播出来,供详情页在右上角亮一个快捷入口。
//
// 只在 ReadingTracker 明确判定 challengeState !== NONE 时才置真——普通网络失败不算
// (地铁上没信号也蹦出过盾图标是打扰)。过盾成功或后续上报成功即复位,保证「图标在 = 当前确实有问题」。
export class ChallengeShortcutEventBus {
  private static listeners: Map<number, ChallengeShortcutListener> = new Map();
  private static nextListenerId: number = 0;
  // 当前是否被拦。进详情页时读它做初值(可能在别的页面就已经撞过盾)。
  private static blocked: boolean = false;

  static isBlocked(): boolean {
    return ChallengeShortcutEventBus.blocked;
  }

  static subscribe(listener: ChallengeShortcutListener): () => void {
    const listenerId: number = ChallengeShortcutEventBus.nextListenerId;
    ChallengeShortcutEventBus.nextListenerId++;
    ChallengeShortcutEventBus.listeners.set(listenerId, listener);
    return () => {
      ChallengeShortcutEventBus.listeners.delete(listenerId);
    };
  }

  // timings 撞盾时调用。
  static notifyBlocked(): void {
    ChallengeShortcutEventBus.publish(true);
  }

  // 过盾成功、或后续 timings 上报成功时调用:盾已经过去了,图标该收起来。
  static notifyCleared(): void {
    ChallengeShortcutEventBus.publish(false);
  }

  private static publish(blocked: boolean): void {
    // 状态没变就不广播,避免每次上报成功都刷一遍订阅者。
    if (ChallengeShortcutEventBus.blocked === blocked) {
      return;
    }
    ChallengeShortcutEventBus.blocked = blocked;
    Log.i(`${LOG_TAG} blocked=${blocked}`);
    const snapshot: ChallengeShortcutListener[] = [];
    ChallengeShortcutEventBus.listeners.forEach((listener: ChallengeShortcutListener) => {
      snapshot.push(listener);
    });
    for (let index: number = 0; index < snapshot.length; index++) {
      snapshot[index](blocked);
    }
  }
}
