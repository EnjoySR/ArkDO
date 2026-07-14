import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][ChallengeRecovery]';

// 挑战恢复协调器的状态机。定义在 bus 而非协调器,避免协调器 <-> bus 循环依赖。
export enum ChallengeRecoveryState {
  IDLE = 0,
  RESOLVING = 1,
  AWAITING_SHEET = 2,
  COOLDOWN = 3
}

export type ChallengeRecoveryStateListener = (state: ChallengeRecoveryState) => void;
export type ManualChallengeListener = () => void;

// 双向通道:
// - 协调器 → UI:每次状态迁移广播,首页据此在"静默中/终态"两态间切换空态。
// - UI → 协调器:首页"手动验证"按钮请求接管,RootTabPage 订阅后调 forceEscalate。
export class ChallengeRecoveryEventBus {
  private static stateListeners: Map<number, ChallengeRecoveryStateListener> = new Map();
  private static manualListeners: Map<number, ManualChallengeListener> = new Map();
  private static nextStateListenerId: number = 0;
  private static nextManualListenerId: number = 0;
  private static currentState: ChallengeRecoveryState = ChallengeRecoveryState.IDLE;

  static subscribeState(listener: ChallengeRecoveryStateListener): () => void {
    const listenerId: number = ChallengeRecoveryEventBus.nextStateListenerId;
    ChallengeRecoveryEventBus.nextStateListenerId++;
    ChallengeRecoveryEventBus.stateListeners.set(listenerId, listener);

    return () => {
      ChallengeRecoveryEventBus.stateListeners.delete(listenerId);
    };
  }

  static notifyState(state: ChallengeRecoveryState): void {
    ChallengeRecoveryEventBus.currentState = state;
    const listeners: ChallengeRecoveryStateListener[] = [];
    ChallengeRecoveryEventBus.stateListeners.forEach((listener: ChallengeRecoveryStateListener) => {
      listeners.push(listener);
    });

    Log.i(`${LOG_TAG} state=${state} listenerCount=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](state);
      } catch (error) {
        Log.i(`${LOG_TAG} state listener failed error=${JSON.stringify(error)}`);
      }
    }
  }

  static getCurrentState(): ChallengeRecoveryState {
    return ChallengeRecoveryEventBus.currentState;
  }

  static subscribeManual(listener: ManualChallengeListener): () => void {
    const listenerId: number = ChallengeRecoveryEventBus.nextManualListenerId;
    ChallengeRecoveryEventBus.nextManualListenerId++;
    ChallengeRecoveryEventBus.manualListeners.set(listenerId, listener);

    return () => {
      ChallengeRecoveryEventBus.manualListeners.delete(listenerId);
    };
  }

  // 首页"手动验证"按钮:请求协调器立即接管(停后台轮询、弹可见验证页)。
  static requestManual(): void {
    const listeners: ManualChallengeListener[] = [];
    ChallengeRecoveryEventBus.manualListeners.forEach((listener: ManualChallengeListener) => {
      listeners.push(listener);
    });

    Log.i(`${LOG_TAG} manual challenge requested listenerCount=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (error) {
        Log.i(`${LOG_TAG} manual listener failed error=${JSON.stringify(error)}`);
      }
    }
  }
}
