import { Log } from '../logging/Log';
import { describePushNotificationRoute, PushNotificationRoute } from './PushNotificationNavigation';

const LOG_TAG: string = '[ArkDO][PushNavigation]';

export type PushNotificationRouteListener = (route: PushNotificationRoute) => void;

export class PushNotificationNavigationEventBus {
  private static listeners: Map<number, PushNotificationRouteListener> = new Map();
  private static nextListenerId: number = 0;
  private static pending?: PushNotificationRoute = undefined;

  static subscribe(listener: PushNotificationRouteListener): () => void {
    const listenerId: number = PushNotificationNavigationEventBus.nextListenerId;
    PushNotificationNavigationEventBus.nextListenerId++;
    PushNotificationNavigationEventBus.listeners.set(listenerId, listener);

    return () => {
      PushNotificationNavigationEventBus.listeners.delete(listenerId);
    };
  }

  static publish(route: PushNotificationRoute): void {
    PushNotificationNavigationEventBus.pending = route;
    const listeners: PushNotificationRouteListener[] = [];
    PushNotificationNavigationEventBus.listeners.forEach((listener: PushNotificationRouteListener) => {
      listeners.push(listener);
    });

    Log.i(`${LOG_TAG} publish id=${route.id} path=${describePushNotificationRoute(route)} listeners=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](route);
      } catch (error) {
        Log.i(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }

  static takePending(): PushNotificationRoute | undefined {
    const route: PushNotificationRoute | undefined = PushNotificationNavigationEventBus.pending;
    PushNotificationNavigationEventBus.pending = undefined;
    return route;
  }

  static clearPending(routeId: number): void {
    if (PushNotificationNavigationEventBus.pending?.id === routeId) {
      PushNotificationNavigationEventBus.pending = undefined;
    }
  }
}
