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
