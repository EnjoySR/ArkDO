import { describe, it, expect } from '@ohos/hypium';
import { EndorsableCategoriesResult } from '../main/ets/models/UserProfile';
import { UserRelationService } from '../main/ets/services/user/UserRelationService';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../main/ets/services/network/NetworkTypes';

// 记录最后一次请求的方法/路径/body:写操作用错 method 或 body 就会误操作,必须锁死。
class SpyBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  lastMethod: string = '';
  lastPath: string = '';
  lastBody: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.lastMethod = 'GET';
    this.lastPath = path;
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.lastMethod = 'POST_FORM';
    this.lastPath = path;
    this.lastBody = body;
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    this.lastMethod = 'POST';
    this.lastPath = path;
    this.lastBody = body;
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    this.lastMethod = 'PUT';
    this.lastPath = path;
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.lastMethod = 'PUT_FORM';
    this.lastPath = path;
    this.lastBody = body;
    return Promise.resolve(this.result);
  }

  uploadImage(base64: string, fileName: string, mimeType: string): Promise<NetworkResult<string>> {
    // 接口占位:本套测试不触及图片上传,只为满足 JsonNetworkClient 而实现。
    this.lastMethod = 'UPLOAD_IMAGE';
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.lastMethod = 'DELETE_FORM';
    this.lastPath = path;
    this.lastBody = body;
    return Promise.resolve(this.result);
  }
}

function okResponse(payload: string): NetworkResult<string> {
  return { success: true, statusCode: 200, challengeState: ChallengeState.NONE, data: payload };
}

export default function userRelationServiceTest() {
  describe('userRelationServiceTest', () => {
    // 关注:PUT /follow/{u}.json 空 body(对齐官网 content-length:0)。
    it('followUserPutsToFollowEndpoint', 0, async () => {
      const bridge: SpyBridge = new SpyBridge(okResponse('{"success":"OK"}'));
      const service: UserRelationService = new UserRelationService(bridge);

      const result: NetworkResult<boolean> = await service.followUser('kevin');

      expect(bridge.lastMethod).assertEqual('PUT');
      expect(bridge.lastPath).assertEqual('/follow/kevin.json');
      expect(result.success).assertTrue();
      expect(result.data).assertEqual(true);
    });

    // 取消关注:DELETE 同一端点。用错成 PUT 就会变成「再次关注」。
    it('unfollowUserDeletesFollowEndpoint', 0, async () => {
      const bridge: SpyBridge = new SpyBridge(okResponse('{"success":"OK"}'));
      const service: UserRelationService = new UserRelationService(bridge);

      await service.unfollowUser('kevin');

      expect(bridge.lastMethod).assertEqual('DELETE_FORM');
      expect(bridge.lastPath).assertEqual('/follow/kevin.json');
    });

    // 认可分类列表:形状取自 /category-experts/endorsable-categories 实测响应。
    it('parsesEndorsableCategoriesAndRemaining', 0, async () => {
      const payload: string = '{"categories":[' +
        '{"id":32,"name":"读书成诗","color":"e0d900"},' +
        '{"id":4,"name":"开发调优","color":"32c3c3"},' +
        // 缺 name 的条目丢弃。
        '{"id":99}],' +
        '"extras":{"remaining_endorsements":2}}';
      const bridge: SpyBridge = new SpyBridge(okResponse(payload));
      const service: UserRelationService = new UserRelationService(bridge);

      const result: NetworkResult<EndorsableCategoriesResult> = await service.getEndorsableCategories('kevin');

      expect(bridge.lastMethod).assertEqual('GET');
      expect(bridge.lastPath).assertEqual('/category-experts/endorsable-categories/kevin.json');
      expect(result.success).assertTrue();
      expect(result.data?.categories.length).assertEqual(2);
      expect(result.data?.categories[0].name).assertEqual('读书成诗');
      expect(result.data?.categories[1].id).assertEqual(4);
      expect(result.data?.remainingEndorsements).assertEqual(2);
    });

    // 提交认可:PUT + form body categoryIds[]=N,多选用 & 连接。body 写错服务端认可到别的分类。
    it('endorsePutsCategoryIdsAsFormBody', 0, async () => {
      const bridge: SpyBridge = new SpyBridge(okResponse('{"category_expert_endorsements":[{"id":1,"category_id":4}]}'));
      const service: UserRelationService = new UserRelationService(bridge);

      const result: NetworkResult<boolean> = await service.endorseCategories('kevin', [4, 11]);

      expect(bridge.lastMethod).assertEqual('PUT_FORM');
      expect(bridge.lastPath).assertEqual('/category-experts/endorse/kevin.json');
      expect(bridge.lastBody).assertEqual('categoryIds[]=4&categoryIds[]=11');
      expect(result.success).assertTrue();
    });

    // 空选择不发请求:防止「认可」按钮误触发一次空提交。
    it('endorseWithNoCategoriesDoesNotRequest', 0, async () => {
      const bridge: SpyBridge = new SpyBridge(okResponse('{}'));
      const service: UserRelationService = new UserRelationService(bridge);

      const result: NetworkResult<boolean> = await service.endorseCategories('kevin', []);

      expect(result.success).assertFalse();
      // 没有触达 bridge:方法记录仍是初始空串。
      expect(bridge.lastMethod).assertEqual('');
    });
  });
}
