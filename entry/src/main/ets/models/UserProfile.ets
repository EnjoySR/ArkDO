// 个人中心数据模型:字段分别来自
// /u/{username}.json(资料)、/u/{username}/summary.json(统计+徽章)、/user_actions.json(最近活动)。
import { TopicTag } from './Topic';
import { User } from './User';

export interface UserProfileDetail {
  id: number;
  username: string;
  displayName?: string;
  // 用户头衔(Discourse user.title,如「活跃用户」),站点可自定义。
  title?: string;
  trustLevel?: number;
  createdAt?: string;
  lastPostedAt?: string;
  badgeCount?: number;
  profileViewCount?: number;
}

export interface UserSummaryStats {
  daysVisited: number;
  // 阅读时长,秒。
  timeReadSeconds: number;
  likesGiven: number;
  likesReceived: number;
  topicCount: number;
  postCount: number;
  topicsEntered: number;
  // solved 插件的被采纳数,站点未启用时为 undefined。
  solvedCount?: number;
}

// Discourse badge_type_id:1=金 2=银 3=铜。
// 图标二选一:imageUrl(站点上传的图片徽章,CDN 直链)优先,否则 icon(FontAwesome 名,
// 与 rawfile/fa_icons 的文件名一致,按徽章等级色染色)。
export interface UserBadgeItem {
  id: number;
  name: string;
  badgeTypeId: number;
  icon?: string;
  imageUrl?: string;
  // 本用户获得该徽章的次数(可重复获得的徽章 >1 时展示 ×N)。
  grantCount?: number;
  // 「全部徽章」页额外字段(summary 精简版不含):徽章说明与授予时间。
  description?: string;
  grantedAt?: string;
}

// 「全部徽章」页按等级(金/银/铜)分组。
export interface UserBadgeGroup {
  typeId: number;
  // 分组标题:优先服务端 badge_types.name,否则金牌/银牌/铜牌兜底。
  typeName: string;
  badges: UserBadgeItem[];
}

export interface UserSummary {
  stats: UserSummaryStats;
  topBadges: UserBadgeItem[];
}

// /user_actions.json 的 action_type:4=发布话题 5=回复。
export enum UserActionType {
  NEW_TOPIC = 4,
  REPLY = 5
}

export interface UserActivityItem {
  actionType: number;
  topicId: number;
  postNumber?: number;
  title: string;
  // 该动作对应楼层的正文摘要(纯文本);列表页用,个人中心预览不显示。
  excerpt: string;
  categoryId?: number;
  tags: TopicTag[];
  createdAt?: string;
  // 该动作对应楼层的作者(user_actions 的 avatar_template/username/name);列表左侧出头像。
  // 接口不返回 flair 字段,故头像无右下角标。
  author?: User;
}

// 一页用户动态 + 是否还有更多(user_actions 按 offset 翻页)。
export interface UserActivityPage {
  items: UserActivityItem[];
  hasMore: boolean;
}
