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
  // 上报 /topics/timings 进行中:该楼蓝点进入"呼吸"(opacity 明暗来回)态,提示正在同步;
  // 上报成功→read=true 淡出,失败→回落静态。直接改字段由 @ObjectLink 精准重渲染。
  reporting?: boolean;
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
  // 书签:该楼是否已被当前用户加书签 + 书签 id(取消时用)。posts.json 的 bookmarked/bookmark_id;
  // 加/删成功后就地更新,由 @ObjectLink 驱动书签图标切换。
  bookmarked?: boolean;
  bookmarkId?: number;
  // 昵称后展示的状态表情短名(user_status.emoji,如 "lollipop"/"tieba_003");渲染时经 EmojiUrlRegistry 查 url。
  statusEmoji?: string;
  // 昵称后展示的徽章图标名数组(顶层 user_badges 按 user_id 解出的 FontAwesome 名,如 far-eye/seedling/hammer)。
  badgeIcons?: string[];
}

// discourse-solved:被采纳为解决方案的答案楼快照(topic.json 顶层 accepted_answers)。
// 快问快答/问答帖在一楼下方渲染「已解决」面板,内容完全自给(带 cooked HTML),
// 哪怕该答案楼尚未加载进列表也能展示;「阅读更多」据 postNumber 跳楼。
// 数组天然支持多解:一题多个采纳答案就铺多张卡片。
@Observed
export class AcceptedAnswer {
  postNumber: number = 0;
  username: string = '';
  avatarTemplate: string = '';
  createdAt: string = '';
  cookedHtml: string = '';
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
  // 主题作者(楼主)的用户 id:topic.json 的 details.created_by.id(回退顶层 user_id)。
  // 楼层作者 id 等于此值时,该楼是楼主发的,右下角渲染「TOPIC OWNER」标记。
  createdById?: number;
  lastReadPostNumber?: number;
  highestPostNumber?: number;
  unreadPosts?: number;
  stream?: number[];
  // discourse-solved 采纳答案面板数据源;无解或非问答帖为 undefined/空数组。
  acceptedAnswers?: AcceptedAnswer[];
}
