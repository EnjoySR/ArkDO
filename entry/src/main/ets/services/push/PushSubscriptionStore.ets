import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Log } from '../logging/Log';
import { PushRelayRegistration } from './PushSubscriptionService';

const LOG_TAG: string = '[ArkDO][PushStore]';
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_PREFIX: string = 'push_subscription_user_';

export interface StoredPushSubscription {
  desiredEnabled: boolean;
  subId: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  updatedAt: number;
}

interface StoredPushSubscriptionPayload {
  desiredEnabled?: boolean;
  subId?: string;
  endpoint?: string;
  p256dh?: string;
  auth?: string;
  updatedAt?: number;
}

export class PushSubscriptionStore {
  static get(context: common.Context, userId: number): StoredPushSubscription {
    try {
      const raw: string = PushSubscriptionStore.store(context).getSync(PushSubscriptionStore.key(userId), '') as string;
      if (raw.length === 0) {
        return PushSubscriptionStore.empty();
      }
      const payload: StoredPushSubscriptionPayload = JSON.parse(raw) as StoredPushSubscriptionPayload;
      return {
        desiredEnabled: payload.desiredEnabled === true,
        subId: typeof payload.subId === 'string' ? payload.subId : '',
        endpoint: typeof payload.endpoint === 'string' ? payload.endpoint : '',
        p256dh: typeof payload.p256dh === 'string' ? payload.p256dh : '',
        auth: typeof payload.auth === 'string' ? payload.auth : '',
        updatedAt: typeof payload.updatedAt === 'number' ? payload.updatedAt : 0
      };
    } catch (err) {
      Log.i(`${LOG_TAG} read failed userId=${userId} error=${JSON.stringify(err)}`);
      return PushSubscriptionStore.empty();
    }
  }

  static saveEnabled(context: common.Context, userId: number, registration: PushRelayRegistration): void {
    PushSubscriptionStore.save(context, userId, {
      desiredEnabled: true,
      subId: registration.subId ?? '',
      endpoint: registration.endpoint,
      p256dh: registration.p256dh,
      auth: registration.auth,
      updatedAt: Date.now()
    });
  }

  static saveDisabled(context: common.Context, userId: number): void {
    PushSubscriptionStore.save(context, userId, {
      desiredEnabled: false,
      subId: '',
      endpoint: '',
      p256dh: '',
      auth: '',
      updatedAt: Date.now()
    });
  }

  static toRegistration(stored: StoredPushSubscription): PushRelayRegistration | undefined {
    if (stored.endpoint.length === 0 || stored.p256dh.length === 0 || stored.auth.length === 0) {
      return undefined;
    }
    return {
      subId: stored.subId,
      endpoint: stored.endpoint,
      p256dh: stored.p256dh,
      auth: stored.auth
    };
  }

  private static save(context: common.Context, userId: number, value: StoredPushSubscription): void {
    try {
      const store: preferences.Preferences = PushSubscriptionStore.store(context);
      store.putSync(PushSubscriptionStore.key(userId), JSON.stringify(value));
      store.flush();
    } catch (err) {
      Log.i(`${LOG_TAG} write failed userId=${userId} error=${JSON.stringify(err)}`);
    }
  }

  private static empty(): StoredPushSubscription {
    return {
      desiredEnabled: false,
      subId: '',
      endpoint: '',
      p256dh: '',
      auth: '',
      updatedAt: 0
    };
  }

  private static key(userId: number): string {
    return `${PREF_KEY_PREFIX}${userId}`;
  }

  private static store(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
  }
}
