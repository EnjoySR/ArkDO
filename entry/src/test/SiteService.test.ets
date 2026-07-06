import { describe, it, expect } from '@ohos/hypium';
import { SiteMetadata, SiteService } from '../main/ets/services/site/SiteService';
import { TopicCategory } from '../main/ets/models/Topic';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../main/ets/services/network/NetworkTypes';

class FakeSiteBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }
}

export default function siteServiceTest() {
  describe('siteServiceTest', () => {
    it('loadsCategoriesFromSitePayload', 0, async () => {
      const payload: string = '{"categories":[{"id":36,"name":"福利羊毛","color":"E45735","text_color":"FFFFFF","slug":"welfare","parent_category_id":12,"uploaded_logo":{"url":"/uploads/default/original/1X/welfare.png"},"icon":"piggy-bank","read_restricted":false},{"id":4,"name":"开发调优","color":"0088CC","text_color":"FFFFFF","slug":"dev","uploaded_logo":"/uploads/default/original/1X/dev.png","read_restricted":true}]}';
      const bridge: FakeSiteBridge = new FakeSiteBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: payload
      });

      const result: NetworkResult<SiteMetadata> = await new SiteService(bridge).getSiteMetadata();

      expect(bridge.requestedPath).assertEqual('/site.json');
      expect(result.success).assertTrue();
      expect(result.data?.categories.length).assertEqual(2);
      const first: TopicCategory | undefined = result.data?.categories[0];
      expect(first?.id).assertEqual(36);
      expect(first?.name).assertEqual('福利羊毛');
      expect(first?.color).assertEqual('E45735');
      expect(first?.textColor).assertEqual('FFFFFF');
      expect(first?.parentCategoryId).assertEqual(12);
      expect(first?.uploadedLogo).assertEqual('/uploads/default/original/1X/welfare.png');
      expect(first?.icon).assertEqual('piggy-bank');
      expect(result.data?.categories[1].uploadedLogo).assertEqual('/uploads/default/original/1X/dev.png');
      expect(result.data?.categories[1].readRestricted).assertTrue();
    });
  });
}
