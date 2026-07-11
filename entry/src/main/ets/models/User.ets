export interface User {
  id: number;
  username: string;
  displayName?: string;
  avatarTemplate?: string;
  animatedAvatar?: string;
  // 头像右下角角标(flair):flairUrl 要么是 FontAwesome 图标名(如 "gem"),要么是一张图片 URL(gif/png)。
  // 图标形态用 flairBgColor 作底色圆、flairColor 作图标色;图片形态直接显示图。flairName 是组名(g-premium 等)。
  flairUrl?: string;
  flairBgColor?: string;
  flairColor?: string;
  flairName?: string;
  // 来自 /session/current.json 的 current_user:头像未读徽标用。
  // unreadNotifications=常规未读(蓝点数字);unreadHighPriorityNotifications=高优先级(私信等)。
  unreadNotifications?: number;
  unreadHighPriorityNotifications?: number;
  // 未发出的草稿数(current_user.draft_count),个人中心草稿角标用。
  draftCount?: number;
}
