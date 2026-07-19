import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][ChallengeShortcut]';
// 与 DohManager / FeedPrefs 共用同一个 preferences 库,只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'challenge_shortcut_enabled';

// 「帖子页过盾快捷入口」开关的持久化。默认关:多数用户从不撞盾,常驻入口只会碍眼;
// 打开后也不是常驻——还要真的探测到 timings 被盾拦下才显示(见 ChallengeShortcutEventBus)。
export class ChallengeShortcutPrefs {
  // 内存镜像:详情页渲染要同步读,不能每帧 await。首次 load 后由 set 维护。
  private static cachedEnabled: boolean = false;
  private static loaded: boolean = false;

  static isEnabled(): boolean {
    return ChallengeShortcutPrefs.cachedEnabled;
  }

  // 冷启动/进设置页时载入一次,回填内存镜像。
  static async load(context: common.UIAbilityContext | common.Context): Promise<boolean> {
    if (ChallengeShortcutPrefs.loaded) {
      return ChallengeShortcutPrefs.cachedEnabled;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PREF_STORE_NAME);
      const value: preferences.ValueType = await store.get(PREF_KEY_ENABLED, false);
      ChallengeShortcutPrefs.cachedEnabled = value === true;
      ChallengeShortcutPrefs.loaded = true;
    } catch (error) {
      // 读失败按默认关处理:这只是个便利开关,不该因存储异常打断任何主流程。
      Log.i(`${LOG_TAG} load failed, fallback to disabled`);
      ChallengeShortcutPrefs.cachedEnabled = false;
    }
    return ChallengeShortcutPrefs.cachedEnabled;
  }

  static async setEnabled(context: common.UIAbilityContext | common.Context, enabled: boolean): Promise<void> {
    ChallengeShortcutPrefs.cachedEnabled = enabled;
    ChallengeShortcutPrefs.loaded = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PREF_STORE_NAME);
      await store.put(PREF_KEY_ENABLED, enabled);
      await store.flush();
      Log.i(`${LOG_TAG} enabled=${enabled}`);
    } catch (error) {
      Log.i(`${LOG_TAG} save failed enabled=${enabled}`);
    }
  }
}
