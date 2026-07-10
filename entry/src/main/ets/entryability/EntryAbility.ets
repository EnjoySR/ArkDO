import { Log } from '../services/logging/Log';
import { AbilityConstant, errorManager, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { ThemeManager } from '../common/theme/ThemeManager';
import { DohManager } from '../services/network/DohManager';
import { FileLogger } from '../services/logging/FileLogger';
import { AppStateEventBus } from '../services/session/AppStateEventBus';
import { LINUXDO_FA_SYMBOLS_RAWFILE, loadFaIconsFromRawContent } from '../views/components/FaIcon';
import { LINUXDO_TAG_ICONS_RAWFILE, loadTagIconsFromRawContent } from '../views/components/TagIconRegistry';
import { ArkWebNetworkBridge } from '../services/network/ArkWebNetworkBridge';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private crashObserverId: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 日志系统须最先初始化,后续经 Log 门面写入的日志才能落盘。
    FileLogger.init(this.context);
    // 计时锚点①:应用启动。与首页帖子列表开始加载的日志配对,测量冷启动到首屏拉取的耗时。
    Log.i(`[ArkDO][Startup] stage=appOnCreate ts=${Date.now()}`);
    this.registerCrashHandler();
    ThemeManager.init(this.context);
    // setHttpDns 只有在 Web 引擎初始化之后才生效(引擎网络服务需先就绪),故须先显式
    // initializeWebEngine 再下发 DoH;且早于任何页面,确保宿主 webview 首次解析
    // linux.do 就走 DoH,规避被污染的系统 DNS。否则请求会以 useHttpDns:0 走系统 DNS 超时。
    try {
      webview.WebviewController.initializeWebEngine();
    } catch (err) {
      Log.e(`[ArkDO][EntryAbility] initializeWebEngine failed: ${JSON.stringify(err)}`);
    }
    DohManager.init(this.context);
    this.loadIconAssets();
    // 冷启动清空音视频缓存目录,避免下载文件无限堆积占存储。
    ArkWebNetworkBridge.clearMediaCacheDir(this.context);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    this.unregisterCrashHandler();
    FileLogger.flush();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    AppStateEventBus.notifyForegroundChanged(true);
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    AppStateEventBus.notifyForegroundChanged(false);
    // 退后台可能随即被系统回收,把缓冲日志强制落盘,避免丢最后一段。
    FileLogger.flush();
  }

  // 全局未捕获异常:崩溃堆栈写入日志并立即刷盘,导出日志里保留闪退现场。
  private registerCrashHandler(): void {
    try {
      this.crashObserverId = errorManager.on('error', {
        onUnhandledException: (errMsg: string): void => {
          Log.e(`[ArkDO][Crash] unhandledException: ${errMsg}`);
          FileLogger.flush();
        }
      });
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'register crash handler failed: %{public}s', JSON.stringify(error));
    }
  }

  private unregisterCrashHandler(): void {
    if (this.crashObserverId < 0) {
      return;
    }
    try {
      errorManager.off('error', this.crashObserverId);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'unregister crash handler failed: %{public}s', JSON.stringify(error));
    }
    this.crashObserverId = -1;
  }

  private loadIconAssets(): void {
    try {
      const rawContent: Uint8Array = this.context.resourceManager.getRawFileContentSync(LINUXDO_FA_SYMBOLS_RAWFILE);
      const iconCount: number = loadFaIconsFromRawContent(rawContent);
      hilog.info(DOMAIN, 'testTag', 'Loaded Linux.do FontAwesome symbols: %{public}d', iconCount);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to load Linux.do FontAwesome symbols. Cause: %{public}s',
        JSON.stringify(err));
    }

    try {
      const rawContent: Uint8Array = this.context.resourceManager.getRawFileContentSync(LINUXDO_TAG_ICONS_RAWFILE);
      const tagIconCount: number = loadTagIconsFromRawContent(rawContent);
      hilog.info(DOMAIN, 'testTag', 'Loaded Linux.do tag icons: %{public}d', tagIconCount);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to load Linux.do tag icons. Cause: %{public}s',
        JSON.stringify(err));
    }
  }
}
