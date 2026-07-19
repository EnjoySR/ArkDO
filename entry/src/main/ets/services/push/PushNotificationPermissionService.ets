import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][PushPermission]';

export interface PushNotificationPermissionResult {
  enabled: boolean;
  message: string;
}

export class PushNotificationPermissionService {
  async checkEnabled(): Promise<PushNotificationPermissionResult> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      Log.i(`${LOG_TAG} enabled check=${enabled}`);
      return {
        enabled: enabled,
        message: enabled ? '通知权限已开启' : '通知权限未开启'
      };
    } catch (err) {
      const detail: string = this.describeError(err);
      Log.i(`${LOG_TAG} check failed ${detail}`);
      return {
        enabled: false,
        message: detail.length > 0 ? `通知权限检查失败: ${detail}` : '通知权限检查失败'
      };
    }
  }

  async ensureEnabled(context: common.UIAbilityContext): Promise<PushNotificationPermissionResult> {
    try {
      const before: boolean = await notificationManager.isNotificationEnabled();
      Log.i(`${LOG_TAG} enabled before=${before}`);
      if (before) {
        return {
          enabled: true,
          message: '通知权限已开启'
        };
      }

      Log.i(`${LOG_TAG} requestEnableNotification start`);
      await notificationManager.requestEnableNotification(context);

      const after: boolean = await notificationManager.isNotificationEnabled();
      Log.i(`${LOG_TAG} enabled after=${after}`);
      if (!after) {
        return {
          enabled: false,
          message: '通知权限未开启'
        };
      }
      return {
        enabled: true,
        message: '通知权限已开启'
      };
    } catch (err) {
      const detail: string = this.describeError(err);
      Log.i(`${LOG_TAG} request failed ${detail}`);
      return {
        enabled: false,
        message: detail.length > 0 ? `通知权限申请失败: ${detail}` : '通知权限申请失败'
      };
    }
  }

  private describeError(err: Object): string {
    const error: BusinessError = err as BusinessError;
    const parts: string[] = [];
    if (error.code !== undefined) {
      parts.push(`code=${error.code}`);
    }
    if (error.message !== undefined && error.message.length > 0) {
      parts.push(error.message);
    }
    return parts.join(' ');
  }
}
