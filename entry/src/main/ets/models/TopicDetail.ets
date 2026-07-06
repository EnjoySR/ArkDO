import { User } from './User';
import { TopicTag } from './Topic';

// discourse-reactions 插件:一条楼层获得的单个表情回应(短名 + 数量)。
export interface PostReaction {
  id: string;
  count: number;
}

// discourse-boosts 插件:一条楼层下别人发的 boost(头像 + 一句短内容)。
// 保留 cooked HTML(而非纯文本):boost 可能是纯 emoji 或文字+emoji 混排,
// 渲染时按行内节点解析,避免纯 emoji 被当作空文本丢失。
export interface PostBoost {
  id: number;
  cookedHtml: string;
  user: User;
}

// discourse-poll 插件:一个投票选项(id + 展示文字 + 当前票数)。
export interface PollOption {
  id: string;
  label: string;
  votes: number;
}

// 投票/撤销后服务端返回的真实值,用于成功后校正本地(吸收他人并发投票带来的偏差)。
// 放在模型层供 TopicService(产出)与 PollMutation(消费)共用,避免结构化类型不兼容。
export interface PollVoteResult {
  options: PollOption[];
  voters: number;
  chosenOptionIds: string[];
}

// discourse-poll 插件:一个投票的完整状态。静态骨架来自 cooked HTML,
// 动态数据(票数/投票人数/当前用户已投项/能否投票)来自 post JSON 的 polls 字段。
// @Observed:投票/撤销后就地改字段即可驱动 PollView(@ObjectLink)精准重渲染,
// 与乐观更新的表情回应同理。
@Observed
export class Poll {
  name: string = 'poll';
  title?: string;
  type: string = 'regular';        // 'regular'(单选) | 'multiple'(多选) | 'number'
  status: string = 'open';         // 'open' | 'closed'
  isPublic: boolean = false;       // public:是否公开投票(可见谁投了)
  results: string = 'always';      // 'always' | 'on_vote' | 'on_close' | 'staff_only'
  options: PollOption[] = [];
  voters: number = 0;
  // 当前登录用户已投的选项 id(来自 post.polls_votes[name]);空数组=未投。
  chosenOptionIds: string[] = [];
  // 当前用户能否投票(来自 post.can_vote)。
  canVote: boolean = false;
}

// @Observed:楼层的 read 变化要能驱动 TopicPostItem(@ObjectLink)重渲染,
// 从而让蓝点淡出动画生效。
@Observed
export class TopicPost {
  id: number = 0;
  topicId?: number;
  postNumber: number = 0;
  cookedHtml: string = '';
  plainText: string = '';
  createdAt?: string;
  updatedAt?: string;
  replyCount?: number;
  // 本楼是回复哪一楼(reply_to_post_number)+被回复者(reply_to_user)。二者齐备时头部右上角显示
  // 「share 图标 + 被回复者头像」,点击滚动定位到 replyToPostNumber 对应楼层。
  replyToPostNumber?: number;
  replyToUser?: User;
  likeCount?: number;
  author?: User;
  read?: boolean;
  userTitle?: string;
  // 表情回应:各表情汇总 + 回应总人数(reaction_users_count)。
  reactions?: PostReaction[];
  reactionUsersCount?: number;
  // 当前登录用户对该楼的回应短名(current_user_reaction.id),无则 undefined。驱动点赞按钮图标。
  currentUserReaction?: string;
  // discourse-boosts:该楼下别人发的 boost 列表(随 posts.json 返回)。
  boosts?: PostBoost[];
  // 当前登录用户是否可对该楼发 boost(can_boost);为真时显示火箭入口。
  canBoost?: boolean;
  // discourse-poll:该楼包含的投票(随 posts.json 返回);cooked HTML 里的 poll 块按 name 关联。
  polls?: Poll[];
}

export interface TopicDetail {
  id: number;
  title: string;
  slug?: string;
  categoryId?: number;
  tags: TopicTag[];
  postsCount?: number;
  replyCount?: number;
  likeCount?: number;
  viewCount?: number;
  createdAt?: string;
  posts: TopicPost[];
  lastReadPostNumber?: number;
  highestPostNumber?: number;
  unreadPosts?: number;
  stream?: number[];
}
