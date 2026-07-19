import { describe, it, expect } from '@ohos/hypium';
import {
  extractRouteFromDiscoursePayload,
  parsePushNotificationRouteFromParameters,
  resolveDiscoursePushUrl
} from '../main/ets/services/push/PushNotificationNavigation';

// 两个被测函数的形参都是 Object,而 ArkTS 禁止无类型对象字面量(arkts-no-untyped-obj-literals),
// 故在此声明入参的显式形状。生产侧对应的 DiscoursePushPayload / PushClickParameters 未导出,
// 这里按其字段子集自建等价类型即可。
interface TestDiscoursePayload {
  title: string;
  url: string;
}

interface TestPushClickParameters {
  data: string;
}

export default function pushNotificationNavigationTest() {
  describe('pushNotificationNavigationTest', () => {
    it('resolvesRelativeDiscourseTopicUrl', 0, () => {
      expect(resolveDiscoursePushUrl('/t/topic/2590051/99')).assertEqual('https://linux.do/t/topic/2590051/99');
    });

    it('keepsSameHostAbsoluteDiscourseTopicUrl', 0, () => {
      expect(resolveDiscoursePushUrl('https://linux.do/t/topic/2590051/99?u=joey')).assertEqual('https://linux.do/t/topic/2590051/99?u=joey');
    });

    it('extractsRouteFromDiscoursePayload', 0, () => {
      const payload: TestDiscoursePayload = {
        title: 'yiming 回复了您 - LINUX DO',
        url: '/t/topic/2590051/99'
      };
      const route = extractRouteFromDiscoursePayload(payload);

      expect(route?.url).assertEqual('https://linux.do/t/topic/2590051/99');
      expect(route?.title).assertEqual('yiming 回复了您 - LINUX DO');
    });

    it('extractsRouteFromPushKitClickDataString', 0, () => {
      const parameters: TestPushClickParameters = {
        data: '{"arkdo_url":"/t/topic/2590051/99","arkdo_title":"帖子回复"}'
      };
      const route = parsePushNotificationRouteFromParameters(parameters);

      expect(route?.url).assertEqual('https://linux.do/t/topic/2590051/99');
      expect(route?.title).assertEqual('帖子回复');
    });
  });
}
