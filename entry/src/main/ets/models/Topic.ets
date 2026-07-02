import { User } from './User';

export interface Topic {
  id: number;
  title: string;
  slug?: string;
  postsCount?: number;
  replyCount?: number;
  likeCount?: number;
  createdAt?: string;
  lastPostedAt?: string;
  author?: User;
}
