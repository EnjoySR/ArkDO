import { describe, it, expect } from '@ohos/hypium';
import { UserActivityItem, UserProfileDetail, UserSummary } from '../main/ets/models/UserProfile';
import { AuthService } from '../main/ets/services/auth/AuthService';
import { UserProfileService } from '../main/ets/services/user/UserProfileService';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../main/ets/services/network/NetworkTypes';

class FakeBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';
  requestedMethod: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedMethod = 'GET';
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedMethod = 'POST_FORM';
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedMethod = 'PUT';
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedMethod = 'POST';
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedMethod = 'PUT_FORM';
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedMethod = 'DELETE_FORM';
    return Promise.resolve(this.result);
  }
}

function okResponse(payload: string): NetworkResult<string> {
  return {
    success: true,
    statusCode: 200,
    challengeState: ChallengeState.NONE,
    data: payload
  };
}

export default function userProfileServiceTest() {
  describe('userProfileServiceTest', () => {
    it('parsesProfileDetailFromUserPayload', 0, async () => {
      const payload: string = '{"user":{"id":7,"username":"linuxdo_user","name":"Linux.do User",' +
        '"title":"活跃用户","trust_level":3,"created_at":"2025-02-14T08:00:00.000Z",' +
        '"last_posted_at":"2026-07-08T01:00:00.000Z","badge_count":27,"profile_view_count":5600}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserProfileDetail> = await service.getProfileDetail('linuxdo_user');

      expect(bridge.requestedPath).assertEqual('/u/linuxdo_user.json');
      expect(result.success).assertTrue();
      expect(result.data?.title).assertEqual('活跃用户');
      expect(result.data?.trustLevel).assertEqual(3);
      expect(result.data?.badgeCount).assertEqual(27);
      expect(result.data?.profileViewCount).assertEqual(5600);
    });

    it('parsesSummaryStatsAndTopBadges', 0, async () => {
      const payload: string = '{"user_summary":{"days_visited":512,"time_read":244800,' +
        '"likes_given":1200,"likes_received":3400,"topic_count":42,"post_count":866,' +
        '"topics_entered":3200,"solved_count":9,' +
        '"badges":[{"badge_id":9,"count":3},{"badge_id":3,"count":1}]},' +
        '"badges":[' +
        '{"id":3,"name":"三级用户","badge_type_id":1,"icon":"user","image_url":null},' +
        '{"id":9,"name":"读者","badge_type_id":3,"icon":"book-open-reader","image_url":null},' +
        '{"id":120,"name":"龙行龘龘","badge_type_id":1,"icon":"certificate",' +
        '"image_url":"https://cdn3.ldstatic.com/original/2X/3/badge.png"}]}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserSummary> = await service.getSummary('linuxdo_user');

      expect(bridge.requestedPath).assertEqual('/u/linuxdo_user/summary.json');
      expect(result.success).assertTrue();
      expect(result.data?.stats.daysVisited).assertEqual(512);
      expect(result.data?.stats.timeReadSeconds).assertEqual(244800);
      expect(result.data?.stats.solvedCount).assertEqual(9);
      expect(result.data?.topBadges.length).assertEqual(3);
      expect(result.data?.topBadges[0].badgeTypeId).assertEqual(1);
      // 图标徽章:icon 透传,无 imageUrl;获得次数按 badge_id 匹配。
      expect(result.data?.topBadges[0].icon).assertEqual('user');
      expect(result.data?.topBadges[0].imageUrl).assertEqual(undefined);
      expect(result.data?.topBadges[0].grantCount).assertEqual(1);
      expect(result.data?.topBadges[1].icon).assertEqual('book-open-reader');
      expect(result.data?.topBadges[1].grantCount).assertEqual(3);
      // 图片徽章:imageUrl 优先,icon 不再透传。
      expect(result.data?.topBadges[2].imageUrl).assertEqual('https://cdn3.ldstatic.com/original/2X/3/badge.png');
      expect(result.data?.topBadges[2].icon).assertEqual(undefined);
      expect(result.data?.topBadges[2].grantCount).assertEqual(undefined);
    });

    it('summaryWithoutSolvedCountLeavesItUndefined', 0, async () => {
      const payload: string = '{"user_summary":{"days_visited":1,"time_read":60,"likes_given":0,' +
        '"likes_received":0,"topic_count":0,"post_count":0,"topics_entered":0}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserSummary> = await service.getSummary('linuxdo_user');

      expect(result.success).assertTrue();
      expect(result.data?.stats.solvedCount).assertEqual(undefined);
      expect(result.data?.topBadges.length).assertEqual(0);
    });

    it('mapsRecentActivityAndSkipsInvalidEntries', 0, async () => {
      const payload: string = '{"user_actions":[' +
        '{"action_type":4,"created_at":"2026-07-08T01:00:00.000Z","topic_id":100,"post_number":1,' +
        '"title":"新话题","category_id":4},' +
        '{"action_type":5,"created_at":"2026-07-07T01:00:00.000Z","topic_id":200,"post_number":15,' +
        '"title":"被回复的话题","category_id":11},' +
        '{"action_type":5,"created_at":"2026-07-06T01:00:00.000Z","topic_id":300},' +
        '{"action_type":4,"created_at":"2026-07-05T01:00:00.000Z","topic_id":400,"post_number":1,"title":"第四条"}]}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserActivityItem[]> = await service.getRecentActivity('linuxdo_user', 3);

      expect(bridge.requestedPath).assertEqual('/user_actions.json?offset=0&username=linuxdo_user&filter=4,5');
      expect(result.success).assertTrue();
      // 缺 title 的第三条被跳过,limit=3 仍取满 3 条有效数据。
      expect(result.data?.length).assertEqual(3);
      expect(result.data?.[0].topicId).assertEqual(100);
      expect(result.data?.[0].postNumber).assertEqual(undefined);
      expect(result.data?.[1].postNumber).assertEqual(15);
      expect(result.data?.[2].topicId).assertEqual(400);
    });

    it('getActivityStripsExcerptHtmlAndReportsNoMoreOnShortPage', 0, async () => {
      const payload: string = '{"user_actions":[' +
        '{"action_type":1,"created_at":"2026-07-08T01:00:00.000Z","topic_id":100,"post_number":6,' +
        '"title":"被点赞的帖","category_id":4,"excerpt":"看 <a class=\\"mention\\">@x</a> 说的 &amp; 对"}]}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result = await service.getActivity('linuxdo_user', '1', 20);

      expect(bridge.requestedPath).assertEqual('/user_actions.json?offset=20&username=linuxdo_user&filter=1');
      expect(result.success).assertTrue();
      expect(result.data?.items.length).assertEqual(1);
      expect(result.data?.items[0].excerpt).assertEqual('看 @x 说的 & 对');
      expect(result.data?.items[0].postNumber).assertEqual(6);
      // 本页不足一页(<30)→ 没有更多。
      expect(result.data?.hasMore).assertFalse();
    });

    it('logoutSendsDeleteToSessionEndpoint', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(okResponse('{"success":"OK"}'));
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<boolean> = await service.logout('linuxdo_user');

      expect(bridge.requestedPath).assertEqual('/session/linuxdo_user');
      expect(bridge.requestedMethod).assertEqual('DELETE_FORM');
      expect(result.success).assertTrue();
      expect(result.data).assertTrue();
    });

    it('parsesDraftCountFromCurrentSession', 0, async () => {
      const payload: string = '{"current_user":{"id":7,"username":"linuxdo_user","draft_count":2}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: AuthService = new AuthService(bridge);

      const result = await service.getCurrentUser();

      expect(result.success).assertTrue();
      expect(result.data?.draftCount).assertEqual(2);
    });
  });
}
