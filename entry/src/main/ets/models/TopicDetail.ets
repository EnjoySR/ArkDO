import { User } from './User';
import { TopicTag } from './Topic';

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
