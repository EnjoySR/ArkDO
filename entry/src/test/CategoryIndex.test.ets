import { describe, it, expect } from '@ohos/hypium';
import { TopicCategory } from '../main/ets/models/Topic';
import { CategoryIndex } from '../main/ets/services/site/CategoryIndex';
import { UserProfileCache } from '../main/ets/services/user/UserProfileCache';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../main/ets/services/network/NetworkTypes';

class CountingBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestCount: number = 0;

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestCount += 1;
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }
}

const SITE_PAYLOAD: string =
  '{"categories":[{"id":4,"name":"开发调优","color":"0088CC","text_color":"FFFFFF"}]}';

function okSite(): NetworkResult<string> {
  return {
    success: true,
    statusCode: 200,
    challengeState: ChallengeState.NONE,
    data: SITE_PAYLOAD
  };
}

function failSite(): NetworkResult<string> {
  return {
    success: false,
    statusCode: 503,
    challengeState: ChallengeState.NONE
  };
}

export default function categoryIndexTest() {
  describe('categoryIndexTest', () => {
    it('cachesCategoriesAcrossInstances', 0, async () => {
      CategoryIndex.resetForTest();
      const bridge: CountingBridge = new CountingBridge(okSite());

      const first: TopicCategory[] | null =
        await new CategoryIndex().loadIfNeeded(bridge, true, false, '[test]');
      const second: TopicCategory[] | null =
        await new CategoryIndex().loadIfNeeded(bridge, true, false, '[test]');

      // 第二个实例(模拟另一页面/重进页面)命中静态缓存,不再发 /site.json。
      expect(bridge.requestCount).assertEqual(1);
      expect(first?.length).assertEqual(1);
      expect(second?.length).assertEqual(1);
      expect(second?.[0].name).assertEqual('开发调优');
    });

    it('skipsWhenPageAlreadyLoadedOrNotReady', 0, async () => {
      CategoryIndex.resetForTest();
      const bridge: CountingBridge = new CountingBridge(okSite());

      const notReady: TopicCategory[] | null =
        await new CategoryIndex().loadIfNeeded(bridge, false, false, '[test]');
      const alreadyLoaded: TopicCategory[] | null =
        await new CategoryIndex().loadIfNeeded(bridge, true, true, '[test]');

      expect(notReady).assertNull();
      expect(alreadyLoaded).assertNull();
      expect(bridge.requestCount).assertEqual(0);
    });

    it('failureDoesNotPoisonCacheAndRetries', 0, async () => {
      CategoryIndex.resetForTest();
      const bridge: CountingBridge = new CountingBridge(failSite());

      const first: TopicCategory[] | null =
        await new CategoryIndex().loadIfNeeded(bridge, true, false, '[test]');
      const second: TopicCategory[] | null =
        await new CategoryIndex().loadIfNeeded(bridge, true, false, '[test]');

      // 失败不写缓存;下次调用重试,而不是永远拿到 null。
      expect(first).assertNull();
      expect(second).assertNull();
      expect(bridge.requestCount).assertEqual(2);
    });

    it('userProfileCacheStoresPerUsername', 0, () => {
      UserProfileCache.resetForTest();

      UserProfileCache.setDetail('alice', { id: 1, username: 'alice', trustLevel: 3 });
      UserProfileCache.setActivity('alice', [{ actionType: 4, topicId: 100, title: '话题', excerpt: '', tags: [] }]);

      expect(UserProfileCache.getDetail('alice')?.trustLevel).assertEqual(3);
      expect(UserProfileCache.getActivity('alice')?.length).assertEqual(1);
      expect(UserProfileCache.getDetail('bob')).assertUndefined();
      expect(UserProfileCache.getSummary('alice')).assertUndefined();
    });
  });
}
