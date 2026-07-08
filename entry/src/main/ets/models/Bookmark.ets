import { TopicTag } from './Topic';
import { User } from './User';

// 书签列表项:来自 /u/{username}/bookmarks.json 的 user_bookmark_list.bookmarks[]。
// 单条对应"某话题的某一层楼"的收藏,excerpt 是那层楼的正文摘要(已从 HTML 转纯文本)。
export interface Bookmark {
  id: number;
  topicId: number;
  title: string;
  // 被收藏楼层的内容摘要,纯文本。
  excerpt: string;
  // 收藏定位到的楼号;主楼(1)不展示 #N 前缀,但仍用于跳转。
  linkedPostNumber: number;
  pinned: boolean;
  categoryId?: number;
  tags: TopicTag[];
  // 被收藏楼层的作者。
  author?: User;
  // 话题总楼数,用于推算回复数(与首页口径一致:总楼数 - 1)。
  highestPostNumber?: number;
  // 收藏时间(非话题活跃时间)。
  createdAt?: string;
}

// 一页书签 + 下一页地址(more_bookmarks_url,缺省表示到底)。
export interface BookmarkPage {
  bookmarks: Bookmark[];
  moreUrl?: string;
}
