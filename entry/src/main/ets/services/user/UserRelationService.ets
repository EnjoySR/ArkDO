import { EndorsableCategoriesResult, EndorsableCategory } from '../../models/UserProfile';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';

// 关注/认可等「对他人的写操作」。与只读的 UserProfileService 分开:
// 一个取数、一个改状态,混在一起职责不清。CSRF/cookie 由 bridge 同源自动处理。

interface DiscourseEndorsableCategory {
  id?: number;
  name?: string;
  color?: string;
}

interface DiscourseEndorsableResponse {
  categories?: DiscourseEndorsableCategory[];
  extras?: DiscourseEndorsableExtras;
}

interface DiscourseEndorsableExtras {
  remaining_endorsements?: number;
}

export class UserRelationService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  // 关注:PUT /follow/{username}.json,空 body(对齐官网 content-length:0)。响应 {"success":"OK"}。
  async followUser(username: string): Promise<NetworkResult<boolean>> {
    const response: NetworkResult<string> = await this.bridge.putJson(`/follow/${encodeURIComponent(username)}.json`);
    return this.asBoolResult(response);
  }

  // 取消关注:DELETE /follow/{username}.json,空 body。
  async unfollowUser(username: string): Promise<NetworkResult<boolean>> {
    const response: NetworkResult<string> = await this.bridge.deleteForm(`/follow/${encodeURIComponent(username)}.json`, '');
    return this.asBoolResult(response);
  }

  // 认可弹窗数据:GET /category-experts/endorsable-categories/{username}.json。
  // 返回可勾选的分类 + 今天还剩几次认可。
  async getEndorsableCategories(username: string): Promise<NetworkResult<EndorsableCategoriesResult>> {
    const path: string = `/category-experts/endorsable-categories/${encodeURIComponent(username)}.json`;
    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure<EndorsableCategoriesResult>(response);
    }
    if (response.data === undefined) {
      return this.unexpected<EndorsableCategoriesResult>(response, 'Linux.do 认可分类响应为空。');
    }
    try {
      const payload: DiscourseEndorsableResponse = JSON.parse(response.data) as DiscourseEndorsableResponse;
      const sourceCategories: DiscourseEndorsableCategory[] = payload.categories ? payload.categories : [];
      const categories: EndorsableCategory[] = [];
      for (let index: number = 0; index < sourceCategories.length; index++) {
        const source: DiscourseEndorsableCategory = sourceCategories[index];
        if (typeof source.id !== 'number' || typeof source.name !== 'string' || source.name.length === 0) {
          continue;
        }
        const category: EndorsableCategory = { id: source.id, name: source.name };
        if (source.color && source.color.length > 0) {
          category.color = source.color;
        }
        categories.push(category);
      }
      const remaining: number = payload.extras && typeof payload.extras.remaining_endorsements === 'number'
        ? payload.extras.remaining_endorsements
        : 0;
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: { categories: categories, remainingEndorsements: remaining }
      };
    } catch (error) {
      return this.unexpected<EndorsableCategoriesResult>(response, 'Linux.do 认可分类响应不是有效 JSON。');
    }
  }

  // 提交认可:PUT /category-experts/endorse/{username}.json,form body categoryIds[]=4(可多选)。
  // 成功返回 {category_expert_endorsements:[...]},这里只需知道成功与否。
  async endorseCategories(username: string, categoryIds: number[]): Promise<NetworkResult<boolean>> {
    if (categoryIds.length === 0) {
      return {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: { code: NetworkErrorCode.UNEXPECTED_RESPONSE, message: '请至少选择一个类别。', requiresChallenge: false }
      };
    }
    const parts: string[] = [];
    for (let index: number = 0; index < categoryIds.length; index++) {
      parts.push(`categoryIds[]=${categoryIds[index]}`);
    }
    const body: string = parts.join('&');
    const path: string = `/category-experts/endorse/${encodeURIComponent(username)}.json`;
    const response: NetworkResult<string> = await this.bridge.putForm(path, body);
    if (!response.success) {
      return this.forwardFailure<boolean>(response);
    }
    return {
      success: true,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      data: true
    };
  }

  // follow/unfollow 只判成败,响应体 {"success":"OK"} 不细解析。
  private asBoolResult(response: NetworkResult<string>): NetworkResult<boolean> {
    if (!response.success) {
      return this.forwardFailure<boolean>(response);
    }
    return {
      success: true,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      data: true
    };
  }

  private forwardFailure<T>(response: NetworkResult<string>): NetworkResult<T> {
    return {
      success: false,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      error: response.error
    };
  }

  private unexpected<T>(response: NetworkResult<string>, message: string): NetworkResult<T> {
    return {
      success: false,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      error: {
        code: NetworkErrorCode.UNEXPECTED_RESPONSE,
        message: message,
        requiresChallenge: response.challengeState !== ChallengeState.NONE
      }
    };
  }
}
