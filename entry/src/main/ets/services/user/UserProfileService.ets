import {
  UserActivityItem,
  UserBadgeItem,
  UserProfileDetail,
  UserSummary,
  UserSummaryStats
} from '../../models/UserProfile';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';

// 个人中心「最近活动」默认取前几条(发布话题 + 回复)。
const RECENT_ACTIVITY_LIMIT: number = 3;
// 徽章横滑条最多取的枚数,其余靠「全部」入口。
const TOP_BADGE_LIMIT: number = 8;

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
}

interface DiscourseSummaryResponse {
  user_summary?: DiscourseUserSummary;
  badges?: DiscourseBadge[];
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
}

interface DiscourseBadge {
  id?: number;
  name?: string;
  badge_type_id?: number;
  icon?: string | null;
  image_url?: string | null;
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
  category_id?: number;
}

// 个人中心数据服务:资料 /u/{username}.json、摘要 /u/{username}/summary.json、
// 最近活动 /user_actions.json?filter=4,5(4=发布话题 5=回复)。均为 Discourse 标准接口。
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
          topBadges: this.mapBadges(payload.badges, sourceSummary.badges)
        }
      };
    } catch (error) {
      return this.unexpectedResponse<UserSummary>(response.statusCode, response.challengeState, 'Linux.do 用户摘要响应不是有效 JSON。');
    }
  }

  async getRecentActivity(username: string, limit: number = RECENT_ACTIVITY_LIMIT): Promise<NetworkResult<UserActivityItem[]>> {
    const path: string = `/user_actions.json?offset=0&username=${encodeURIComponent(username)}&filter=4,5`;
    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure<UserActivityItem[]>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<UserActivityItem[]>(response.statusCode, response.challengeState, 'Linux.do 用户活动响应为空。');
    }

    try {
      const payload: DiscourseUserActionsResponse = JSON.parse(response.data) as DiscourseUserActionsResponse;
      const sourceActions: DiscourseUserAction[] = payload.user_actions ? payload.user_actions : [];
      const items: UserActivityItem[] = [];
      for (let index: number = 0; index < sourceActions.length && items.length < limit; index++) {
        const item: UserActivityItem | undefined = this.mapAction(sourceActions[index]);
        if (item) {
          items.push(item);
        }
      }
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: items
      };
    } catch (error) {
      return this.unexpectedResponse<UserActivityItem[]>(response.statusCode, response.challengeState, 'Linux.do 用户活动响应不是有效 JSON。');
    }
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
      title: sourceAction.title
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
    return item;
  }

  private asCount(value?: number): number {
    return typeof value === 'number' && value >= 0 ? value : 0;
  }

  private forwardFailure<T>(response: NetworkResult<string>): NetworkResult<T> {
    return {
      success: false,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      error: response.error
    };
  }

  private unexpectedResponse<T>(statusCode: number, challengeState: ChallengeState, message: string): NetworkResult<T> {
    return {
      success: false,
      statusCode: statusCode,
      challengeState: challengeState,
      error: {
        code: NetworkErrorCode.UNEXPECTED_RESPONSE,
        message: message,
        requiresChallenge: challengeState !== ChallengeState.NONE
      }
    };
  }
}
