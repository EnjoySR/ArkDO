import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeManager } from '../common/theme/ThemeManager';
import { LINUXDO_FA_SYMBOLS_RAWFILE, loadFaIconsFromRawContent } from '../views/components/FaIcon';
import { LINUXDO_TAG_ICONS_RAWFILE, loadTagIconsFromRawContent } from '../views/components/TagIconRegistry';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ThemeManager.init(this.context);
    this.loadIconAssets();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
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
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
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
