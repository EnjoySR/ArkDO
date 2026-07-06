import { Topic, TopicTag } from '../../models/Topic';
import { PostBoost, PostReaction, TopicDetail, TopicPost } from '../../models/TopicDetail';
import { User } from '../../models/User';
import { CookedHtmlParser } from '../content/CookedHtmlParser';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';
import { AppConstants } from '../../common/constants/AppConstants';

interface DiscourseLatestResponse {
  topic_list?: DiscourseTopicList;
  users?: DiscourseUser[];
}

interface DiscourseTopicList {
  topics?: DiscourseTopic[];
  more_topics_url?: string;
}

interface DiscourseTopic {
  id?: number;
  title?: string;
  slug?: string;
  category_id?: number;
  tags?: Object[];
  posts_count?: number;
  reply_count?: number;
  like_count?: number;
  created_at?: string;
  last_posted_at?: string;
  unseen?: boolean;
  unread_posts?: number;
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
  animated_avatar?: string;
}

interface DiscourseTopicDetail {
  id?: number;
  title?: string;
  slug?: string;
  category_id?: number;
  tags?: Object[];
  posts_count?: number;
  reply_count?: number;
  like_count?: number;
  views?: number;
  created_at?: string;
  post_stream?: DiscoursePostStream;
  last_read_post_number?: number;
  highest_post_number?: number;
  unread_posts?: number;
}

interface DiscoursePostStream {
  posts?: DiscoursePost[];
  stream?: number[];
}

interface DiscourseReaction {
  id?: string;
  type?: string;
  count?: number;
}

interface DiscourseCurrentReaction {
  id?: string;
  type?: string;
  can_undo?: boolean;
}

// discourse-boosts:发 boost 的用户。
interface DiscourseBoostUser {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string;
}

// discourse-boosts:一条 boost(id + cooked 短文本 + 用户)。
interface DiscourseBoost {
  id?: number;
  cooked?: string;
  user?: DiscourseBoostUser;
}

interface DiscoursePost {
  id?: number;
  topic_id?: number;
  post_number?: number;
  user_id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string;
  cooked?: string;
  created_at?: string;
  updated_at?: string;
  reply_count?: number;
  like_count?: number;
  read?: boolean;
  user_title?: string;
  reactions?: DiscourseReaction[];
  reaction_users_count?: number;
  current_user_reaction?: DiscourseCurrentReaction;
  boosts?: DiscourseBoost[];
  can_boost?: boolean;
}

// POST /posts 的响应外壳:真正的楼层在 post 字段里,不在顶层。
interface CreatePostResponse {
  action?: string;
  success?: boolean;
  post?: DiscoursePost;
  // 进入审核队列时返回 pending_post(而非 post),action 为 'enqueued'。
  pending_post?: DiscoursePost;
}

// 发表评论/回复的结果:要么直接发布得到新楼层 post,要么进了审核队列(pending)。
export interface CreateReplyOutcome {
  post?: TopicPost;
  pending: boolean;
}

// 发表评论/回复 POST /posts 的请求体(对齐官方 composer 提交字段)。
interface CreateReplyPayload {
  raw: string;
  unlist_topic: boolean;
  topic_id: number;
  category?: number;
  // 定向回复某楼时携带该楼号(对齐 Discourse composer);缺省=回复整个话题的顶层回复。
  reply_to_post_number?: number;
  is_warning: boolean;
  // 悄悄话(仅管理组可见)回复,普通回复为 false(对齐官方 composer)。
  whisper: boolean;
  archetype: string;
  typing_duration_msecs: number;
  composer_open_duration_msecs: number;
  composer_version: number;
  tags: string[];
  featured_link: string | null;
  shared_draft: boolean;
  draft_key: string;
  locale: string;
  // 图片尺寸表,无图时为空对象(对齐官方 composer)。
  image_sizes: Record<string, number>;
  nested_post: boolean;
}

export interface TopicPage {
  topics: Topic[];
  page: number;
  hasMore: boolean;
}

export class TopicService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  async getLatestTopics(): Promise<NetworkResult<Topic[]>> {
    const pageResult: NetworkResult<TopicPage> = await this.getLatestTopicsPage(0);
    if (!pageResult.success) {
      return {
        success: false,
        statusCode: pageResult.statusCode,
        challengeState: pageResult.challengeState,
        error: pageResult.error
      };
    }

    return {
      success: true,
      statusCode: pageResult.statusCode,
      challengeState: pageResult.challengeState,
      data: pageResult.data ? pageResult.data.topics : []
    };
  }

  async getLatestTopicsPage(page: number): Promise<NetworkResult<TopicPage>> {
    const response: NetworkResult<string> = await this.bridge.getJson(this.getLatestPath(page));
    if (!response.success) {
      return this.forwardFailure<TopicPage>(response);
    }

    if (response.data === undefined) {
      return this.unexpectedResponse<TopicPage>(response.statusCode, response.challengeState, 'Linux.do 最新帖子响应为空。');
    }

    try {
      const payload: DiscourseLatestResponse = JSON.parse(response.data) as DiscourseLatestResponse;
      if (!payload.topic_list || !payload.topic_list.topics) {
        return this.unexpectedResponse<TopicPage>(response.statusCode, response.challengeState, 'Linux.do 最新帖子响应缺少 topic_list.topics。');
      }

      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: {
          topics: this.mapTopics(payload.topic_list.topics, payload.users),
          page: page,
          hasMore: this.hasMoreTopics(payload.topic_list)
        }
      };
    } catch (error) {
      return this.unexpectedResponse<TopicPage>(response.statusCode, response.challengeState, 'Linux.do 最新帖子响应不是有效 JSON。');
    }
  }

  async getTopicDetail(topicId: number, slug?: string): Promise<NetworkResult<TopicDetail>> {
    const response: NetworkResult<string> = await this.bridge.getJson(this.getTopicDetailPath(topicId, slug));
    if (!response.success) {
      return this.forwardFailure<TopicDetail>(response);
    }

    if (response.data === undefined) {
      return this.unexpectedResponse<TopicDetail>(response.statusCode, response.challengeState, 'Linux.do 帖子详情响应为空。');
    }

    try {
      const payload: DiscourseTopicDetail = JSON.parse(response.data) as DiscourseTopicDetail;
      if (typeof payload.id !== 'number' || typeof payload.title !== 'string' ||
        !payload.post_stream || !payload.post_stream.posts) {
        return this.unexpectedResponse<TopicDetail>(response.statusCode, response.challengeState, 'Linux.do 帖子详情响应缺少必要字段。');
      }

      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: this.mapTopicDetail(payload)
      };
    } catch (error) {
      return this.unexpectedResponse<TopicDetail>(response.statusCode, response.challengeState, 'Linux.do 帖子详情响应不是有效 JSON。');
    }
  }

  async loadMorePosts(topicId: number, postIds: number[]): Promise<NetworkResult<TopicPost[]>> {
    if (postIds.length === 0) {
      return { success: true, statusCode: 200, challengeState: ChallengeState.NONE, data: [] };
    }

    const params: string[] = [];
    for (let index: number = 0; index < postIds.length; index++) {
      params.push(`post_ids%5B%5D=${postIds[index]}`);
    }
    const path: string = `/t/${topicId}/posts.json?${params.join('&')}&include_suggested=false`;

    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure<TopicPost[]>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<TopicPost[]>(response.statusCode, response.challengeState, 'Linux.do 加载更多楼层响应为空。');
    }

    try {
      const payload: DiscourseTopicDetail = JSON.parse(response.data) as DiscourseTopicDetail;
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: this.mapPosts(payload.post_stream?.posts)
      };
    } catch (error) {
      return this.unexpectedResponse<TopicPost[]>(response.statusCode, response.challengeState, 'Linux.do 加载更多楼层响应不是有效 JSON。');
    }
  }

  async reportTimings(topicId: number, timings: Map<number, number>, topicTime: number): Promise<NetworkResult<string>> {
    // 编码成 Discourse 期望的 application/x-www-form-urlencoded:
    // timings%5B楼号%5D=毫秒&...&topic_time=毫秒&topic_id=id
    const parts: string[] = [];
    timings.forEach((milliseconds: number, postNumber: number) => {
      parts.push(`timings%5B${postNumber}%5D=${Math.round(milliseconds)}`);
    });
    parts.push(`topic_time=${Math.round(topicTime)}`);
    parts.push(`topic_id=${topicId}`);
    const body: string = parts.join('&');
    // 把 Referer 设成帖子页(对齐官方 timings 请求),让 CF 不再把这条后台 POST 当异常拦下。
    const referrer: string = `${AppConstants.BASE_URL}/t/topic/${topicId}`;
    // 后台上报不弹 CF 验证页(notifyChallenge:false)。
    return this.bridge.postForm('/topics/timings', body, { notifyChallenge: false, referrer: referrer });
  }

  // discourse-reactions:切换某楼的表情回应(点亮/取消/切换)。PUT 空 body,同一楼同一用户只保留一个回应。
  async toggleReaction(postId: number, topicId: number, reaction: string): Promise<NetworkResult<string>> {
    const path: string =
      `/discourse-reactions/posts/${postId}/custom-reactions/${encodeURIComponent(reaction)}/toggle.json`;
    const referrer: string = `${AppConstants.BASE_URL}/t/topic/${topicId}`;
    return this.bridge.putJson(path, { notifyChallenge: false, referrer: referrer });
  }

  // 发表评论/回复:POST /posts,body 为 JSON(对齐官方 composer 提交)。
  // 关键字段:raw(正文)、topic_id、category、archetype;其余为 composer 的默认/遥测字段。
  // typingDurationMs / composerOpenDurationMs 由调用方按真实交互时长传入(缺省给合理值)。
  async createReply(
    topicId: number,
    categoryId: number | undefined,
    raw: string,
    typingDurationMs: number = 0,
    composerOpenDurationMs: number = 0,
    replyToPostNumber?: number
  ): Promise<NetworkResult<CreateReplyOutcome>> {
    const payload: CreateReplyPayload = {
      raw: raw,
      unlist_topic: false,
      topic_id: topicId,
      is_warning: false,
      whisper: false,
      archetype: 'regular',
      typing_duration_msecs: Math.max(0, Math.round(typingDurationMs)),
      composer_open_duration_msecs: Math.max(0, Math.round(composerOpenDurationMs)),
      composer_version: 1,
      tags: [],
      featured_link: null,
      shared_draft: false,
      draft_key: `topic_${topicId}`,
      locale: '',
      image_sizes: {},
      nested_post: true
    };
    if (typeof categoryId === 'number') {
      payload.category = categoryId;
    }
    if (typeof replyToPostNumber === 'number') {
      payload.reply_to_post_number = replyToPostNumber;
    }
    const body: string = JSON.stringify(payload);
    const referrer: string = `${AppConstants.BASE_URL}/t/topic/${topicId}`;

    const response: NetworkResult<string> = await this.bridge.postJson('/posts', body, {
      notifyChallenge: true,
      referrer: referrer
    });
    if (!response.success) {
      return this.forwardFailure<CreateReplyOutcome>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<CreateReplyOutcome>(response.statusCode, response.challengeState, 'Linux.do 发表评论响应为空。');
    }

    try {
      // 直接发布:{ action:'create_post', success, post:{…} };楼层在 post 字段。
      // 进审核队列:{ action:'enqueued', success, pending_post:{…} },此时无即时楼层。
      const wrapper: CreatePostResponse = JSON.parse(response.data) as CreatePostResponse;
      const created: DiscoursePost | undefined = wrapper.post;
      const posts: TopicPost[] = created ? this.mapPosts([created]) : [];
      if (posts.length > 0) {
        return {
          success: true,
          statusCode: response.statusCode,
          challengeState: response.challengeState,
          data: { post: posts[0], pending: false }
        };
      }
      // 进入审核队列(等待管理员/系统批准),视为提交成功但没有可追加的楼层。
      if (wrapper.action === 'enqueued' || wrapper.pending_post !== undefined) {
        return {
          success: true,
          statusCode: response.statusCode,
          challengeState: response.challengeState,
          data: { pending: true }
        };
      }
      return this.unexpectedResponse<CreateReplyOutcome>(response.statusCode, response.challengeState, 'Linux.do 发表评论响应缺少楼层数据。');
    } catch (error) {
      return this.unexpectedResponse<CreateReplyOutcome>(response.statusCode, response.challengeState, 'Linux.do 发表评论响应不是有效 JSON。');
    }
  }

  // discourse-boosts:对某楼发一条 boost(短文本)。表单 POST,body 为 raw=<文本>。
  // 抓包确认:POST /discourse-boosts/posts/{postId}/boosts,application/x-www-form-urlencoded,
  // 响应 200 返回新建的 boost 对象(id/cooked/user{…})。CSRF/Referer 由 postForm 脚本自动带。
  async createBoost(postId: number, topicId: number, raw: string): Promise<NetworkResult<PostBoost>> {
    const path: string = `/discourse-boosts/posts/${postId}/boosts`;
    const body: string = `raw=${encodeURIComponent(raw)}`;
    const referrer: string = `${AppConstants.BASE_URL}/t/topic/${topicId}`;
    const response: NetworkResult<string> = await this.bridge.postForm(path, body, {
      notifyChallenge: true,
      referrer: referrer
    });
    if (!response.success) {
      return this.forwardFailure<PostBoost>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<PostBoost>(response.statusCode, response.challengeState, 'Linux.do 发送 boost 响应为空。');
    }

    try {
      const created: DiscourseBoost = JSON.parse(response.data) as DiscourseBoost;
      const boosts: PostBoost[] = this.mapBoosts([created]);
      if (boosts.length > 0) {
        return {
          success: true,
          statusCode: response.statusCode,
          challengeState: response.challengeState,
          data: boosts[0]
        };
      }
      return this.unexpectedResponse<PostBoost>(response.statusCode, response.challengeState, 'Linux.do 发送 boost 响应缺少 boost 数据。');
    } catch (error) {
      return this.unexpectedResponse<PostBoost>(response.statusCode, response.challengeState, 'Linux.do 发送 boost 响应不是有效 JSON。');
    }
  }

  private getLatestPath(page: number): string {
    if (page <= 0) {
      return '/latest.json';
    }
    return `/latest.json?page=${page}`;
  }

  private getTopicDetailPath(topicId: number, slug?: string): string {
    if (slug && slug.length > 0) {
      return `/t/${encodeURIComponent(slug)}/${topicId}.json`;
    }
    return `/t/${topicId}.json`;
  }

  private mapTopics(sourceTopics: DiscourseTopic[], sourceUsers?: DiscourseUser[]): Topic[] {
    const topics: Topic[] = [];
    for (let index: number = 0; index < sourceTopics.length; index++) {
      const sourceTopic: DiscourseTopic = sourceTopics[index];
      if (typeof sourceTopic.id !== 'number' || typeof sourceTopic.title !== 'string') {
        continue;
      }

      // Topic 现为 @Observed class,须 new 实例(对象字面量不会被 @ObjectLink 观测)。
      const topic: Topic = new Topic();
      topic.id = sourceTopic.id;
      topic.title = sourceTopic.title;
      topic.slug = sourceTopic.slug;
      topic.categoryId = sourceTopic.category_id;
      topic.tags = this.mapTags(sourceTopic.tags);
      topic.postsCount = sourceTopic.posts_count;
      topic.replyCount = sourceTopic.reply_count;
      topic.likeCount = sourceTopic.like_count;
      topic.createdAt = sourceTopic.created_at;
      topic.lastPostedAt = sourceTopic.last_posted_at;
      topic.unseen = typeof sourceTopic.unseen === 'boolean' ? sourceTopic.unseen : undefined;
      topic.unreadPosts = typeof sourceTopic.unread_posts === 'number' ? sourceTopic.unread_posts : undefined;
      topic.author = this.findOriginalPoster(sourceTopic, sourceUsers);
      topics.push(topic);
    }
    return topics;
  }

  private mapTags(sourceTags?: Object[]): TopicTag[] {
    const tags: TopicTag[] = [];
    if (!sourceTags) {
      return tags;
    }

    for (let index: number = 0; index < sourceTags.length; index++) {
      const tag: TopicTag | undefined = this.mapTag(sourceTags[index]);
      if (tag) {
        tags.push(tag);
      }
    }
    return tags;
  }

  private mapTag(sourceTag: Object): TopicTag | undefined {
    if (sourceTag === undefined || sourceTag === null) {
      return undefined;
    }

    if (typeof sourceTag === 'string') {
      const name: string = (sourceTag as string).trim();
      return name.length > 0 ? { name } : undefined;
    }

    if (typeof sourceTag === 'number' || typeof sourceTag === 'boolean') {
      const name: string = sourceTag.toString().trim();
      return name.length > 0 ? { name } : undefined;
    }

    const source: Record<string, Object> = sourceTag as Record<string, Object>;
    const name: string = this.readString(source['name']);
    const slug: string = this.readString(source['slug']);
    const displayName: string = name.length > 0 ? name : slug;
    if (displayName.length === 0) {
      return undefined;
    }

    const tag: TopicTag = { name: displayName };
    const id: number = this.readNumber(source['id']);
    if (id > 0) {
      tag.id = id;
    }
    if (slug.length > 0) {
      tag.slug = slug;
    }
    return tag;
  }

  private findOriginalPoster(topic: DiscourseTopic, users?: DiscourseUser[]): User | undefined {
    if (!topic.posters || !users) {
      return undefined;
    }

    if (topic.posters.length === 0 || typeof topic.posters[0].user_id !== 'number') {
      return undefined;
    }

    const userId: number = topic.posters[0].user_id;
    for (let userIndex: number = 0; userIndex < users.length; userIndex++) {
      const sourceUser: DiscourseUser = users[userIndex];
      if (sourceUser.id === userId && sourceUser.username) {
        return {
          id: sourceUser.id,
          username: sourceUser.username,
          displayName: sourceUser.name,
          avatarTemplate: sourceUser.avatar_template,
          animatedAvatar: sourceUser.animated_avatar ? sourceUser.animated_avatar : undefined
        };
      }
    }

    return undefined;
  }

  private hasMoreTopics(topicList: DiscourseTopicList): boolean {
    return typeof topicList.more_topics_url === 'string' && topicList.more_topics_url.length > 0;
  }

  private mapTopicDetail(sourceTopic: DiscourseTopicDetail): TopicDetail {
    return {
      id: sourceTopic.id as number,
      title: sourceTopic.title as string,
      slug: sourceTopic.slug,
      categoryId: sourceTopic.category_id,
      tags: this.mapTags(sourceTopic.tags),
      postsCount: sourceTopic.posts_count,
      replyCount: sourceTopic.reply_count,
      likeCount: sourceTopic.like_count,
      viewCount: sourceTopic.views,
      createdAt: sourceTopic.created_at,
      posts: this.mapPosts(sourceTopic.post_stream?.posts),
      lastReadPostNumber: typeof sourceTopic.last_read_post_number === 'number' ? sourceTopic.last_read_post_number : undefined,
      highestPostNumber: typeof sourceTopic.highest_post_number === 'number' ? sourceTopic.highest_post_number : undefined,
      unreadPosts: typeof sourceTopic.unread_posts === 'number' ? sourceTopic.unread_posts : undefined,
      stream: this.mapStream(sourceTopic.post_stream?.stream)
    };
  }

  private mapStream(stream?: number[]): number[] {
    const out: number[] = [];
    if (!stream) {
      return out;
    }
    for (let index: number = 0; index < stream.length; index++) {
      const value: number = stream[index];
      if (typeof value === 'number') {
        out.push(value);
      }
    }
    return out;
  }

  private mapPosts(sourcePosts?: DiscoursePost[]): TopicPost[] {
    const posts: TopicPost[] = [];
    if (!sourcePosts) {
      return posts;
    }

    for (let index: number = 0; index < sourcePosts.length; index++) {
      const sourcePost: DiscoursePost = sourcePosts[index];
      if (typeof sourcePost.id !== 'number' || typeof sourcePost.post_number !== 'number') {
        continue;
      }

      const cookedHtml: string = sourcePost.cooked ? sourcePost.cooked : '';
      // TopicPost 现为 @Observed class,须 new 实例(对象字面量不会被 @ObjectLink 观测)。
      const post: TopicPost = new TopicPost();
      post.id = sourcePost.id;
      post.topicId = sourcePost.topic_id;
      post.postNumber = sourcePost.post_number;
      post.cookedHtml = cookedHtml;
      post.plainText = this.htmlToPlainText(cookedHtml);
      post.createdAt = sourcePost.created_at;
      post.updatedAt = sourcePost.updated_at;
      post.replyCount = sourcePost.reply_count;
      post.likeCount = sourcePost.like_count;
      post.author = this.mapPostAuthor(sourcePost);
      post.read = typeof sourcePost.read === 'boolean' ? sourcePost.read : undefined;
      post.userTitle = typeof sourcePost.user_title === 'string' ? sourcePost.user_title : undefined;
      post.reactions = this.mapReactions(sourcePost.reactions);
      post.reactionUsersCount =
        typeof sourcePost.reaction_users_count === 'number' ? sourcePost.reaction_users_count : undefined;
      const currentReactionId: string | undefined = sourcePost.current_user_reaction?.id;
      post.currentUserReaction =
        typeof currentReactionId === 'string' && currentReactionId.length > 0 ? currentReactionId : undefined;
      post.boosts = this.mapBoosts(sourcePost.boosts);
      post.canBoost = sourcePost.can_boost === true;
      posts.push(post);
    }

    return posts;
  }

  private mapReactions(source?: DiscourseReaction[]): PostReaction[] {
    const reactions: PostReaction[] = [];
    if (!source) {
      return reactions;
    }
    for (let index: number = 0; index < source.length; index++) {
      const item: DiscourseReaction = source[index];
      if (typeof item.id !== 'string' || item.id.length === 0) {
        continue;
      }
      reactions.push({
        id: item.id,
        count: typeof item.count === 'number' ? item.count : 0
      });
    }
    return reactions;
  }

  private mapBoosts(source?: DiscourseBoost[]): PostBoost[] {
    const boosts: PostBoost[] = [];
    if (!source) {
      return boosts;
    }
    for (let index: number = 0; index < source.length; index++) {
      const item: DiscourseBoost = source[index];
      if (typeof item.id !== 'number') {
        continue;
      }
      const user: User | undefined = this.mapBoostUser(item.user);
      if (!user) {
        continue;
      }
      boosts.push({
        id: item.id,
        cookedHtml: item.cooked ? item.cooked : '',
        user: user
      });
    }
    return boosts;
  }

  private mapBoostUser(source?: DiscourseBoostUser): User | undefined {
    if (!source || !source.username) {
      return undefined;
    }
    return {
      id: typeof source.id === 'number' ? source.id : 0,
      username: source.username,
      displayName: source.name,
      avatarTemplate: source.avatar_template,
      animatedAvatar: source.animated_avatar ? source.animated_avatar : undefined
    };
  }

  private mapPostAuthor(sourcePost: DiscoursePost): User | undefined {
    if (!sourcePost.username) {
      return undefined;
    }

    return {
      id: typeof sourcePost.user_id === 'number' ? sourcePost.user_id : 0,
      username: sourcePost.username,
      displayName: sourcePost.name,
      avatarTemplate: sourcePost.avatar_template,
      animatedAvatar: sourcePost.animated_avatar ? sourcePost.animated_avatar : undefined
    };
  }

  private htmlToPlainText(html: string): string {
    return CookedHtmlParser.toPlainText(html);
  }

  private readString(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return value.toString().trim();
  }

  private readNumber(value: Object | undefined): number {
    if (value === undefined || value === null) {
      return 0;
    }
    const numberValue: number = Number(value.toString());
    return isNaN(numberValue) ? 0 : numberValue;
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
