import {
  SolvedPostItem,
  SolvedPostPage,
  UserActivityItem,
  UserActivityPage,
  UserBadgeGroup,
  UserBadgeItem,
  UserInteraction,
  UserProfileDetail,
  UserSummary,
  UserSummaryStats,
  UserTopReply,
  UserTopTopic
} from '../../models/UserProfile';
import { User } from '../../models/User';
import { HtmlText } from '../content/HtmlText';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { forwardFailure, unexpectedResponse } from '../network/NetworkResults';

// 个人中心「最近活动」默认取前几条(发布话题 + 回复)。
const RECENT_ACTIVITY_LIMIT: number = 3;
// user_actions 服务端每页固定条数(用于判断是否还有下一页)。
const ACTIVITY_PAGE_SIZE: number = 30;
// 徽章横滑条最多取的枚数,其余靠「全部」入口。
const TOP_BADGE_LIMIT: number = 8;
// /solution/by_user.json 每页条数(该接口自带 limit 参数,由我们指定)。
const SOLVED_PAGE_SIZE: number = 20;
// summary 的热门话题/热门回复各取几条(其余靠「全部」入口)。
const SUMMARY_LIST_LIMIT: number = 6;
// 互动圈每行几个头像。
const INTERACTION_LIMIT: number = 5;

interface DiscourseUserResponse {
  user?: DiscourseUserDetail;
}

interface DiscourseUserDetail {
  id?: number;
  username?: string;
  name?: string;
  title?: string | null;
  trust_level?: number;
  created_at?: string;
  last_posted_at?: string | null;
  badge_count?: number;
  profile_view_count?: number;
  // 他人主页身份区自己渲染头像,不像「我的」页有现成的 accountUser 可用。
  avatar_template?: string;
  animated_avatar?: string | null;
  flair_url?: string | null;
  flair_bg_color?: string | null;
  flair_color?: string | null;
  flair_name?: string | null;
  // bio_cooked 是 HTML,身份区只要两行摘要,取纯文本的 bio_excerpt。
  bio_excerpt?: string | null;
  // discourse-follow 插件字段(实测 /u/kevin.json 全部返回)。
  can_follow?: boolean;
  is_followed?: boolean;
  total_followers?: number;
  total_following?: number;
  // discourse-category-experts:当前登录者已认可 TA 的记录,元素形如 {category_id,...}。
  // 字段存在(哪怕空数组)即插件启用。
  category_expert_endorsements?: DiscourseEndorsementRecord[];
  // 用户状态(user_status.emoji),昵称后展示的状态表情短名。
  status?: DiscourseUserStatus;
}

interface DiscourseUserStatus {
  emoji?: string;
}

interface DiscourseEndorsementRecord {
  category_id?: number;
}

interface DiscourseSummaryResponse {
  user_summary?: DiscourseUserSummary;
  badges?: DiscourseBadge[];
  // 顶层 topics 是「所有被引用话题」的字典:既含热门话题,也含热门回复/热门链接所在的话题。
  // 哪些是热门话题由 user_summary.topic_ids 指定;热门回复的标题也要拿 topic_id 来这里关联
  // (replies 自身只有 topic_id,不带标题)。
  topics?: DiscourseSummaryTopic[];
}

interface DiscourseUserSummary {
  days_visited?: number;
  time_read?: number;
  likes_given?: number;
  likes_received?: number;
  topic_count?: number;
  post_count?: number;
  topics_entered?: number;
  solved_count?: number;
  badges?: DiscourseUserBadgeGrant[];
  // 以下字段此前全部被丢弃——官网「热门话题/热门回复/最多回复至/被谁赞得最多/赞最多」
  // 都在这一个响应里,他人主页的内容区与互动圈靠它们,不需要额外请求。
  // 注意:热门话题的正文不在这儿——topic_ids 只给 id,详情在顶层 topics 里。
  topic_ids?: number[];
  replies?: DiscourseSummaryReply[];
  most_replied_to_users?: DiscourseUserWithCount[];
  most_liked_users?: DiscourseUserWithCount[];
  most_liked_by_users?: DiscourseUserWithCount[];
}

// 顶层 topics 一条(TopicSerializer 精简)。
interface DiscourseSummaryTopic {
  id?: number;
  title?: string;
  slug?: string;
  like_count?: number;
  created_at?: string;
  category_id?: number;
}

// user_summary.replies 一条:他获赞最多的回复,指向具体楼层。
// 实测只有这四个字段——没有标题/分类,要靠 topic_id 去顶层 topics 关联。
interface DiscourseSummaryReply {
  topic_id?: number;
  post_number?: number;
  like_count?: number;
  created_at?: string;
}

// most_*_users 一条:BasicUser + count。实测不返回 animated_avatar(互动圈头像用静态图),
// 仍保留声明:站点若哪天补上,映射自动生效。
interface DiscourseUserWithCount {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string | null;
  count?: number;
  flair_url?: string | null;
  flair_bg_color?: string | null;
  flair_color?: string | null;
  flair_name?: string | null;
}

interface DiscourseBadge {
  id?: number;
  name?: string;
  badge_type_id?: number;
  icon?: string | null;
  image_url?: string | null;
  description?: string | null;
}

// /user-badges/{username}.json?grouped=true 响应:徽章定义 + 等级类型 + 本用户授予记录。
interface DiscourseUserBadgesResponse {
  badges?: DiscourseBadge[];
  badge_types?: DiscourseBadgeType[];
  user_badges?: DiscourseUserBadgeRecord[];
}

interface DiscourseBadgeType {
  id?: number;
  name?: string;
}

// grouped=true 时每枚徽章一条,count 为累计获得次数。
interface DiscourseUserBadgeRecord {
  id?: number;
  badge_id?: number;
  granted_at?: string;
  count?: number;
}

// user_summary.badges:本用户的徽章授予记录,badge_id 对应顶层 badges 定义。
interface DiscourseUserBadgeGrant {
  badge_id?: number;
  count?: number;
}

interface DiscourseUserActionsResponse {
  user_actions?: DiscourseUserAction[];
}

interface DiscourseUserAction {
  action_type?: number;
  created_at?: string;
  topic_id?: number;
  post_number?: number;
  title?: string;
  excerpt?: string;
  category_id?: number;
  // 该动作对应楼层的作者。acting_* 是动作发起人,自己的活动流里二者同一人,取前者即可。
  user_id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
}

// /solution/by_user.json?username=&offset=&limit= 响应(discourse-solved 插件)。
// 与 user_actions 无关:它是独立端点、独立结构,自带 offset/limit 分页。
interface DiscourseSolvedResponse {
  user_solved_posts?: DiscourseSolvedPost[];
}

interface DiscourseSolvedPost {
  post_id?: number;
  topic_id?: number;
  post_number?: number;
  topic_title?: string;
  slug?: string;
  // 他那条被采纳答案的正文摘要;实测带 HTML(<a> 等),需转纯文本。
  excerpt?: string;
  category_id?: number;
  created_at?: string;
}

// 个人中心数据服务:资料 /u/{username}.json、摘要 /u/{username}/summary.json、
// 最近活动 /user_actions.json?filter=4,5(4=发布话题 5=回复)。均为 Discourse 标准接口。
// 另有 /solution/by_user.json(discourse-solved 插件),他人主页的「解决方案」入口用。
export class UserProfileService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  async getProfileDetail(username: string): Promise<NetworkResult<UserProfileDetail>> {
    const response: NetworkResult<string> = await this.bridge.getJson(`/u/${encodeURIComponent(username)}.json`);
    if (!response.success) {
      return this.forwardFailure<UserProfileDetail>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<UserProfileDetail>(response.statusCode, response.challengeState, 'Linux.do 用户资料响应为空。');
    }

    try {
      const payload: DiscourseUserResponse = JSON.parse(response.data) as DiscourseUserResponse;
      const sourceUser: DiscourseUserDetail | undefined = payload.user;
      if (!sourceUser || typeof sourceUser.id !== 'number' || typeof sourceUser.username !== 'string') {
        return this.unexpectedResponse<UserProfileDetail>(response.statusCode, response.challengeState, 'Linux.do 用户资料响应字段无效。');
      }

      const detail: UserProfileDetail = {
        id: sourceUser.id,
        username: sourceUser.username
      };
      if (sourceUser.name && sourceUser.name.length > 0) {
        detail.displayName = sourceUser.name;
      }
      if (sourceUser.title && sourceUser.title.length > 0) {
        detail.title = sourceUser.title;
      }
      if (typeof sourceUser.trust_level === 'number') {
        detail.trustLevel = sourceUser.trust_level;
      }
      if (sourceUser.created_at && sourceUser.created_at.length > 0) {
        detail.createdAt = sourceUser.created_at;
      }
      if (sourceUser.last_posted_at && sourceUser.last_posted_at.length > 0) {
        detail.lastPostedAt = sourceUser.last_posted_at;
      }
      if (typeof sourceUser.badge_count === 'number') {
        detail.badgeCount = sourceUser.badge_count;
      }
      if (typeof sourceUser.profile_view_count === 'number') {
        detail.profileViewCount = sourceUser.profile_view_count;
      }
      if (sourceUser.avatar_template && sourceUser.avatar_template.length > 0) {
        detail.avatarTemplate = sourceUser.avatar_template;
      }
      if (sourceUser.animated_avatar && sourceUser.animated_avatar.length > 0) {
        detail.animatedAvatar = sourceUser.animated_avatar;
      }
      if (sourceUser.flair_url && sourceUser.flair_url.length > 0) {
        detail.flairUrl = sourceUser.flair_url;
      }
      if (sourceUser.flair_bg_color && sourceUser.flair_bg_color.length > 0) {
        detail.flairBgColor = sourceUser.flair_bg_color;
      }
      if (sourceUser.flair_color && sourceUser.flair_color.length > 0) {
        detail.flairColor = sourceUser.flair_color;
      }
      if (sourceUser.flair_name && sourceUser.flair_name.length > 0) {
        detail.flairName = sourceUser.flair_name;
      }
      // 布尔字段用 typeof 判断:false 是有效值(「不可关注」「未关注」),不能被 && 短路吃掉。
      if (typeof sourceUser.can_follow === 'boolean') {
        detail.canFollow = sourceUser.can_follow;
      }
      if (typeof sourceUser.is_followed === 'boolean') {
        detail.isFollowed = sourceUser.is_followed;
      }
      if (typeof sourceUser.total_followers === 'number') {
        detail.totalFollowers = sourceUser.total_followers;
      }
      if (typeof sourceUser.total_following === 'number') {
        detail.totalFollowing = sourceUser.total_following;
      }
      // 字段是数组即插件启用,据此显示「认可」按钮;元素的 category_id 是已认可的分类。
      if (Array.isArray(sourceUser.category_expert_endorsements)) {
        detail.endorsementAvailable = true;
        const ids: number[] = [];
        for (let index: number = 0; index < sourceUser.category_expert_endorsements.length; index++) {
          const record: DiscourseEndorsementRecord = sourceUser.category_expert_endorsements[index];
          if (typeof record.category_id === 'number') {
            ids.push(record.category_id);
          }
        }
        detail.endorsedCategoryIds = ids;
      }
      if (sourceUser.status && sourceUser.status.emoji && sourceUser.status.emoji.length > 0) {
        detail.statusEmoji = sourceUser.status.emoji;
      }
      if (sourceUser.bio_excerpt && sourceUser.bio_excerpt.length > 0) {
        // bio_excerpt 实测带 HTML 实体与 <a> 标签,身份区是纯 Text,统一转纯文本。
        const bio: string = HtmlText.toPlainText(sourceUser.bio_excerpt);
        if (bio.length > 0) {
          detail.bioExcerpt = bio;
        }
      }
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: detail
      };
    } catch (error) {
      return this.unexpectedResponse<UserProfileDetail>(response.statusCode, response.challengeState, 'Linux.do 用户资料响应不是有效 JSON。');
    }
  }

  async getSummary(username: string): Promise<NetworkResult<UserSummary>> {
    const response: NetworkResult<string> = await this.bridge.getJson(`/u/${encodeURIComponent(username)}/summary.json`);
    if (!response.success) {
      return this.forwardFailure<UserSummary>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<UserSummary>(response.statusCode, response.challengeState, 'Linux.do 用户摘要响应为空。');
    }

    try {
      const payload: DiscourseSummaryResponse = JSON.parse(response.data) as DiscourseSummaryResponse;
      const sourceSummary: DiscourseUserSummary | undefined = payload.user_summary;
      if (!sourceSummary) {
        return this.unexpectedResponse<UserSummary>(response.statusCode, response.challengeState, 'Linux.do 用户摘要响应缺少 user_summary。');
      }

      const stats: UserSummaryStats = {
        daysVisited: this.asCount(sourceSummary.days_visited),
        timeReadSeconds: this.asCount(sourceSummary.time_read),
        likesGiven: this.asCount(sourceSummary.likes_given),
        likesReceived: this.asCount(sourceSummary.likes_received),
        topicCount: this.asCount(sourceSummary.topic_count),
        postCount: this.asCount(sourceSummary.post_count),
        topicsEntered: this.asCount(sourceSummary.topics_entered)
      };
      if (typeof sourceSummary.solved_count === 'number') {
        stats.solvedCount = sourceSummary.solved_count;
      }

      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: {
          stats: stats,
          topBadges: this.mapBadges(payload.badges, sourceSummary.badges),
          topTopics: this.mapTopTopics(payload.topics, sourceSummary.topic_ids),
          topReplies: this.mapTopReplies(sourceSummary.replies, payload.topics),
          mostRepliedToUsers: this.mapInteractions(sourceSummary.most_replied_to_users),
          mostLikedUsers: this.mapInteractions(sourceSummary.most_liked_users),
          mostLikedByUsers: this.mapInteractions(sourceSummary.most_liked_by_users)
        }
      };
    } catch (error) {
      return this.unexpectedResponse<UserSummary>(response.statusCode, response.challengeState, 'Linux.do 用户摘要响应不是有效 JSON。');
    }
  }

  // 顶层 topics 建 id 索引:热门话题与热门回复都要靠它查详情。
  private buildTopicIndex(sourceTopics?: DiscourseSummaryTopic[]): Map<number, DiscourseSummaryTopic> {
    const byId: Map<number, DiscourseSummaryTopic> = new Map();
    if (!sourceTopics) {
      return byId;
    }
    for (let index: number = 0; index < sourceTopics.length; index++) {
      const source: DiscourseSummaryTopic = sourceTopics[index];
      if (typeof source.id === 'number') {
        byId.set(source.id, source);
      }
    }
    return byId;
  }

  // 热门话题:顶层 topics 是「所有被引用话题」的字典(还含热门回复/热门链接所在的话题),
  // 只有 user_summary.topic_ids 里的才是热门话题——顺序也以 topic_ids 为准。
  private mapTopTopics(sourceTopics?: DiscourseSummaryTopic[], topicIds?: number[]): UserTopTopic[] {
    const topics: UserTopTopic[] = [];
    if (!sourceTopics || !topicIds) {
      return topics;
    }
    const byId: Map<number, DiscourseSummaryTopic> = this.buildTopicIndex(sourceTopics);
    for (let index: number = 0; index < topicIds.length && topics.length < SUMMARY_LIST_LIMIT; index++) {
      const source: DiscourseSummaryTopic | undefined = byId.get(topicIds[index]);
      if (!source || typeof source.id !== 'number' ||
        typeof source.title !== 'string' || source.title.length === 0) {
        continue;
      }
      const topic: UserTopTopic = {
        topicId: source.id,
        title: source.title,
        likeCount: this.asCount(source.like_count)
      };
      if (source.slug && source.slug.length > 0) {
        topic.slug = source.slug;
      }
      if (source.created_at && source.created_at.length > 0) {
        topic.createdAt = source.created_at;
      }
      if (typeof source.category_id === 'number') {
        topic.categoryId = source.category_id;
      }
      topics.push(topic);
    }
    return topics;
  }

  // 热门回复:replies 自身只有 {topic_id, post_number, like_count, created_at},
  // 标题/分类/slug 全靠 topic_id 去顶层 topics 关联;关联不到就丢弃(没标题的行没法看)。
  private mapTopReplies(sourceReplies?: DiscourseSummaryReply[], sourceTopics?: DiscourseSummaryTopic[]): UserTopReply[] {
    const replies: UserTopReply[] = [];
    if (!sourceReplies) {
      return replies;
    }
    const byId: Map<number, DiscourseSummaryTopic> = this.buildTopicIndex(sourceTopics);
    for (let index: number = 0; index < sourceReplies.length && replies.length < SUMMARY_LIST_LIMIT; index++) {
      const source: DiscourseSummaryReply = sourceReplies[index];
      if (typeof source.topic_id !== 'number') {
        continue;
      }
      const topic: DiscourseSummaryTopic | undefined = byId.get(source.topic_id);
      if (!topic || typeof topic.title !== 'string' || topic.title.length === 0) {
        continue;
      }
      const reply: UserTopReply = {
        topicId: source.topic_id,
        postNumber: typeof source.post_number === 'number' ? source.post_number : 1,
        topicTitle: topic.title,
        likeCount: this.asCount(source.like_count)
      };
      if (topic.slug && topic.slug.length > 0) {
        reply.slug = topic.slug;
      }
      // 时间取回复自身的,不是话题的。
      if (source.created_at && source.created_at.length > 0) {
        reply.createdAt = source.created_at;
      }
      if (typeof topic.category_id === 'number') {
        reply.categoryId = topic.category_id;
      }
      replies.push(reply);
    }
    return replies;
  }

  // 互动圈一行:取前 INTERACTION_LIMIT 个头像。服务端已按次数降序,顺序即强弱,不再排序。
  private mapInteractions(sourceUsers?: DiscourseUserWithCount[]): UserInteraction[] {
    const interactions: UserInteraction[] = [];
    if (!sourceUsers) {
      return interactions;
    }
    for (let index: number = 0; index < sourceUsers.length && interactions.length < INTERACTION_LIMIT; index++) {
      const source: DiscourseUserWithCount = sourceUsers[index];
      if (typeof source.username !== 'string' || source.username.length === 0) {
        continue;
      }
      const user: User = {
        id: typeof source.id === 'number' ? source.id : 0,
        username: source.username
      };
      if (source.name && source.name.length > 0) {
        user.displayName = source.name;
      }
      if (source.avatar_template && source.avatar_template.length > 0) {
        user.avatarTemplate = source.avatar_template;
      }
      if (source.animated_avatar && source.animated_avatar.length > 0) {
        user.animatedAvatar = source.animated_avatar;
      }
      if (source.flair_url && source.flair_url.length > 0) {
        user.flairUrl = source.flair_url;
      }
      if (source.flair_bg_color && source.flair_bg_color.length > 0) {
        user.flairBgColor = source.flair_bg_color;
      }
      if (source.flair_color && source.flair_color.length > 0) {
        user.flairColor = source.flair_color;
      }
      if (source.flair_name && source.flair_name.length > 0) {
        user.flairName = source.flair_name;
      }
      interactions.push({
        user: user,
        count: this.asCount(source.count)
      });
    }
    return interactions;
  }

  // 个人中心「最近活动」预览:取发布话题+回复(filter=4,5)的前 limit 条。
  async getRecentActivity(username: string, limit: number = RECENT_ACTIVITY_LIMIT): Promise<NetworkResult<UserActivityItem[]>> {
    const result: NetworkResult<UserActivityPage> = await this.getActivity(username, '4,5', 0);
    if (!result.success || result.data === undefined) {
      return {
        success: false,
        statusCode: result.statusCode,
        challengeState: result.challengeState,
        error: result.error
      };
    }
    const items: UserActivityItem[] = result.data.items.length > limit
      ? result.data.items.slice(0, limit)
      : result.data.items;
    return {
      success: true,
      statusCode: result.statusCode,
      challengeState: result.challengeState,
      data: items
    };
  }

  // 通用用户动态分页:filter 见 UserActionType(4=话题 5=回复 1=点赞,可用逗号组合),
  // offset 为已加载条数;hasMore 依据本页返回是否满一页判断。
  async getActivity(username: string, filter: string, offset: number): Promise<NetworkResult<UserActivityPage>> {
    const path: string =
      `/user_actions.json?offset=${offset}&username=${encodeURIComponent(username)}&filter=${filter}`;
    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure<UserActivityPage>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<UserActivityPage>(response.statusCode, response.challengeState, 'Linux.do 用户活动响应为空。');
    }

    try {
      const payload: DiscourseUserActionsResponse = JSON.parse(response.data) as DiscourseUserActionsResponse;
      const sourceActions: DiscourseUserAction[] = payload.user_actions ? payload.user_actions : [];
      const items: UserActivityItem[] = [];
      for (let index: number = 0; index < sourceActions.length; index++) {
        const item: UserActivityItem | undefined = this.mapAction(sourceActions[index]);
        if (item) {
          items.push(item);
        }
      }
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: {
          items: items,
          hasMore: sourceActions.length >= ACTIVITY_PAGE_SIZE
        }
      };
    } catch (error) {
      return this.unexpectedResponse<UserActivityPage>(response.statusCode, response.challengeState, 'Linux.do 用户活动响应不是有效 JSON。');
    }
  }

  // 「全部徽章」页:/user-badges/{username}.json?grouped=true。与摘要接口同源,复用同一 bridge 过盾。
  // 返回按等级(金/银/铜)分组、组内保持服务端顺序的徽章列表。
  async getUserBadges(username: string): Promise<NetworkResult<UserBadgeGroup[]>> {
    const path: string = `/user-badges/${encodeURIComponent(username)}.json?grouped=true`;
    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure<UserBadgeGroup[]>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<UserBadgeGroup[]>(response.statusCode, response.challengeState, 'Linux.do 徽章响应为空。');
    }

    try {
      const payload: DiscourseUserBadgesResponse = JSON.parse(response.data) as DiscourseUserBadgesResponse;
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: this.mapUserBadges(payload.badges, payload.badge_types, payload.user_badges)
      };
    } catch (error) {
      return this.unexpectedResponse<UserBadgeGroup[]>(response.statusCode, response.challengeState, 'Linux.do 徽章响应不是有效 JSON。');
    }
  }

  // 他被采纳为解决方案的回复:/solution/by_user.json,自带 offset/limit 分页。
  // 入口是他人主页统计格里的「解决方案」数字(summary 的 solved_count)。
  async getSolvedPosts(username: string, offset: number): Promise<NetworkResult<SolvedPostPage>> {
    const path: string =
      `/solution/by_user.json?username=${encodeURIComponent(username)}&offset=${offset}&limit=${SOLVED_PAGE_SIZE}`;
    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure<SolvedPostPage>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<SolvedPostPage>(response.statusCode, response.challengeState, 'Linux.do 解决方案响应为空。');
    }

    try {
      const payload: DiscourseSolvedResponse = JSON.parse(response.data) as DiscourseSolvedResponse;
      const sourcePosts: DiscourseSolvedPost[] = payload.user_solved_posts ? payload.user_solved_posts : [];
      const items: SolvedPostItem[] = [];
      for (let index: number = 0; index < sourcePosts.length; index++) {
        const item: SolvedPostItem | undefined = this.mapSolvedPost(sourcePosts[index]);
        if (item) {
          items.push(item);
        }
      }
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: {
          items: items,
          hasMore: sourcePosts.length >= SOLVED_PAGE_SIZE
        }
      };
    } catch (error) {
      return this.unexpectedResponse<SolvedPostPage>(response.statusCode, response.challengeState, 'Linux.do 解决方案响应不是有效 JSON。');
    }
  }

  private mapSolvedPost(sourcePost: DiscourseSolvedPost): SolvedPostItem | undefined {
    if (typeof sourcePost.topic_id !== 'number' ||
      typeof sourcePost.topic_title !== 'string' || sourcePost.topic_title.length === 0) {
      return undefined;
    }

    const item: SolvedPostItem = {
      postId: typeof sourcePost.post_id === 'number' ? sourcePost.post_id : 0,
      topicId: sourcePost.topic_id,
      postNumber: typeof sourcePost.post_number === 'number' ? sourcePost.post_number : 1,
      topicTitle: sourcePost.topic_title,
      excerpt: HtmlText.toPlainText(sourcePost.excerpt)
    };
    if (sourcePost.slug && sourcePost.slug.length > 0) {
      item.slug = sourcePost.slug;
    }
    if (typeof sourcePost.category_id === 'number') {
      item.categoryId = sourcePost.category_id;
    }
    if (sourcePost.created_at && sourcePost.created_at.length > 0) {
      item.createdAt = sourcePost.created_at;
    }
    return item;
  }

  private mapUserBadges(
    sourceBadges?: DiscourseBadge[],
    badgeTypes?: DiscourseBadgeType[],
    userBadges?: DiscourseUserBadgeRecord[]): UserBadgeGroup[] {
    const groups: UserBadgeGroup[] = [];
    if (!userBadges || userBadges.length === 0) {
      return groups;
    }

    // badge_id -> 定义。
    const defById: Map<number, DiscourseBadge> = new Map();
    if (sourceBadges) {
      for (let index: number = 0; index < sourceBadges.length; index++) {
        const badge: DiscourseBadge = sourceBadges[index];
        if (typeof badge.id === 'number') {
          defById.set(badge.id, badge);
        }
      }
    }
    // badge_type_id -> 服务端名称。
    const typeNames: Map<number, string> = new Map();
    if (badgeTypes) {
      for (let index: number = 0; index < badgeTypes.length; index++) {
        const type: DiscourseBadgeType = badgeTypes[index];
        if (typeof type.id === 'number' && typeof type.name === 'string' && type.name.length > 0) {
          typeNames.set(type.id, type.name);
        }
      }
    }

    // 按 user_badges 顺序遍历,按等级归桶;同一徽章去重(防未分组时重复)。
    const bucketByType: Map<number, UserBadgeItem[]> = new Map();
    const seenBadgeIds: Set<number> = new Set();
    const typeOrder: number[] = [];

    for (let index: number = 0; index < userBadges.length; index++) {
      const record: DiscourseUserBadgeRecord = userBadges[index];
      if (typeof record.badge_id !== 'number' || seenBadgeIds.has(record.badge_id)) {
        continue;
      }
      const def: DiscourseBadge | undefined = defById.get(record.badge_id);
      if (!def || typeof def.id !== 'number' || typeof def.name !== 'string' || def.name.length === 0) {
        continue;
      }
      seenBadgeIds.add(record.badge_id);

      const typeId: number = typeof def.badge_type_id === 'number' ? def.badge_type_id : 3;
      const item: UserBadgeItem = {
        id: def.id,
        name: def.name,
        badgeTypeId: typeId
      };
      if (def.image_url && def.image_url.length > 0) {
        item.imageUrl = def.image_url;
      } else if (def.icon && def.icon.length > 0) {
        item.icon = def.icon;
      }
      if (def.description && def.description.length > 0) {
        item.description = def.description;
      }
      if (typeof record.count === 'number' && record.count > 1) {
        item.grantCount = record.count;
      }
      if (record.granted_at && record.granted_at.length > 0) {
        item.grantedAt = record.granted_at;
      }

      let bucket: UserBadgeItem[] | undefined = bucketByType.get(typeId);
      if (!bucket) {
        bucket = [];
        bucketByType.set(typeId, bucket);
        typeOrder.push(typeId);
      }
      bucket.push(item);
    }

    // 组顺序:金(1)→银(2)→铜(3)。
    typeOrder.sort((a: number, b: number) => a - b);
    for (let index: number = 0; index < typeOrder.length; index++) {
      const typeId: number = typeOrder[index];
      const bucket: UserBadgeItem[] | undefined = bucketByType.get(typeId);
      if (bucket && bucket.length > 0) {
        groups.push({
          typeId: typeId,
          typeName: this.badgeTypeName(typeId, typeNames),
          badges: bucket
        });
      }
    }
    return groups;
  }

  private badgeTypeName(typeId: number, typeNames: Map<number, string>): string {
    const name: string | undefined = typeNames.get(typeId);
    if (name && name.length > 0) {
      return name;
    }
    if (typeId === 1) {
      return '金牌';
    }
    if (typeId === 2) {
      return '银牌';
    }
    return '铜牌';
  }

  private mapBadges(sourceBadges?: DiscourseBadge[], grants?: DiscourseUserBadgeGrant[]): UserBadgeItem[] {
    const badges: UserBadgeItem[] = [];
    if (!sourceBadges) {
      return badges;
    }

    // badge_id -> 本用户获得次数(user_summary.badges)。
    const grantCounts: Map<number, number> = new Map();
    if (grants) {
      for (let index: number = 0; index < grants.length; index++) {
        const grant: DiscourseUserBadgeGrant = grants[index];
        if (typeof grant.badge_id === 'number' && typeof grant.count === 'number') {
          grantCounts.set(grant.badge_id, grant.count);
        }
      }
    }

    for (let index: number = 0; index < sourceBadges.length && badges.length < TOP_BADGE_LIMIT; index++) {
      const sourceBadge: DiscourseBadge = sourceBadges[index];
      if (typeof sourceBadge.id !== 'number' || typeof sourceBadge.name !== 'string' || sourceBadge.name.length === 0) {
        continue;
      }
      const badge: UserBadgeItem = {
        id: sourceBadge.id,
        name: sourceBadge.name,
        badgeTypeId: typeof sourceBadge.badge_type_id === 'number' ? sourceBadge.badge_type_id : 3
      };
      if (sourceBadge.image_url && sourceBadge.image_url.length > 0) {
        badge.imageUrl = sourceBadge.image_url;
      } else if (sourceBadge.icon && sourceBadge.icon.length > 0) {
        badge.icon = sourceBadge.icon;
      }
      const grantCount: number | undefined = grantCounts.get(sourceBadge.id);
      if (grantCount !== undefined && grantCount > 0) {
        badge.grantCount = grantCount;
      }
      badges.push(badge);
    }
    return badges;
  }

  private mapAction(sourceAction: DiscourseUserAction): UserActivityItem | undefined {
    if (typeof sourceAction.topic_id !== 'number' ||
      typeof sourceAction.title !== 'string' || sourceAction.title.length === 0 ||
      typeof sourceAction.action_type !== 'number') {
      return undefined;
    }

    const item: UserActivityItem = {
      actionType: sourceAction.action_type,
      topicId: sourceAction.topic_id,
      title: sourceAction.title,
      excerpt: HtmlText.toPlainText(sourceAction.excerpt),
      // /user_actions.json 只返回 category_id,不含 tags 字段(实测),故活动列表仅显示分类,无标签。
      tags: []
    };
    if (typeof sourceAction.post_number === 'number' && sourceAction.post_number > 1) {
      item.postNumber = sourceAction.post_number;
    }
    if (typeof sourceAction.category_id === 'number') {
      item.categoryId = sourceAction.category_id;
    }
    if (sourceAction.created_at && sourceAction.created_at.length > 0) {
      item.createdAt = sourceAction.created_at;
    }
    if (typeof sourceAction.username === 'string' && sourceAction.username.length > 0) {
      item.author = {
        id: typeof sourceAction.user_id === 'number' ? sourceAction.user_id : 0,
        username: sourceAction.username,
        displayName: sourceAction.name,
        avatarTemplate: sourceAction.avatar_template
      };
    }
    return item;
  }

  private asCount(value?: number): number {
    return typeof value === 'number' && value >= 0 ? value : 0;
  }

  private forwardFailure<T>(response: NetworkResult<string>): NetworkResult<T> {
    return forwardFailure<T>(response);
  }

  private unexpectedResponse<T>(statusCode: number, challengeState: ChallengeState, message: string): NetworkResult<T> {
    return unexpectedResponse<T>(statusCode, challengeState, message);
  }
}
