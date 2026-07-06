import { User } from '../../models/User';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';

const CURRENT_SESSION_PATH: string = '/session/current.json';

interface DiscourseCurrentSessionResponse {
  current_user?: DiscourseCurrentUser | null;
}

interface DiscourseCurrentUser {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string;
  unread_notifications?: number;
  unread_high_priority_notifications?: number;
}

export class AuthService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  async getCurrentUser(): Promise<NetworkResult<User | undefined>> {
    const response: NetworkResult<string> = await this.bridge.getJson(CURRENT_SESSION_PATH);
    if (!response.success) {
      return this.forwardFailure(response);
    }

    if (response.data === undefined) {
      return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 当前会话响应为空。');
    }

    try {
      const payload: DiscourseCurrentSessionResponse = JSON.parse(response.data) as DiscourseCurrentSessionResponse;
      const sourceUser: DiscourseCurrentUser | null | undefined = payload.current_user;
      if (sourceUser === undefined || sourceUser === null) {
        return {
          success: true,
          statusCode: response.statusCode,
          challengeState: response.challengeState,
          data: undefined
        };
      }

      if (typeof sourceUser.id !== 'number' || typeof sourceUser.username !== 'string') {
        return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 当前用户响应字段无效。');
      }

      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: {
          id: sourceUser.id,
          username: sourceUser.username,
          displayName: sourceUser.name,
          avatarTemplate: sourceUser.avatar_template,
          animatedAvatar: sourceUser.animated_avatar ? sourceUser.animated_avatar : undefined,
          unreadNotifications: typeof sourceUser.unread_notifications === 'number' ? sourceUser.unread_notifications : 0,
          unreadHighPriorityNotifications: typeof sourceUser.unread_high_priority_notifications === 'number' ? sourceUser.unread_high_priority_notifications : 0
        }
      };
    } catch (error) {
      return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 当前会话响应不是有效 JSON。');
    }
  }

  private forwardFailure(response: NetworkResult<string>): NetworkResult<User | undefined> {
    return {
      success: false,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      error: response.error
    };
  }

  private unexpectedResponse(statusCode: number, challengeState: ChallengeState, message: string): NetworkResult<User | undefined> {
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
