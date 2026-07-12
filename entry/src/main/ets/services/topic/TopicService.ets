import { Topic, TopicCategory, TopicTag } from '../../models/Topic';
import { AcceptedAnswer, Poll, PollOption, PollVoteResult, PostBoost, PostReaction, TopicDetail, TopicPost } from '../../models/TopicDetail';
import { User } from '../../models/User';
import { CookedHtmlParser } from '../content/CookedHtmlParser';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';
import { AppConstants } from '../../common/constants/AppConstants';
import { FeedKey } from '../site/FeedPrefs';

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
  last_read_post_number?: number;
  highest_post_number?: number;
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
  flair_url?: string;
  flair_bg_color?: string;
  flair_color?: string;
  flair_name?: string;
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
  user_badges?: DiscourseUserBadges;
  accepted_answers?: DiscourseAcceptedAnswer[];
}

interface DiscoursePostStream {
  posts?: DiscoursePost[];
  stream?: number[];
}

// discourse-solved 采纳答案快照:自带 cooked HTML,面板据此自渲染,无需回列表找楼。
interface DiscourseAcceptedAnswer {
  post_number?: number;
  username?: string;
  avatar_template?: string;
  created_at?: string;
  cooked?: string;
}

// 楼层作者状态:user_status.emoji 是具名表情短名(lollipop / tieba_003 …),经 EmojiUrlRegistry 查 url。
interface DiscourseUserStatus {
  emoji?: string;
  description?: string;
}

// 顶层 user_badges:users 按 user_id 给出展示的 badge_ids,badges 按 id 给出图标名(FontAwesome)。
interface DiscourseUserBadges {
  users?: Record<string, DiscourseUserBadgeUser>;
  badges?: Record<string, DiscourseBadgeDef>;
}

interface DiscourseUserBadgeUser {
  id?: number;
  badge_ids?: number[];
}

interface DiscourseBadgeDef {
  id?: number;
  icon?: string;
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

// discourse-poll:一个投票选项(id + 展示 html + 票数)。
interface DiscoursePollOption {
  id?: string;
  html?: string;
  votes?: number;
}

// discourse-poll:一个投票的服务端结构。
interface DiscoursePoll {
  name?: string;
  type?: string;
  status?: string;
  public?: boolean;
  results?: string;
  options?: DiscoursePollOption[];
  voters?: number;
  title?: string;
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
  user_status?: DiscourseUserStatus;
  flair_url?: string;
  flair_bg_color?: string;
  flair_color?: string;
  flair_name?: string;
  reply_to_post_number?: number;
  reply_to_user?: DiscourseBoostUser;
  reactions?: DiscourseReaction[];
  reaction_users_count?: number;
  current_user_reaction?: DiscourseCurrentReaction;
  boosts?: DiscourseBoost[];
  can_boost?: boolean;
  bookmarked?: boolean;
  bookmark_id?: number;
  // discourse-poll:该楼的投票列表、当前用户各投票的已投项、能否投票。
  polls?: DiscoursePoll[];
  polls_votes?: Record<string, string[]>;
  can_vote?: boolean;
}

// PUT/DELETE /polls/vote 的响应外壳:poll 为更新后的投票,vote 为当前用户已投项(撤销时缺省)。
interface DiscoursePollVoteResponse {
  poll?: DiscoursePoll;
  vote?: string[];
}

// POST /bookmarks.json 的响应:{ success:"OK", id:<bookmarkId> }。
interface DiscourseBookmarkResponse {
  success?: string;
  id?: number;
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
    return this.getFeedPage(FeedKey.LATEST, page);
  }

  // 全站内置入口(最新/热门/未读/新主题)分页:响应体均为 topic_list.topics 结构,共用解析。
  async getFeedPage(feedKey: string, page: number): Promise<NetworkResult<TopicPage>> {
    return this.getTopicListPage(this.getFeedPath(feedKey, page), page);
  }

  // 某版块分页:/c/{slug}/{id}/l/latest.json,同为 topic_list.topics 结构。
  async getCategoryTopicsPage(category: TopicCategory, page: number): Promise<NetworkResult<TopicPage>> {
    return this.getTopicListPage(this.getCategoryPath(category, page), page);
  }

  private async getTopicListPage(path: string, page: number): Promise<NetworkResult<TopicPage>> {
    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure<TopicPage>(response);
    }

    if (response.data === undefined) {
      return this.unexpectedResponse<TopicPage>(response.statusCode, response.challengeState, 'Linux.do 帖子列表响应为空。');
    }

    try {
      const payload: DiscourseLatestResponse = JSON.parse(response.data) as DiscourseLatestResponse;
      if (!payload.topic_list || !payload.topic_list.topics) {
        return this.unexpectedResponse<TopicPage>(response.statusCode, response.challengeState, 'Linux.do 帖子列表响应缺少 topic_list.topics。');
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
      return this.unexpectedResponse<TopicPage>(response.statusCode, response.challengeState, 'Linux.do 帖子列表响应不是有效 JSON。');
    }
  }

  // postNumber>1 时请求带楼号的详情:服务端以该楼为锚返回一窗楼层(前 1/4 后 3/4),用于跳转未读/指定楼。
  async getTopicDetail(topicId: number, slug?: string, postNumber?: number): Promise<NetworkResult<TopicDetail>> {
    const response: NetworkResult<string> = await this.bridge.getJson(this.getTopicDetailPath(topicId, slug, postNumber));
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
        data: this.mapPosts(payload.post_stream?.posts, this.buildBadgeIconMap(payload.user_badges))
      };
    } catch (error) {
      return this.unexpectedResponse<TopicPost[]>(response.statusCode, response.challengeState, 'Linux.do 加载更多楼层响应不是有效 JSON。');
    }
  }

  // 加载某楼的「被回复」列表:GET /posts/{postId}/replies?after=1。
  // 返回的是裸 post 对象数组(顶层 [...],非 post_stream),元素结构与 DiscoursePost 一致,直接喂 mapPosts。
  // GET 无需 CSRF/referer。
  async getPostReplies(postId: number): Promise<NetworkResult<TopicPost[]>> {
    const path: string = `/posts/${postId}/replies?after=1`;

    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure<TopicPost[]>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<TopicPost[]>(response.statusCode, response.challengeState, 'Linux.do 被回复列表响应为空。');
    }

    try {
      const payload: DiscoursePost[] = JSON.parse(response.data) as DiscoursePost[];
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: this.mapPosts(payload)
      };
    } catch (error) {
      return this.unexpectedResponse<TopicPost[]>(response.statusCode, response.challengeState, 'Linux.do 被回复列表响应不是有效 JSON。');
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

  // discourse-poll:给某楼的投票投票。PUT /polls/vote,form body:post_id、poll_name、options[]。
  // 响应 200 返回 { poll:{更新后}, vote:[已投项] };解析出票数/人数/已投项供本地校正。
  async votePoll(postId: number, topicId: number, pollName: string, optionIds: string[]): Promise<NetworkResult<PollVoteResult>> {
    const parts: string[] = [`post_id=${postId}`, `poll_name=${encodeURIComponent(pollName)}`];
    for (let index: number = 0; index < optionIds.length; index++) {
      parts.push(`options%5B%5D=${encodeURIComponent(optionIds[index])}`);
    }
    const referrer: string = `${AppConstants.BASE_URL}/t/topic/${topicId}`;
    const response: NetworkResult<string> =
      await this.bridge.putForm('/polls/vote', parts.join('&'), { notifyChallenge: false, referrer: referrer });
    return this.parsePollVoteResponse(response);
  }

  // discourse-poll:撤销某楼投票。DELETE /polls/vote,form body:post_id、poll_name。
  // 响应 200 返回 { poll:{更新后} }(无 vote,即已投项为空)。
  async removePollVote(postId: number, topicId: number, pollName: string): Promise<NetworkResult<PollVoteResult>> {
    const body: string = `post_id=${postId}&poll_name=${encodeURIComponent(pollName)}`;
    const referrer: string = `${AppConstants.BASE_URL}/t/topic/${topicId}`;
    const response: NetworkResult<string> =
      await this.bridge.deleteForm('/polls/vote', body, { notifyChallenge: false, referrer: referrer });
    return this.parsePollVoteResponse(response);
  }

  private parsePollVoteResponse(response: NetworkResult<string>): NetworkResult<PollVoteResult> {
    if (!response.success) {
      return this.forwardFailure<PollVoteResult>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<PollVoteResult>(response.statusCode, response.challengeState, 'Linux.do 投票响应为空。');
    }
    try {
      const wrapper: DiscoursePollVoteResponse = JSON.parse(response.data) as DiscoursePollVoteResponse;
      if (!wrapper.poll) {
        return this.unexpectedResponse<PollVoteResult>(response.statusCode, response.challengeState, 'Linux.do 投票响应缺少 poll 字段。');
      }
      const chosen: string[] = Array.isArray(wrapper.vote) ? wrapper.vote.slice() : [];
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: {
          options: this.mapPollOptions(wrapper.poll.options),
          voters: typeof wrapper.poll.voters === 'number' ? wrapper.poll.voters : 0,
          chosenOptionIds: chosen
        }
      };
    } catch (error) {
      return this.unexpectedResponse<PollVoteResult>(response.statusCode, response.challengeState, 'Linux.do 投票响应不是有效 JSON。');
    }
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

  // 书签:给某楼加书签。POST /bookmarks.json,form body(对齐抓包):
  // reminder_at=&auto_delete_preference=3&bookmarkable_id=<postId>&bookmarkable_type=Post。
  // 响应 { success:"OK", id:<bookmarkId> };返回 bookmarkId 供后续取消。
  async addBookmark(postId: number, topicId: number): Promise<NetworkResult<number>> {
    const body: string = `reminder_at=&auto_delete_preference=3&bookmarkable_id=${postId}&bookmarkable_type=Post`;
    const referrer: string = `${AppConstants.BASE_URL}/t/topic/${topicId}`;
    const response: NetworkResult<string> = await this.bridge.postForm('/bookmarks.json', body, {
      notifyChallenge: true,
      referrer: referrer
    });
    if (!response.success) {
      return this.forwardFailure<number>(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse<number>(response.statusCode, response.challengeState, 'Linux.do 添加书签响应为空。');
    }
    try {
      const wrapper: DiscourseBookmarkResponse = JSON.parse(response.data) as DiscourseBookmarkResponse;
      if (typeof wrapper.id !== 'number') {
        return this.unexpectedResponse<number>(response.statusCode, response.challengeState, 'Linux.do 添加书签响应缺少 id。');
      }
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: wrapper.id
      };
    } catch (error) {
      return this.unexpectedResponse<number>(response.statusCode, response.challengeState, 'Linux.do 添加书签响应不是有效 JSON。');
    }
  }

  // 书签:取消某个书签。DELETE /bookmarks/<bookmarkId>.json,无 body。响应 { success:"OK", topic_bookmarked:bool }。
  async removeBookmark(bookmarkId: number, topicId: number): Promise<NetworkResult<string>> {
    const referrer: string = `${AppConstants.BASE_URL}/t/topic/${topicId}`;
    return this.bridge.deleteForm(`/bookmarks/${bookmarkId}.json`, '', {
      notifyChallenge: true,
      referrer: referrer
    });
  }

  private getFeedPath(feedKey: string, page: number): string {
    const suffix: string = page > 0 ? `?page=${page}` : '';
    switch (feedKey) {
      case FeedKey.TOP:
        return `/top.json${suffix}`;
      case FeedKey.UNREAD:
        return `/unread.json${suffix}`;
      case FeedKey.NEW:
        return `/new.json${suffix}`;
      default:
        return `/latest.json${suffix}`;
    }
  }

  private getCategoryPath(category: TopicCategory, page: number): string {
    const suffix: string = page > 0 ? `?page=${page}` : '';
    if (category.slug && category.slug.length > 0) {
      return `/c/${encodeURIComponent(category.slug)}/${category.id}/l/latest.json${suffix}`;
    }
    return `/c/${category.id}/l/latest.json${suffix}`;
  }

  private getTopicDetailPath(topicId: number, slug?: string, postNumber?: number): string {
    // 楼号作为路径段(对齐官网 /t/<slug>/<id>/<楼号>);1 楼等同默认首屏,不拼。
    const anchor: string = postNumber !== undefined && postNumber > 1 ? `/${postNumber}` : '';
    if (slug && slug.length > 0) {
      return `/t/${encodeURIComponent(slug)}/${topicId}${anchor}.json`;
    }
    return `/t/${topicId}${anchor}.json`;
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
      topic.lastReadPostNumber = typeof sourceTopic.last_read_post_number === 'number' ? sourceTopic.last_read_post_number : undefined;
      topic.highestPostNumber = typeof sourceTopic.highest_post_number === 'number' ? sourceTopic.highest_post_number : undefined;
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
          animatedAvatar: sourceUser.animated_avatar ? sourceUser.animated_avatar : undefined,
          flairUrl: typeof sourceUser.flair_url === 'string' && sourceUser.flair_url.length > 0
            ? sourceUser.flair_url : undefined,
          flairBgColor: typeof sourceUser.flair_bg_color === 'string' && sourceUser.flair_bg_color.length > 0
            ? sourceUser.flair_bg_color : undefined,
          flairColor: typeof sourceUser.flair_color === 'string' && sourceUser.flair_color.length > 0
            ? sourceUser.flair_color : undefined,
          flairName: typeof sourceUser.flair_name === 'string' && sourceUser.flair_name.length > 0
            ? sourceUser.flair_name : undefined
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
      posts: this.mapPosts(sourceTopic.post_stream?.posts, this.buildBadgeIconMap(sourceTopic.user_badges)),
      lastReadPostNumber: typeof sourceTopic.last_read_post_number === 'number' ? sourceTopic.last_read_post_number : undefined,
      highestPostNumber: typeof sourceTopic.highest_post_number === 'number' ? sourceTopic.highest_post_number : undefined,
      unreadPosts: typeof sourceTopic.unread_posts === 'number' ? sourceTopic.unread_posts : undefined,
      stream: this.mapStream(sourceTopic.post_stream?.stream),
      acceptedAnswers: this.mapAcceptedAnswers(sourceTopic.accepted_answers)
    };
  }

  // discourse-solved:采纳答案数组 → AcceptedAnswer 列表;缺 post_number 的条目丢弃(跳楼无落点)。
  private mapAcceptedAnswers(source?: DiscourseAcceptedAnswer[]): AcceptedAnswer[] | undefined {
    if (!source || source.length === 0) {
      return undefined;
    }
    const out: AcceptedAnswer[] = [];
    for (let index: number = 0; index < source.length; index++) {
      const item: DiscourseAcceptedAnswer = source[index];
      if (typeof item.post_number !== 'number') {
        continue;
      }
      const answer: AcceptedAnswer = new AcceptedAnswer();
      answer.postNumber = item.post_number;
      answer.username = item.username ?? '';
      answer.avatarTemplate = item.avatar_template ?? '';
      answer.createdAt = item.created_at ?? '';
      answer.cookedHtml = item.cooked ?? '';
      out.push(answer);
    }
    return out.length > 0 ? out : undefined;
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

  // 顶层 user_badges → Map<userId, 图标名[]>:users 里每个用户的 badge_ids 逐个到 badges 查 icon(FontAwesome 名)。
  // 只有展示了徽章的用户会出现在 users 里,其余楼层取不到 → badgeIcons 为空。
  private buildBadgeIconMap(source?: DiscourseUserBadges): Map<number, string[]> {
    const map: Map<number, string[]> = new Map();
    if (!source || !source.users || !source.badges) {
      return map;
    }
    const users: Record<string, DiscourseUserBadgeUser> = source.users;
    const badges: Record<string, DiscourseBadgeDef> = source.badges;
    const userKeys: string[] = Object.keys(users);
    for (let i: number = 0; i < userKeys.length; i++) {
      const user: DiscourseUserBadgeUser = users[userKeys[i]];
      if (!user || typeof user.id !== 'number' || !Array.isArray(user.badge_ids)) {
        continue;
      }
      const icons: string[] = [];
      for (let j: number = 0; j < user.badge_ids.length; j++) {
        const badge: DiscourseBadgeDef | undefined = badges[`${user.badge_ids[j]}`];
        if (badge && typeof badge.icon === 'string' && badge.icon.length > 0) {
          icons.push(badge.icon);
        }
      }
      if (icons.length > 0) {
        map.set(user.id, icons);
      }
    }
    return map;
  }

  private mapPosts(sourcePosts?: DiscoursePost[], badgeMap?: Map<number, string[]>): TopicPost[] {
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
      post.replyToPostNumber =
        typeof sourcePost.reply_to_post_number === 'number' ? sourcePost.reply_to_post_number : undefined;
      post.replyToUser = this.mapBoostUser(sourcePost.reply_to_user);
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
      post.bookmarked = sourcePost.bookmarked === true;
      post.bookmarkId = typeof sourcePost.bookmark_id === 'number' ? sourcePost.bookmark_id : undefined;
      post.polls = this.mapPolls(sourcePost);
      const statusEmoji: string | undefined = sourcePost.user_status?.emoji;
      post.statusEmoji =
        typeof statusEmoji === 'string' && statusEmoji.length > 0 ? statusEmoji : undefined;
      const authorId: number | undefined = typeof sourcePost.user_id === 'number' ? sourcePost.user_id : undefined;
      post.badgeIcons = badgeMap && authorId !== undefined ? badgeMap.get(authorId) : undefined;
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

  private mapPolls(sourcePost: DiscoursePost): Poll[] {
    const polls: Poll[] = [];
    const source: DiscoursePoll[] | undefined = sourcePost.polls;
    if (!source) {
      return polls;
    }
    const canVote: boolean = sourcePost.can_vote === true;
    const votesMap: Record<string, string[]> | undefined = sourcePost.polls_votes;
    for (let index: number = 0; index < source.length; index++) {
      const item: DiscoursePoll = source[index];
      // Poll 为 @Observed class,须 new 实例(对象字面量不会被 @ObjectLink 观测)。
      const poll: Poll = new Poll();
      poll.name = typeof item.name === 'string' && item.name.length > 0 ? item.name : 'poll';
      poll.title = typeof item.title === 'string' ? item.title : undefined;
      poll.type = typeof item.type === 'string' ? item.type : 'regular';
      poll.status = typeof item.status === 'string' ? item.status : 'open';
      poll.isPublic = item.public === true;
      poll.results = typeof item.results === 'string' ? item.results : 'always';
      poll.options = this.mapPollOptions(item.options);
      poll.voters = typeof item.voters === 'number' ? item.voters : 0;
      const chosen: string[] | undefined = votesMap ? votesMap[poll.name] : undefined;
      poll.chosenOptionIds = Array.isArray(chosen) ? chosen.slice() : [];
      poll.canVote = canVote;
      polls.push(poll);
    }
    return polls;
  }

  private mapPollOptions(source?: DiscoursePollOption[]): PollOption[] {
    const options: PollOption[] = [];
    if (!source) {
      return options;
    }
    for (let index: number = 0; index < source.length; index++) {
      const item: DiscoursePollOption = source[index];
      if (typeof item.id !== 'string' || item.id.length === 0) {
        continue;
      }
      options.push({
        id: item.id,
        label: CookedHtmlParser.toPlainText(item.html ? item.html : ''),
        votes: typeof item.votes === 'number' ? item.votes : 0
      });
    }
    return options;
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
      animatedAvatar: sourcePost.animated_avatar ? sourcePost.animated_avatar : undefined,
      flairUrl: typeof sourcePost.flair_url === 'string' && sourcePost.flair_url.length > 0
        ? sourcePost.flair_url : undefined,
      flairBgColor: typeof sourcePost.flair_bg_color === 'string' && sourcePost.flair_bg_color.length > 0
        ? sourcePost.flair_bg_color : undefined,
      flairColor: typeof sourcePost.flair_color === 'string' && sourcePost.flair_color.length > 0
        ? sourcePost.flair_color : undefined,
      flairName: typeof sourcePost.flair_name === 'string' && sourcePost.flair_name.length > 0
        ? sourcePost.flair_name : undefined
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
