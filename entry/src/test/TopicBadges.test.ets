import { describe, it, expect } from '@ohos/hypium';
import { FaIconDefinition, getFaIcon, hasLoadedFaIcons, loadFaIconsFromJson } from '../main/ets/views/components/FaIcon';
import { getCategoryIcon, getTagColor, getTagIcon } from '../main/ets/views/components/TopicBadgeUtils';
import { getTagIconStyle, hasLoadedTagIcons, loadTagIconsFromJson } from '../main/ets/views/components/TagIconRegistry';
import { TopicCategory } from '../main/ets/models/Topic';

export default function topicBadgesTest() {
  describe('topicBadgesTest', () => {
    it('loadsFontAwesomeIconIdsIntoMemory', 0, () => {
      const iconCount: number = loadFaIconsFromJson('[{"id":"piggy-bank"},{"id":"coins"}]');

      expect(iconCount).assertEqual(2);
      expect(hasLoadedFaIcons()).assertTrue();
      expect(getFaIcon('piggy-bank')?.rawfilePath).assertEqual('fa_icons/piggy-bank.svg');
    });

    it('resolvesRawfilePathFromIconIdOnly', 0, () => {
      const iconCount: number = loadFaIconsFromJson('[{"id":"triangle-exclamation"}]');

      expect(iconCount).assertEqual(1);
      expect(getFaIcon('triangle-exclamation')?.rawfilePath).assertEqual('fa_icons/triangle-exclamation.svg');
    });

    it('resolvesCategoryFontAwesomeIconFromSiteIconName', 0, () => {
      loadFaIconsFromJson('[{"id":"piggy-bank"}]');
      const category: TopicCategory = {
        id: 36,
        name: '福利羊毛',
        color: 'E45735',
        textColor: 'FFFFFF',
        icon: 'piggy-bank'
      };

      const icon: FaIconDefinition | undefined = getCategoryIcon(category);

      expect(icon?.id).assertEqual('piggy-bank');
      expect(icon?.rawfilePath).assertEqual('fa_icons/piggy-bank.svg');
    });

    it('loadsTagIconsFromLinuxDoResource', 0, () => {
      const count: number = loadTagIconsFromJson('[{"tagName":"软件开发","iconId":"file-code","color":"#669d34"},{"tagName":"ChatGPT","iconId":"","color":""},{"tagName":"nsfw","iconId":"triangle-exclamation","color":"#F7941D"}]');

      expect(count).assertEqual(2);
      expect(hasLoadedTagIcons()).assertTrue();
      expect(getTagIconStyle('软件开发')?.iconId).assertEqual('file-code');
      expect(getTagIconStyle('NSFW')?.iconId).assertEqual('triangle-exclamation');
      expect(getTagIconStyle('ChatGPT')?.iconId).assertEqual(undefined);
    });

    it('resolvesTagIconOnlyFromLoadedLinuxDoTagIconResource', 0, () => {
      loadFaIconsFromJson('[{"id":"file-code"},{"id":"code"}]');
      loadTagIconsFromJson('[{"tagName":"软件开发","iconId":"file-code","color":"#669d34"}]');

      const icon: FaIconDefinition | undefined = getTagIcon('软件开发');

      expect(icon?.id).assertEqual('file-code');
      expect(getTagColor('软件开发')).assertEqual('#669d34');
      expect(getTagIcon('ChatGPT')?.id).assertEqual(undefined);
    });

  });
}
