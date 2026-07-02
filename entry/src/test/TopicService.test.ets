import { describe, it, expect } from '@ohos/hypium';
import { TopicPage, TopicService } from '../main/ets/services/topic/TopicService';
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

class SequenceBridge implements JsonNetworkClient {
  private results: NetworkResult<string>[];
  requestedPaths: string[] = [];
  private index: number = 0;

  constructor(results: NetworkResult<string>[]) {
    this.results = results;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPaths.push(path);
    const result: NetworkResult<string> = this.results[this.index];
    this.index++;
    return Promise.resolve(result);
  }
}

export default function topicServiceTest() {
  describe('topicServiceTest', () => {
    it('loadsLatestTopicsFromDiscoursePayload', 0, async () => {
      const payload: string = '{"topic_list":{"topics":[{"id":42,"title":"ArkDO 第二阶段","slug":"arkdo-phase-two","posts_count":5,"reply_count":4,"like_count":9,"created_at":"2026-07-03T00:00:00.000Z","last_posted_at":"2026-07-03T00:10:00.000Z","posters":[{"user_id":7,"description":"原始作者"}]}]},"users":[{"id":7,"username":"linuxdo_user","name":"Linux.do User","avatar_template":"/user_avatar/linux.do/linuxdo_user/{size}/1_2.png"}]}';
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

    it('usesFirstPosterUserIdAsTopicAuthor', 0, async () => {
      const payload: string = '{"topic_list":{"topics":[{"id":43,"title":"中文 poster 描述","posts_count":1,"reply_count":0,"like_count":0,"posters":[{"user_id":8,"description":"原始作者"},{"user_id":9,"description":"最近回复"}]}]},"users":[{"id":8,"username":"first_user","name":"First User","avatar_template":"/first/{size}.png"},{"id":9,"username":"wrong_user","name":"Wrong User","avatar_template":"/wrong/{size}.png"}]}';
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: payload
      });
      const service: TopicService = new TopicService(bridge);

      const result: NetworkResult<Topic[]> = await service.getLatestTopics();

      expect(result.success).assertTrue();
      expect(result.data?.[0].author?.id).assertEqual(8);
      expect(result.data?.[0].author?.username).assertEqual('first_user');
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

    it('loadsPagedLatestTopicsWithMoreFlag', 0, async () => {
      const firstPayload: string = '{"topic_list":{"more_topics_url":"/latest.json?page=1","topics":[{"id":1,"title":"第一页","posts_count":1,"reply_count":0,"like_count":0}]},"users":[]}';
      const secondPayload: string = '{"topic_list":{"topics":[{"id":2,"title":"第二页","posts_count":1,"reply_count":0,"like_count":0}]},"users":[]}';
      const bridge: SequenceBridge = new SequenceBridge([
        {
          success: true,
          statusCode: 200,
          challengeState: ChallengeState.NONE,
          data: firstPayload
        },
        {
          success: true,
          statusCode: 200,
          challengeState: ChallengeState.NONE,
          data: secondPayload
        }
      ]);
      const service: TopicService = new TopicService(bridge);

      const firstPage: NetworkResult<TopicPage> = await service.getLatestTopicsPage(0);
      const secondPage: NetworkResult<TopicPage> = await service.getLatestTopicsPage(1);

      expect(bridge.requestedPaths[0]).assertEqual('/latest.json');
      expect(bridge.requestedPaths[1]).assertEqual('/latest.json?page=1');
      expect(firstPage.success).assertTrue();
      expect(firstPage.data?.topics[0].title).assertEqual('第一页');
      expect(firstPage.data?.page).assertEqual(0);
      expect(firstPage.data?.hasMore).assertTrue();
      expect(secondPage.success).assertTrue();
      expect(secondPage.data?.topics[0].title).assertEqual('第二页');
      expect(secondPage.data?.page).assertEqual(1);
      expect(secondPage.data?.hasMore).assertFalse();
    });
  });
}
