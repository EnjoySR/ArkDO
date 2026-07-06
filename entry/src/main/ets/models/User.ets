export interface User {
  id: number;
  username: string;
  displayName?: string;
  avatarTemplate?: string;
  animatedAvatar?: string;
  // 来自 /session/current.json 的 current_user:头像未读徽标用。
  // unreadNotifications=常规未读(蓝点数字);unreadHighPriorityNotifications=高优先级(私信等)。
  unreadNotifications?: number;
  unreadHighPriorityNotifications?: number;
}
