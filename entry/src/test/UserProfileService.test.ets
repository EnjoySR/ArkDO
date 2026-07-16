import { describe, it, expect } from '@ohos/hypium';
import { SolvedPostPage, UserActivityItem, UserProfileDetail, UserSummary } from '../main/ets/models/UserProfile';
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

    // 形状取自 /u/kevin.json 实测响应:他人主页身份区要自己渲染头像与 flair,
    // 这些字段此前全被丢弃(「我的」页有现成的 accountUser,不需要它们)。
    it('mapsAvatarFlairAndBioFromUserPayload', 0, async () => {
      const payload: string = '{"user":{"id":142,"username":"kevin","name":"kevin",' +
        '"title":"不二之选","trust_level":4,"created_at":"2024-01-18T01:52:06.248Z",' +
        '"last_posted_at":"2026-07-16T03:31:07.090Z","badge_count":49,"profile_view_count":17304,' +
        '"avatar_template":"/user_avatar/linux.do/kevin/{size}/408759_2.png","animated_avatar":null,' +
        '"flair_url":"https://cdn3.ldstatic.com/original/4X/d/4/9/d4941ba.gif",' +
        // 实测 flair_bg_color 是空串(图片形态的 flair 不需要底色圆)。
        '"flair_bg_color":"","flair_color":"ff6600","flair_name":"g-secret",' +
        '"bio_excerpt":"<img src=\\"/images/emoji/twemoji/white_check_mark.png?v=15\\" ' +
        'title=\\":white_check_mark:\\" class=\\"emoji\\" width=\\"20\\"> 此用户已获搞七捻三认证<br>\\n"}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserProfileDetail> = await service.getProfileDetail('kevin');

      expect(result.success).assertTrue();
      expect(result.data?.avatarTemplate).assertEqual('/user_avatar/linux.do/kevin/{size}/408759_2.png');
      // animated_avatar 为 null 时不设,UserAvatar 回落到静态头像候选。
      expect(result.data?.animatedAvatar).assertEqual(undefined);
      expect(result.data?.flairUrl).assertEqual('https://cdn3.ldstatic.com/original/4X/d/4/9/d4941ba.gif');
      expect(result.data?.flairName).assertEqual('g-secret');
      expect(result.data?.flairColor).assertEqual('ff6600');
      // 空串不写进模型:否则展示层会拿空串当颜色用。
      expect(result.data?.flairBgColor).assertEqual(undefined);
      // bio_excerpt 是 HTML(还内嵌 emoji <img>),身份区是纯 Text,标签须剥干净。
      expect(result.data?.bioExcerpt).assertEqual('此用户已获搞七捻三认证');
      expect(result.data?.title).assertEqual('不二之选');
      expect(result.data?.badgeCount).assertEqual(49);
    });

    // 昵称后的状态表情(user.status.emoji),与帖子详情同源。
    // (昵称后徽章图标不做:个人页接口只给精选徽章,与帖子头的 show_in_post_header 徽章两套数据,凑不到一致。)
    it('mapsStatusEmojiFromUserStatus', 0, async () => {
      const payload: string = '{"user":{"id":142,"username":"kevin",' +
        '"status":{"emoji":"nerd_face","description":"当牛马"}}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserProfileDetail> = await service.getProfileDetail('kevin');

      expect(result.success).assertTrue();
      expect(result.data?.statusEmoji).assertEqual('nerd_face');
    });

    // discourse-follow 字段:false 是有效值(未关注),不能被 && 短路当成缺失丢掉。
    it('mapsFollowStateIncludingFalseValues', 0, async () => {
      const payload: string = '{"user":{"id":142,"username":"kevin",' +
        '"can_follow":true,"is_followed":false,"total_followers":268,"total_following":56}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserProfileDetail> = await service.getProfileDetail('kevin');

      expect(result.success).assertTrue();
      expect(result.data?.canFollow).assertEqual(true);
      // 关键:未关注是 false 而不是 undefined,按钮才能画成「关注」而非整个不显示。
      expect(result.data?.isFollowed).assertEqual(false);
      expect(result.data?.totalFollowers).assertEqual(268);
      expect(result.data?.totalFollowing).assertEqual(56);
    });

    // 站点没启用 follow 插件时字段整体缺席:canFollow 为 undefined,展示层据此隐藏关注按钮。
    it('leavesFollowStateUndefinedWhenPluginFieldsAbsent', 0, async () => {
      const payload: string = '{"user":{"id":7,"username":"linuxdo_user"}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserProfileDetail> = await service.getProfileDetail('linuxdo_user');

      expect(result.data?.canFollow).assertEqual(undefined);
      expect(result.data?.isFollowed).assertEqual(undefined);
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

    // 形状取自 /u/kevin/summary.json 实测响应。两个关键点都曾猜错过:
    // 1) topics 在顶层而非 user_summary 里,且是「所有被引用话题」的字典——
    //    热门话题只能按 user_summary.topic_ids 挑,否则回复所在的话题会混进热门话题。
    // 2) replies 只有 {topic_id, post_number, like_count, created_at},标题要回顶层 topics 关联。
    it('picksTopTopicsByTopicIdsAndJoinsRepliesToTopics', 0, async () => {
      const payload: string = '{"topics":[' +
        '{"id":17895,"title":"分享一点Docker的学习笔记","slug":"topic","posts_count":291,' +
        '"category_id":4,"like_count":915,"created_at":"2024-02-22T13:16:45.458Z"},' +
        // 这条只是热门回复所在的话题,不在 topic_ids 里,不该出现在热门话题中。
        '{"id":854979,"title":"那就枪口抬高一寸","slug":"topic","posts_count":699,' +
        '"category_id":2,"like_count":1590,"created_at":"2025-08-09T18:24:55.922Z"}],' +
        '"user_summary":{"days_visited":801,"time_read":1277810,"likes_given":1623,' +
        '"likes_received":4997,"topic_count":37,"post_count":1509,"topics_entered":15659,' +
        '"solved_count":4,"topic_ids":[17895],' +
        '"replies":[{"post_number":6,"like_count":133,' +
        '"created_at":"2025-08-09T18:25:52.940Z","topic_id":854979}],' +
        '"most_liked_users":[{"id":1,"username":"neo","name":"Neo","count":398,' +
        '"avatar_template":"/user_avatar/linux.do/neo/{size}/12_2.png","flair_url":"gem",' +
        '"flair_bg_color":"BE123C","flair_color":"FFFFFF","flair_name":"g-premium"}],' +
        '"most_replied_to_users":[{"id":58,"username":"King-Huiwen-of-Qin","name":"","count":22,' +
        '"avatar_template":"/user_avatar/linux.do/king-huiwen-of-qin/{size}/387331_2.png"}],' +
        '"most_liked_by_users":[{"id":17776,"username":"fogupro","name":"Fogupro","count":27,' +
        '"avatar_template":"/user_avatar/linux.do/fogupro/{size}/1858676_2.png"}]}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserSummary> = await service.getSummary('kevin');

      expect(result.success).assertTrue();
      // 热门话题只认 topic_ids:854979 虽在 topics 里,但它是回复所在话题,不能混进来。
      expect(result.data?.topTopics.length).assertEqual(1);
      expect(result.data?.topTopics[0].topicId).assertEqual(17895);
      expect(result.data?.topTopics[0].title).assertEqual('分享一点Docker的学习笔记');
      expect(result.data?.topTopics[0].likeCount).assertEqual(915);
      expect(result.data?.topTopics[0].categoryId).assertEqual(4);

      // 热门回复:标题/分类来自关联的话题,时间与楼号来自回复自身。
      expect(result.data?.topReplies.length).assertEqual(1);
      expect(result.data?.topReplies[0].topicTitle).assertEqual('那就枪口抬高一寸');
      expect(result.data?.topReplies[0].topicId).assertEqual(854979);
      expect(result.data?.topReplies[0].postNumber).assertEqual(6);
      expect(result.data?.topReplies[0].likeCount).assertEqual(133);
      expect(result.data?.topReplies[0].categoryId).assertEqual(2);
      expect(result.data?.topReplies[0].createdAt).assertEqual('2025-08-09T18:25:52.940Z');

      // 互动圈三行:服务端已按次数降序,顺序即强弱。
      expect(result.data?.mostLikedUsers.length).assertEqual(1);
      expect(result.data?.mostLikedUsers[0].user.username).assertEqual('neo');
      expect(result.data?.mostLikedUsers[0].user.displayName).assertEqual('Neo');
      expect(result.data?.mostLikedUsers[0].count).assertEqual(398);
      expect(result.data?.mostLikedUsers[0].user.flairUrl).assertEqual('gem');
      expect(result.data?.mostRepliedToUsers[0].user.username).assertEqual('King-Huiwen-of-Qin');
      expect(result.data?.mostRepliedToUsers[0].count).assertEqual(22);
      // name 为空串时不设 displayName,展示层回落到 username。
      expect(result.data?.mostRepliedToUsers[0].user.displayName).assertEqual(undefined);
      expect(result.data?.mostLikedByUsers[0].user.username).assertEqual('fogupro');
      expect(result.data?.mostLikedByUsers[0].count).assertEqual(27);
    });

    // 回复关联不到话题时整条丢弃:没有标题的行没法看。
    it('dropsTopReplyWhenTopicIsMissing', 0, async () => {
      const payload: string = '{"topics":[],' +
        '"user_summary":{"days_visited":1,"time_read":60,"likes_given":0,"likes_received":0,' +
        '"topic_count":0,"post_count":0,"topics_entered":0,"topic_ids":[999],' +
        '"replies":[{"post_number":6,"like_count":133,"topic_id":854979}]}}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<UserSummary> = await service.getSummary('kevin');

      expect(result.success).assertTrue();
      expect(result.data?.topReplies.length).assertEqual(0);
      // topic_ids 指向的话题不在 topics 里也一样丢弃,不产生空标题行。
      expect(result.data?.topTopics.length).assertEqual(0);
    });

    // 形状取自 /solution/by_user.json 实测响应。excerpt 带 HTML,需转纯文本。
    it('parsesSolvedPostsAndStripsExcerptHtml', 0, async () => {
      const payload: string = '{"user_solved_posts":[' +
        '{"created_at":"2025-11-05T03:12:07.944Z","category_id":4,' +
        '"excerpt":"不要用官方给你的这个配置 \\n<a href=\\"https://linux.do/t/topic/1011958\\">Codex CLI</a>",' +
        '"post_id":10019971,"post_number":5,"slug":"topic","topic_id":1058508,' +
        '"topic_title":"codex 里serena 配置问题求助","username":"kevin"},' +
        // 缺 topic_title 的条目丢弃。
        '{"post_id":1,"topic_id":2,"post_number":1}]}';
      const bridge: FakeBridge = new FakeBridge(okResponse(payload));
      const service: UserProfileService = new UserProfileService(bridge);

      const result: NetworkResult<SolvedPostPage> = await service.getSolvedPosts('kevin', 0);

      expect(bridge.requestedPath).assertEqual('/solution/by_user.json?username=kevin&offset=0&limit=20');
      expect(result.success).assertTrue();
      expect(result.data?.items.length).assertEqual(1);
      expect(result.data?.items[0].topicTitle).assertEqual('codex 里serena 配置问题求助');
      expect(result.data?.items[0].topicId).assertEqual(1058508);
      expect(result.data?.items[0].postNumber).assertEqual(5);
      expect(result.data?.items[0].categoryId).assertEqual(4);
      // 单页未满 limit → 没有下一页。
      expect(result.data?.hasMore).assertFalse();
      // excerpt 的 <a> 标签被剥离,只留可读文本。
      expect(result.data?.items[0].excerpt.includes('<a href')).assertFalse();
      expect(result.data?.items[0].excerpt.includes('Codex CLI')).assertTrue();
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
