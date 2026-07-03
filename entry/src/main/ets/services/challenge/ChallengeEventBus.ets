import { ChallengeState } from '../network/NetworkTypes';

const LOG_TAG: string = '[ArkDO][Challenge]';
const DIAG_TAG: string = '[ARKDO_CF_DIAG]';

export interface ChallengeRequiredEvent {
  version: number;
  source: string;
  statusCode: number;
  challengeState: ChallengeState;
}

export type ChallengeRequiredListener = (event: ChallengeRequiredEvent) => void;

export class ChallengeEventBus {
  private static listeners: Map<number, ChallengeRequiredListener> = new Map();
  private static nextListenerId: number = 0;
  private static currentVersion: number = 0;

  static subscribe(listener: ChallengeRequiredListener): () => void {
    const listenerId: number = ChallengeEventBus.nextListenerId;
    ChallengeEventBus.nextListenerId++;
    ChallengeEventBus.listeners.set(listenerId, listener);

    return () => {
      ChallengeEventBus.listeners.delete(listenerId);
    };
  }

  static notifyChallengeRequired(source: string, statusCode: number, challengeState: ChallengeState): number {
    ChallengeEventBus.currentVersion++;
    const version: number = ChallengeEventBus.currentVersion;
    const event: ChallengeRequiredEvent = {
      version: version,
      source: source,
      statusCode: statusCode,
      challengeState: challengeState
    };
    const listeners: ChallengeRequiredListener[] = [];

    ChallengeEventBus.listeners.forEach((listener: ChallengeRequiredListener) => {
      listeners.push(listener);
    });

    console.info(`${LOG_TAG} required version=${version} source=${source} status=${statusCode} state=${challengeState} listenerCount=${listeners.length}`);
    console.info(`${DIAG_TAG} stage=eventBusNotify version=${version} source=${source} status=${statusCode} state=${challengeState} listenerCount=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](event);
      } catch (error) {
        console.info(`${LOG_TAG} listener failed version=${version} error=${JSON.stringify(error)}`);
      }
    }

    return version;
  }

  static getCurrentVersion(): number {
    return ChallengeEventBus.currentVersion;
  }
}
