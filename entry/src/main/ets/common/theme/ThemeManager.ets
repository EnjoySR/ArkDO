import { Log } from '../../services/logging/Log';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { mediaquery } from '@kit.ArkUI';

const LOG_TAG: string = '[ArkDO][Theme]';
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_THEME_MODE: string = 'themeMode';

/** AppStorage 中主题模式的 key，供 UI 通过 @StorageLink/@StorageProp 绑定。 */
export const THEME_MODE_STORAGE_KEY: string = 'themeMode';

/**
 * AppStorage 中「当前是否为深色渲染」的布尔 key。资源色(app.color.*)靠限定符自动翻转,
 * 但非资源的染色(如公式位图 colorFilter 矩阵、烘进数值的色值)拿不到限定符,须靠此布尔手动切换。
 * 取值同时考虑强制主题(DARK/LIGHT)与「跟随系统」下的系统实际明暗,供 @StorageProp 响应式绑定。
 */
export const APP_IS_DARK_STORAGE_KEY: string = 'appIsDark';

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
  // 「跟随系统」时用 mediaquery 监听系统明暗;强制主题时忽略。listener 全局单例,随应用存活不销毁。
  private static systemDarkListener?: mediaquery.MediaQueryListener = undefined;
  private static systemIsDark: boolean = false;
  private static currentMode: ThemeMode = ThemeMode.SYSTEM;

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
    ThemeManager.currentMode = mode;
    AppStorage.setOrCreate(THEME_MODE_STORAGE_KEY, mode);
    ThemeManager.applyColorMode(context, mode);
    ThemeManager.startSystemDarkWatch();
    ThemeManager.recomputeIsDark();
  }

  /** 用户切换主题：立即应用 + 持久化 + 同步 AppStorage 供 UI 高亮。 */
  static setMode(context: common.Context, mode: ThemeMode): void {
    ThemeManager.currentMode = mode;
    AppStorage.setOrCreate(THEME_MODE_STORAGE_KEY, mode);
    ThemeManager.applyColorMode(context, mode);
    ThemeManager.recomputeIsDark();
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

  // 惰性建立系统明暗监听(仅一次)。系统在「跟随系统」时决定实际明暗;change 回调实时刷新。
  private static startSystemDarkWatch(): void {
    if (ThemeManager.systemDarkListener) {
      return;
    }
    try {
      const listener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(dark-mode: true)');
      ThemeManager.systemIsDark = listener.matches;
      listener.on('change', (result: mediaquery.MediaQueryResult): void => {
        ThemeManager.systemIsDark = result.matches;
        ThemeManager.recomputeIsDark();
      });
      ThemeManager.systemDarkListener = listener;
    } catch (err) {
      Log.e(`${LOG_TAG} start system dark watch failed: ${JSON.stringify(err)}`);
    }
  }

  // 计算「当前是否深色渲染」并写入 AppStorage:强制主题优先,SYSTEM 时取系统实际明暗。
  // 资源色靠限定符自动翻转,此布尔只服务于非资源染色(公式位图 colorFilter、烘进数值的高亮色等)。
  private static recomputeIsDark(): void {
    let dark: boolean;
    switch (ThemeManager.currentMode) {
      case ThemeMode.DARK:
        dark = true;
        break;
      case ThemeMode.LIGHT:
        dark = false;
        break;
      default:
        dark = ThemeManager.systemIsDark;
        break;
    }
    AppStorage.setOrCreate(APP_IS_DARK_STORAGE_KEY, dark);
  }
}
