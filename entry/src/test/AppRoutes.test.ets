import { describe, it, expect } from '@ohos/hypium';
import { AppRouteName, buildTopicDetailRouteParam, isTopicDetailRouteParam, TopicDetailRouteParam } from '../main/ets/navigation/AppRoutes';

interface InvalidTopicIdRouteParam {
  topicId: string;
  title: string;
}

interface MissingTitleRouteParam {
  topicId: number;
}

export default function appRoutesTest() {
  describe('appRoutesTest', () => {
    it('buildsTopicDetailRouteParamFromTopicFields', 0, () => {
      const param: TopicDetailRouteParam = buildTopicDetailRouteParam(42, 'arkdo-phase-two', 'ArkDO 第二阶段');

      expect(isTopicDetailRouteParam(param)).assertTrue();
      expect(param.topicId).assertEqual(42);
      expect(param.slug).assertEqual('arkdo-phase-two');
      expect(param.title).assertEqual('ArkDO 第二阶段');
      expect(AppRouteName.TOPIC_DETAIL).assertEqual('topicDetail');
    });

    it('rejectsInvalidTopicDetailRouteParam', 0, () => {
      const invalidTopicIdParam: InvalidTopicIdRouteParam = { topicId: '42', title: 'Bad' };
      const missingTitleParam: MissingTitleRouteParam = { topicId: 42 };

      expect(isTopicDetailRouteParam(invalidTopicIdParam)).assertFalse();
      expect(isTopicDetailRouteParam(missingTitleParam)).assertFalse();
      expect(isTopicDetailRouteParam(undefined)).assertFalse();
    });
  });
}
