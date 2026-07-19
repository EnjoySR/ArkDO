import { describe, it, expect } from '@ohos/hypium';
import { TopicPage, TopicService } from '../main/ets/services/topic/TopicService';
import { Topic } from '../main/ets/models/Topic';
import { TopicDetail } from '../main/ets/models/TopicDetail';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';

class FakeBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';
  postedPath: string = '';
  postedBody: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.postedPath = path;
    this.postedBody = body;
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    this.postedPath = path;
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    this.postedPath = path;
    this.postedBody = body;
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.postedPath = path;
    this.postedBody = body;
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.postedPath = path;
    this.postedBody = body;
    return Promise.resolve(this.result);
  }

  // 接口占位:本套测试不触及图片上传,只为满足 JsonNetworkClient 而实现。
  uploadImage(base64: string, fileName: string, mimeType: string): Promise<NetworkResult<string>> {
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

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPaths.push(path);
    const result: NetworkResult<string> = this.results[this.index];
    this.index++;
    return Promise.resolve(result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPaths.push(path);
    const result: NetworkResult<string> = this.results[this.index];
    this.index++;
    return Promise.resolve(result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPaths.push(path);
    const result: NetworkResult<string> = this.results[this.index];
    this.index++;
    return Promise.resolve(result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPaths.push(path);
    const result: NetworkResult<string> = this.results[this.index];
    this.index++;
    return Promise.resolve(result);
  }

  // 接口占位:本套测试不触及图片上传,只为满足 JsonNetworkClient 而实现。
  // 与其它方法一致从序列取值,避免误用时静默返回错位的结果。
  uploadImage(base64: string, fileName: string, mimeType: string): Promise<NetworkResult<string>> {
    const result: NetworkResult<string> = this.results[this.index];
    this.index++;
    return Promise.resolve(result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPaths.push(path);
    const result: NetworkResult<string> = this.results[this.index];
    this.index++;
    return Promise.resolve(result);
  }
}

export default function topicServiceTest() {
  describe('topicServiceTest', () => {
    it('loadsLatestTopicsFromDiscoursePayload', 0, async () => {
      const payload: string = '{"topic_list":{"topics":[{"id":42,"title":"ArkDO 第二阶段","slug":"arkdo-phase-two","category_id":36,"tags":["快问快答",{"name":"高级推广","slug":"1514-tag"}],"posts_count":5,"reply_count":4,"like_count":9,"created_at":"2026-07-03T00:00:00.000Z","last_posted_at":"2026-07-03T00:10:00.000Z","posters":[{"user_id":7,"description":"原始作者"}]}]},"users":[{"id":7,"username":"linuxdo_user","name":"Linux.do User","avatar_template":"/user_avatar/linux.do/linuxdo_user/{size}/1_2.png"}]}';
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
      expect(result.data?.[0].categoryId).assertEqual(36);
      expect(result.data?.[0].tags.length).assertEqual(2);
      expect(result.data?.[0].tags[0].name).assertEqual('快问快答');
      expect(result.data?.[0].tags[1].name).assertEqual('高级推广');
      expect(result.data?.[0].tags[1].slug).assertEqual('1514-tag');
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

    it('loadsTopicDetailFromDiscoursePayload', 0, async () => {
      const payload: string = '{"id":42,"title":"ArkDO 第二阶段","slug":"arkdo-phase-two","category_id":36,"tags":["快问快答",{"name":"高级推广","slug":"1514-tag"}],"posts_count":2,"reply_count":1,"like_count":3,"views":128,"created_at":"2026-07-03T00:00:00.000Z","post_stream":{"posts":[{"id":100,"topic_id":42,"post_number":1,"username":"alice","name":"Alice","avatar_template":"/user_avatar/linux.do/alice/{size}/1_2.png","created_at":"2026-07-03T00:01:00.000Z","cooked":"<p>Hello <strong>ArkDO</strong>&amp; Linux.do</p>","like_count":2},{"id":101,"topic_id":42,"post_number":2,"username":"bob","name":"Bob","avatar_template":"/user_avatar/linux.do/bob/{size}/1_2.png","created_at":"2026-07-03T00:02:00.000Z","cooked":"<p>第二条回复<br>继续讨论</p>","reply_count":1}]}}';
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: payload
      });
      const service: TopicService = new TopicService(bridge);

      const result: NetworkResult<TopicDetail> = await service.getTopicDetail(42, 'arkdo-phase-two');

      expect(bridge.requestedPath).assertEqual('/t/arkdo-phase-two/42.json');
      expect(result.success).assertTrue();
      expect(result.data?.id).assertEqual(42);
      expect(result.data?.title).assertEqual('ArkDO 第二阶段');
      expect(result.data?.categoryId).assertEqual(36);
      expect(result.data?.tags.length).assertEqual(2);
      expect(result.data?.tags[0].name).assertEqual('快问快答');
      expect(result.data?.tags[1].name).assertEqual('高级推广');
      expect(result.data?.tags[1].slug).assertEqual('1514-tag');
      expect(result.data?.viewCount).assertEqual(128);
      expect(result.data?.posts.length).assertEqual(2);
      expect(result.data?.posts[0].author?.username).assertEqual('alice');
      expect(result.data?.posts[0].plainText).assertEqual('Hello ArkDO& Linux.do');
      expect(result.data?.posts[1].plainText).assertEqual('第二条回复\n继续讨论');
    });

    it('mapsAnimatedAvatarForPostAuthor', 0, async () => {
      const payload: string = '{"id":7,"title":"动图头像","post_stream":{"posts":[{"id":70,"topic_id":7,"post_number":1,"username":"torvalds","name":"Linus","avatar_template":"/user_avatar/linux.do/torvalds/{size}/1_2.png","animated_avatar":"//cdn.ldstatic.com/original/4X/a/b/c.gif","cooked":"<p>hi</p>"}]}}';
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: payload
      });
      const service: TopicService = new TopicService(bridge);

      const result: NetworkResult<TopicDetail> = await service.getTopicDetail(7, 'topic');

      expect(result.success).assertTrue();
      expect(result.data?.posts[0].author?.animatedAvatar).assertEqual('//cdn.ldstatic.com/original/4X/a/b/c.gif');
      expect(result.data?.posts[0].author?.avatarTemplate).assertEqual('/user_avatar/linux.do/torvalds/{size}/1_2.png');
    });

    it('mapsReadStateFromTopicDetailPayload', 0, async () => {
      const payload: string = '{"id":88,"title":"已读状态","last_read_post_number":2,"highest_post_number":3,"unread_posts":1,"post_stream":{"posts":[{"id":1,"topic_id":88,"post_number":1,"username":"a","cooked":"<p>1</p>","read":true},{"id":2,"topic_id":88,"post_number":2,"username":"b","cooked":"<p>2</p>","read":false},{"id":3,"topic_id":88,"post_number":3,"username":"c","cooked":"<p>3</p>"}]}}';
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: payload
      });
      const service: TopicService = new TopicService(bridge);

      const result: NetworkResult<TopicDetail> = await service.getTopicDetail(88);

      expect(result.success).assertTrue();
      expect(result.data?.lastReadPostNumber).assertEqual(2);
      expect(result.data?.highestPostNumber).assertEqual(3);
      expect(result.data?.unreadPosts).assertEqual(1);
      expect(result.data?.posts[0].read).assertEqual(true);
      expect(result.data?.posts[1].read).assertEqual(false);
      // 无 read 字段的楼层保持 undefined,交给水位线兜底。
      expect(result.data?.posts[2].read === undefined).assertTrue();
    });

    it('encodesTimingsReportAsFormBody', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: ''
      });
      const service: TopicService = new TopicService(bridge);
      const timings: Map<number, number> = new Map();
      timings.set(1, 1001);
      timings.set(2, 3000);

      const result: NetworkResult<string> = await service.reportTimings(2117030, timings, 4001);

      expect(result.success).assertTrue();
      expect(bridge.postedPath).assertEqual('/topics/timings');
      expect(bridge.postedBody).assertEqual('timings%5B1%5D=1001&timings%5B2%5D=3000&topic_time=4001&topic_id=2117030');
    });
  });
}
