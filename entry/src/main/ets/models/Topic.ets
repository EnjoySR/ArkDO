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
  // 当前用户是否已收藏该主题(列表接口 topic 顶层 bookmarked)。为真时标题行首内联灰色书签标记,
  // 排在已解决勾选框之前。匿名/未读态可能为 null → 统一按 === true 判定。
  bookmarked?: boolean;
  // 搜索结果专用:命中楼层的高亮摘要纯文本(/search.json 的 posts[].blurb 去标签)。
  // 仅搜索列表填充,普通 feed 为 undefined,搜索结果项据此在标题下展示命中片段。
  searchBlurb?: string;
}
