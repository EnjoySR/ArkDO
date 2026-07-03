import { User } from './User';

export interface TopicPost {
  id: number;
  topicId?: number;
  postNumber: number;
  cookedHtml: string;
  plainText: string;
  createdAt?: string;
  updatedAt?: string;
  replyCount?: number;
  likeCount?: number;
  author?: User;
}

export interface TopicDetail {
  id: number;
  title: string;
  slug?: string;
  postsCount?: number;
  replyCount?: number;
  likeCount?: number;
  viewCount?: number;
  createdAt?: string;
  posts: TopicPost[];
}
