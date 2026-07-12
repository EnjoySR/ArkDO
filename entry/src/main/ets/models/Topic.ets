import { User } from './User';

export interface TopicTag {
  id?: number;
  name: string;
  slug?: string;
}

export interface TopicCategory {
  id: number;
  name: string;
  color: string;
  textColor: string;
  slug?: string;
  parentCategoryId?: number;
  uploadedLogo?: string;
  icon?: string;
  readRestricted?: boolean;
}

// @Observed:列表项的 unseen / unreadPosts 变化(点击已读、返回同步)要能驱动
// TopicListItem(@ObjectLink)精准重渲染,只刷新那一行的蓝点/未读徽标。
@Observed
export class Topic {
  id: number = 0;
  title: string = '';
  slug?: string;
  categoryId?: number;
  tags: TopicTag[] = [];
  postsCount?: number;
  replyCount?: number;
  likeCount?: number;
  createdAt?: string;
  lastPostedAt?: string;
  // unseen:全新未读主题(标题后蓝点);unreadPosts:已读过但又有新回复的未读数(数字徽标)。
  unseen?: boolean;
  unreadPosts?: number;
  // 未读徽标跳转定位:目标楼号 = lastReadPostNumber + 1,以 highestPostNumber 封顶。匿名时无值。
  lastReadPostNumber?: number;
  highestPostNumber?: number;
  author?: User;
  // discourse-solved:该主题是否有被采纳的解决方案(列表接口 has_accepted_answer)。
  // 为真时列表标题行首内联绿色 far-square-check 标记,与详情页一致。
  hasAcceptedAnswer?: boolean;
}
