import { User } from './User';
import { TopicTag } from './Topic';

// discourse-reactions 插件:一条楼层获得的单个表情回应(短名 + 数量)。
export interface PostReaction {
  id: string;
  count: number;
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
