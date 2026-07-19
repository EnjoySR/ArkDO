import { BusinessError } from '@kit.BasicServicesKit';
import { pushService } from '@kit.PushKit';
import { Log } from '../logging/Log';
import { PushTokenProvider } from './PushSubscriptionService';
import { buildPushTokenDebugLogLine, shouldLogFullPushToken } from './PushTokenDebugLog';

const LOG_TAG: string = '[ArkDO][HarmonyPush]';

export class HarmonyPushTokenProvider implements PushTokenProvider {
  async getToken(): Promise<string> {
    Log.i(`${LOG_TAG} getToken start`);
    try {
      const token: string = await pushService.getToken();
      Log.i(`${LOG_TAG} getToken ok tokenLength=${token.length}`);
      if (shouldLogFullPushToken()) {
        Log.i(buildPushTokenDebugLogLine(LOG_TAG, token, true));
      }
      return token;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      const message: string = error.message === undefined ? '' : error.message;
      Log.i(`${LOG_TAG} getToken failed code=${error.code} message=${message}`);
      throw new Error(`code=${error.code} ${message}`);
    }
  }
}
