import { describe, it, expect } from '@ohos/hypium';
import {
  formatCount,
  formatJoinDate,
  formatTimeRead,
  trustLabelOf,
  TRUST_LEVEL_NAMES
} from '../main/ets/common/utils/ProfileFormat';
import { UserProfileDetail } from '../main/ets/models/UserProfile';

export default function profileFormatTest() {
  describe('profileFormatTest', () => {

    it('formatsCountBelowThousandVerbatim', 0, () => {
      expect(formatCount(0)).assertEqual('0');
      expect(formatCount(999)).assertEqual('999');
    });

    it('formatsThousandsWithOneDecimalAndDropsTrailingZero', 0, () => {
      expect(formatCount(1000)).assertEqual('1k');
      expect(formatCount(1200)).assertEqual('1.2k');
      expect(formatCount(1250)).assertEqual('1.2k');
      expect(formatCount(9999)).assertEqual('9.9k');
    });

    it('formatsTenThousandPlusAsWholeThousands', 0, () => {
      expect(formatCount(10000)).assertEqual('10k');
      expect(formatCount(123456)).assertEqual('123k');
    });

    it('formatsTimeReadInMinutesBelowOneHour', 0, () => {
      expect(formatTimeRead(0)).assertEqual('1m');
      expect(formatTimeRead(90)).assertEqual('2m');
      expect(formatTimeRead(3599)).assertEqual('60m');
    });

    it('formatsTimeReadInHoursFromOneHourUp', 0, () => {
      expect(formatTimeRead(3600)).assertEqual('1h');
      expect(formatTimeRead(7200)).assertEqual('2h');
    });

    it('formatsJoinDateFromIsoTimestamp', 0, () => {
      expect(formatJoinDate('2024-01-18T05:30:00.000Z')).assertEqual('2024年1月18日');
      expect(formatJoinDate('2024-12-05')).assertEqual('2024年12月5日');
    });

    it('returnsEmptyJoinDateForMissingOrMalformedInput', 0, () => {
      expect(formatJoinDate(undefined)).assertEqual('');
      expect(formatJoinDate('')).assertEqual('');
      expect(formatJoinDate('not-a-date')).assertEqual('');
    });

    it('exposesFiveTrustLevelNames', 0, () => {
      expect(TRUST_LEVEL_NAMES.length).assertEqual(5);
      expect(TRUST_LEVEL_NAMES[3]).assertEqual('常客');
    });

    // 这是修掉的那处分叉:「我的」页原本取 title,他人主页原本忽略 title,
    // 同一份数据在两页显示不同。统一后 title 优先。
    it('prefersSiteTitleOverDefaultTrustLevelName', 0, () => {
      const detail: UserProfileDetail = { trustLevel: 3, title: '赞助商' };
      expect(trustLabelOf(detail)).assertEqual('TL3 赞助商');
    });

    it('fallsBackToTrustLevelNameWhenTitleAbsentOrEmpty', 0, () => {
      expect(trustLabelOf({ trustLevel: 3 })).assertEqual('TL3 常客');
      expect(trustLabelOf({ trustLevel: 3, title: '' })).assertEqual('TL3 常客');
      expect(trustLabelOf({ trustLevel: 0 })).assertEqual('TL0 新用户');
    });

    // 站点新增等级导致 trustLevel 超出内置名表时,只显示 TL 号,不能崩也不能显示 undefined。
    it('showsBareTrustLevelWhenLevelOutOfNameTableRange', 0, () => {
      expect(trustLabelOf({ trustLevel: 9 })).assertEqual('TL9');
      expect(trustLabelOf({ trustLevel: -1 })).assertEqual('TL-1');
    });

    it('returnsEmptyLabelWhenDetailOrTrustLevelMissing', 0, () => {
      expect(trustLabelOf(undefined)).assertEqual('');
      expect(trustLabelOf({})).assertEqual('');
    });
  });
}
