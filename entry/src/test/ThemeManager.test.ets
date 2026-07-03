import { describe, it, expect } from '@ohos/hypium';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeManager, ThemeMode } from '../main/ets/common/theme/ThemeManager';

export default function themeManagerTest() {
  describe('themeManagerTest', () => {
    it('mapsThemeModeToSystemColorMode', 0, () => {
      expect(ThemeManager.toColorMode(ThemeMode.SYSTEM))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      expect(ThemeManager.toColorMode(ThemeMode.LIGHT))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      expect(ThemeManager.toColorMode(ThemeMode.DARK))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    });

    it('parsesStoredThemeModeString', 0, () => {
      expect(ThemeManager.parseMode('system')).assertEqual(ThemeMode.SYSTEM);
      expect(ThemeManager.parseMode('light')).assertEqual(ThemeMode.LIGHT);
      expect(ThemeManager.parseMode('dark')).assertEqual(ThemeMode.DARK);
    });

    it('fallsBackToSystemForUnknownMode', 0, () => {
      expect(ThemeManager.parseMode('')).assertEqual(ThemeMode.SYSTEM);
      expect(ThemeManager.parseMode('unknown')).assertEqual(ThemeMode.SYSTEM);
    });
  });
}
