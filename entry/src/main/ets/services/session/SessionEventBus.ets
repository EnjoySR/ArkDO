const LOG_TAG: string = '[ArkDO][Session]';

export type SessionChangedListener = (version: number) => void;

export class SessionEventBus {
  private static listeners: Map<number, SessionChangedListener> = new Map();
  private static nextListenerId: number = 0;
  private static currentVersion: number = 0;

  static subscribe(listener: SessionChangedListener): () => void {
    const listenerId: number = SessionEventBus.nextListenerId;
    SessionEventBus.nextListenerId++;
    SessionEventBus.listeners.set(listenerId, listener);

    return () => {
      SessionEventBus.listeners.delete(listenerId);
    };
  }

  static notifySessionChanged(): number {
    SessionEventBus.currentVersion++;
    const version: number = SessionEventBus.currentVersion;
    const listeners: SessionChangedListener[] = [];

    SessionEventBus.listeners.forEach((listener: SessionChangedListener) => {
      listeners.push(listener);
    });

    console.info(`${LOG_TAG} session changed version=${version} listenerCount=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](version);
      } catch (error) {
        console.info(`${LOG_TAG} listener failed version=${version} error=${JSON.stringify(error)}`);
      }
    }

    return version;
  }

  static getCurrentVersion(): number {
    return SessionEventBus.currentVersion;
  }
}
