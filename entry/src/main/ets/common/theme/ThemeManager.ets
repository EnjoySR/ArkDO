import { Log } from '../../services/logging/Log';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][Theme]';
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_THEME_MODE: string = 'themeMode';

/** AppStorage 中主题模式的 key，供 UI 通过 @StorageLink/@StorageProp 绑定。 */
export const THEME_MODE_STORAGE_KEY: string = 'themeMode';

/** 三态主题模式：跟随系统 / 强制浅色 / 强制深色。 */
export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

/**
 * 集中管理应用颜色模式：负责 ThemeMode 与系统 ColorMode 的映射、preferences 持久化、
 * AppStorage 状态同步，以及调用 setColorMode 让 ArkUI 重新解析颜色资源。
 */
export class ThemeManager {
  /** 纯映射：ThemeMode -> 系统 ColorMode（便于单测）。 */
  static toColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
    switch (mode) {
      case ThemeMode.LIGHT:
        return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      case ThemeMode.DARK:
        return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      default:
        return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
  }

  /** 纯解析：把持久化的字符串还原为 ThemeMode，非法值回退到 SYSTEM。 */
  static parseMode(raw: string): ThemeMode {
    switch (raw) {
      case ThemeMode.LIGHT:
        return ThemeMode.LIGHT;
      case ThemeMode.DARK:
        return ThemeMode.DARK;
      default:
        return ThemeMode.SYSTEM;
    }
  }

  /** 应用启动时调用：读取上次选择并应用；首次无记录等价于跟随系统。 */
  static init(context: common.Context): void {
    let mode: ThemeMode = ThemeMode.SYSTEM;
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      const raw: string = store.getSync(PREF_KEY_THEME_MODE, ThemeMode.SYSTEM) as string;
      mode = ThemeManager.parseMode(raw);
    } catch (err) {
      Log.e(`${LOG_TAG} read theme mode failed: ${JSON.stringify(err)}`);
    }
    AppStorage.setOrCreate(THEME_MODE_STORAGE_KEY, mode);
    ThemeManager.applyColorMode(context, mode);
  }

  /** 用户切换主题：立即应用 + 持久化 + 同步 AppStorage 供 UI 高亮。 */
  static setMode(context: common.Context, mode: ThemeMode): void {
    AppStorage.setOrCreate(THEME_MODE_STORAGE_KEY, mode);
    ThemeManager.applyColorMode(context, mode);
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      store.putSync(PREF_KEY_THEME_MODE, mode);
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} persist theme mode failed: ${JSON.stringify(err)}`);
    }
  }

  private static applyColorMode(context: common.Context, mode: ThemeMode): void {
    try {
      context.getApplicationContext().setColorMode(ThemeManager.toColorMode(mode));
    } catch (err) {
      Log.e(`${LOG_TAG} setColorMode failed: ${JSON.stringify(err)}`);
    }
  }
}
