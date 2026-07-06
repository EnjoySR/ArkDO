// Discourse /notifications.json 的原始结构(仅取用到的字段)。
export interface RawNotificationData {
  topic_title?: string;
  display_username?: string;
  original_username?: string;
  username?: string;
  group_name?: string;
  badge_name?: string;
  badge_slug?: string;
  badge_id?: number;
  count?: number;
}

export interface RawNotification {
  id?: number;
  notification_type?: number;
  read?: boolean;
  high_priority?: boolean;
  created_at?: string;
  post_number?: number;
  topic_id?: number;
  fancy_title?: string;
  slug?: string;
  acting_user_avatar_template?: string;
  acting_user_name?: string;
  data?: RawNotificationData;
}

export interface RawNotificationsResponse {
  notifications?: RawNotification[];
}

// 通知的展示模型:解析时已把类型映射成图标/颜色/文案,行组件直接读取即可。
export interface NotificationItem {
  id: number;
  type: number;
  read: boolean;
  createdAt: string;
  actorName: string;         // 发起人展示名;系统类通知为空串
  actorUsername: string;     // 用于头像首字母兜底
  avatarTemplate?: string;   // 发起人头像模板(交给 UserAvatar 解析)
  actionText: string;        // "回复了你"/"你获得了徽章" 等
  title: string;             // 帖子标题 / 徽章名
  topicId?: number;
  postNumber?: number;
  slug?: string;
  iconId: string;            // FontAwesome 图标 id(角标/系统圈用)
  iconColor: string;         // 角标颜色
}
