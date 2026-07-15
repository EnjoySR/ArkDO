import {
  UserActivityItem,
  UserActivityPage,
  UserBadgeGroup,
  UserBadgeItem,
  UserProfileDetail,
  UserSummary,
  UserSummaryStats
} from '../../models/UserProfile';
import { HtmlText } from '../content/HtmlText';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';

// 个人中心「最近活动」默认取前几条(发布话题 + 回复)。
const RECENT_ACTIVITY_LIMIT: number = 3;
// user_actions 服务端每页固定条数(用于判断是否还有下一页)。
const ACTIVITY_PAGE_SIZE: number = 30;
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
