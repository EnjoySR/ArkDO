import { describe, it, expect } from '@ohos/hypium';
import {
  formatCount,
  formatJoinDate,
  formatTimeRead,
  trustLabelOf,
  trustLabelWithTitleOf,
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
      expect(TRUST_LEVEL_NAMES[3]).assertEqual('活跃用户');
    });

    // 两个变体的差别是刻意的,由页面布局决定,不是漂移——曾经有人(见 git 历史)把它们
    // "统一"成头衔优先,结果他人主页把同一个头衔显示了两遍。这两条用例就是为了钉住这件事。
    //
    // trustLabelOf:只给等级名。用于页面别处已单独展示头衔的场合(他人主页)。
    it('ignoresSiteTitleAndAlwaysShowsTrustLevelName', 0, () => {
      expect(trustLabelOf({ trustLevel: 3, title: '指导顾问' })).assertEqual('TL3 活跃用户');
      expect(trustLabelOf({ trustLevel: 3 })).assertEqual('TL3 活跃用户');
      expect(trustLabelOf({ trustLevel: 0 })).assertEqual('TL0 新用户');
    });

    // trustLabelWithTitleOf:头衔优先。用于这里是头衔唯一露出的场合(「我的」页)。
    it('prefersSiteTitleWhenLabelIsTheOnlyPlaceTitleAppears', 0, () => {
      expect(trustLabelWithTitleOf({ trustLevel: 3, title: '指导顾问' })).assertEqual('TL3 指导顾问');
      expect(trustLabelWithTitleOf({ trustLevel: 3, title: '' })).assertEqual('TL3 活跃用户');
      expect(trustLabelWithTitleOf({ trustLevel: 3 })).assertEqual('TL3 活跃用户');
    });

    // 站点新增等级导致 trustLevel 超出内置名表时,只显示 TL 号,不能崩也不能显示 undefined。
    it('showsBareTrustLevelWhenLevelOutOfNameTableRange', 0, () => {
      expect(trustLabelOf({ trustLevel: 9 })).assertEqual('TL9');
      expect(trustLabelOf({ trustLevel: -1 })).assertEqual('TL-1');
      // 带头衔的变体在超范围时仍应给出头衔,而不是退化成裸 TL 号。
      expect(trustLabelWithTitleOf({ trustLevel: 9, title: '指导顾问' })).assertEqual('TL9 指导顾问');
      expect(trustLabelWithTitleOf({ trustLevel: 9 })).assertEqual('TL9');
    });

    it('returnsEmptyLabelWhenDetailOrTrustLevelMissing', 0, () => {
      expect(trustLabelOf(undefined)).assertEqual('');
      expect(trustLabelOf({})).assertEqual('');
    });
  });
}
