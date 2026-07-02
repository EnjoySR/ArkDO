import { describe, it, expect } from '@ohos/hypium';
import { TopicService } from '../main/ets/services/topic/TopicService';
import { Topic } from '../main/ets/models/Topic';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';

class FakeBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }
}

export default function topicServiceTest() {
  describe('topicServiceTest', () => {
    it('loadsLatestTopicsFromDiscoursePayload', 0, async () => {
      const payload: string = '{"topic_list":{"topics":[{"id":42,"title":"ArkDO 第二阶段","slug":"arkdo-phase-two","posts_count":5,"reply_count":4,"like_count":9,"created_at":"2026-07-03T00:00:00.000Z","last_posted_at":"2026-07-03T00:10:00.000Z","posters":[{"user_id":7,"description":"Original Poster"}]}]},"users":[{"id":7,"username":"linuxdo_user","name":"Linux.do User","avatar_template":"/user_avatar/linux.do/linuxdo_user/{size}/1_2.png"}]}';
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: payload
      });
      const service: TopicService = new TopicService(bridge);

      const result: NetworkResult<Topic[]> = await service.getLatestTopics();

      expect(bridge.requestedPath).assertEqual('/latest.json');
      expect(result.success).assertTrue();
      expect(result.data?.length).assertEqual(1);
      expect(result.data?.[0].id).assertEqual(42);
      expect(result.data?.[0].title).assertEqual('ArkDO 第二阶段');
      expect(result.data?.[0].postsCount).assertEqual(5);
      expect(result.data?.[0].replyCount).assertEqual(4);
      expect(result.data?.[0].author?.username).assertEqual('linuxdo_user');
    });

    it('returnsUnexpectedResponseForInvalidTopicPayload', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: '{"topic_list":{}}'
      });
      const service: TopicService = new TopicService(bridge);

      const result: NetworkResult<Topic[]> = await service.getLatestTopics();

      expect(result.success).assertFalse();
      expect(result.statusCode).assertEqual(200);
      expect(result.error?.code).assertEqual(NetworkErrorCode.UNEXPECTED_RESPONSE);
    });

    it('preservesChallengeRequiredResult', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: false,
        statusCode: 403,
        challengeState: ChallengeState.REQUIRED,
        error: {
          code: NetworkErrorCode.CHALLENGE_REQUIRED,
          message: 'Cloudflare challenge required.',
          requiresChallenge: true
        }
      });
      const service: TopicService = new TopicService(bridge);

      const result: NetworkResult<Topic[]> = await service.getLatestTopics();

      expect(result.success).assertFalse();
      expect(result.statusCode).assertEqual(403);
      expect(result.challengeState).assertEqual(ChallengeState.REQUIRED);
      expect(result.error?.requiresChallenge).assertTrue();
    });
  });
}
