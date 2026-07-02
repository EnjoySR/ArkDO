import { Topic } from '../../models/Topic';
import { User } from '../../models/User';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';

interface DiscourseLatestResponse {
  topic_list?: DiscourseTopicList;
  users?: DiscourseUser[];
}

interface DiscourseTopicList {
  topics?: DiscourseTopic[];
}

interface DiscourseTopic {
  id?: number;
  title?: string;
  slug?: string;
  posts_count?: number;
  reply_count?: number;
  like_count?: number;
  created_at?: string;
  last_posted_at?: string;
  posters?: DiscoursePoster[];
}

interface DiscoursePoster {
  user_id?: number;
  description?: string;
}

interface DiscourseUser {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
}

export class TopicService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  async getLatestTopics(): Promise<NetworkResult<Topic[]>> {
    const response: NetworkResult<string> = await this.bridge.getJson('/latest.json');
    if (!response.success) {
      return this.forwardFailure(response);
    }

    if (response.data === undefined) {
      return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 最新帖子响应为空。');
    }

    try {
      const payload: DiscourseLatestResponse = JSON.parse(response.data) as DiscourseLatestResponse;
      if (!payload.topic_list || !payload.topic_list.topics) {
        return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 最新帖子响应缺少 topic_list.topics。');
      }

      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: this.mapTopics(payload.topic_list.topics, payload.users)
      };
    } catch (error) {
      return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 最新帖子响应不是有效 JSON。');
    }
  }

  private mapTopics(sourceTopics: DiscourseTopic[], sourceUsers?: DiscourseUser[]): Topic[] {
    const topics: Topic[] = [];
    for (let index: number = 0; index < sourceTopics.length; index++) {
      const sourceTopic: DiscourseTopic = sourceTopics[index];
      if (typeof sourceTopic.id !== 'number' || typeof sourceTopic.title !== 'string') {
        continue;
      }

      topics.push({
        id: sourceTopic.id,
        title: sourceTopic.title,
        slug: sourceTopic.slug,
        postsCount: sourceTopic.posts_count,
        replyCount: sourceTopic.reply_count,
        likeCount: sourceTopic.like_count,
        createdAt: sourceTopic.created_at,
        lastPostedAt: sourceTopic.last_posted_at,
        author: this.findOriginalPoster(sourceTopic, sourceUsers)
      });
    }
    return topics;
  }

  private findOriginalPoster(topic: DiscourseTopic, users?: DiscourseUser[]): User | undefined {
    if (!topic.posters || !users) {
      return undefined;
    }

    let userId: number | undefined = undefined;
    for (let posterIndex: number = 0; posterIndex < topic.posters.length; posterIndex++) {
      const poster: DiscoursePoster = topic.posters[posterIndex];
      if (poster.description === 'Original Poster' && typeof poster.user_id === 'number') {
        userId = poster.user_id;
        break;
      }
    }

    if (userId === undefined) {
      return undefined;
    }

    for (let userIndex: number = 0; userIndex < users.length; userIndex++) {
      const sourceUser: DiscourseUser = users[userIndex];
      if (sourceUser.id === userId && sourceUser.username) {
        return {
          id: sourceUser.id,
          username: sourceUser.username,
          displayName: sourceUser.name,
          avatarTemplate: sourceUser.avatar_template
        };
      }
    }

    return undefined;
  }

  private forwardFailure(response: NetworkResult<string>): NetworkResult<Topic[]> {
    return {
      success: false,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      error: response.error
    };
  }

  private unexpectedResponse(statusCode: number, challengeState: ChallengeState, message: string): NetworkResult<Topic[]> {
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
