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

export interface Topic {
  id: number;
  title: string;
  slug?: string;
  categoryId?: number;
  tags: TopicTag[];
  postsCount?: number;
  replyCount?: number;
  likeCount?: number;
  createdAt?: string;
  lastPostedAt?: string;
  author?: User;
}
