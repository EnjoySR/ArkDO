export enum AppRouteName {
  TOPIC_DETAIL = 'topicDetail',
  PROFILE = 'profile',
  SETTINGS = 'settings',
  DOH_SETTINGS = 'dohSettings',
  LEVEL_PROGRESS = 'levelProgress',
  WEB = 'web',
  NOTIFICATIONS = 'notifications',
  BOOKMARKS = 'bookmarks',
  ACTIVITY = 'activity',
  BADGES = 'badges',
  // 双栏(平板横屏)下右详情栏的空占位:未选帖子时垫在栈底,让右栏不空白。仅宽屏使用。
  PLACEHOLDER = 'placeholder'
}

export interface TopicDetailRouteParam {
  topicId: number;
  slug?: string;
  title: string;
  // 目标楼号:未读徽标/通知/引用跳转的定位锚,详情页以该楼为窗口中心加载。缺省从头加载。
  targetPostNumber?: number;
  // 落地后是否短暂高亮目标楼:通知跳转 true(对齐官网 anchor 高亮);未读徽标跳转 false(只有红线)。
  highlightTarget?: boolean;
}

export interface ProfileRouteParam {
  source: string;
}

export interface SettingsRouteParam {
  source: string;
}

export function buildSettingsRouteParam(source: string): SettingsRouteParam {
  return {
    source: source
  };
}

export interface DohSettingsRouteParam {
  source: string;
}

export function buildDohSettingsRouteParam(source: string): DohSettingsRouteParam {
  return {
    source: source
  };
}

export interface LevelProgressRouteParam {
  isLoggedIn: boolean;
}

export function buildLevelProgressRouteParam(isLoggedIn: boolean): LevelProgressRouteParam {
  return {
    isLoggedIn: isLoggedIn
  };
}

export interface NotificationsRouteParam {
  source: string;
}

export interface BookmarksRouteParam {
  username: string;
}

export function buildBookmarksRouteParam(username: string): BookmarksRouteParam {
  return {
    username: username
  };
}

export function isBookmarksRouteParam(param: Object | undefined): boolean {
  if (!param) {
    return false;
  }
  const candidate: BookmarksRouteParam = param as BookmarksRouteParam;
  return typeof candidate.username === 'string' && candidate.username.length > 0;
}

// 全部徽章页参数:目标用户名 + 徽章总数(用于标题「徽章 · N」,0 表示未知)。
export interface BadgesRouteParam {
  username: string;
  badgeCount: number;
}

export function buildBadgesRouteParam(username: string, badgeCount: number): BadgesRouteParam {
  return {
    username: username,
    badgeCount: badgeCount
  };
}

export function isBadgesRouteParam(param: Object | undefined): boolean {
  if (!param) {
    return false;
  }
  const candidate: BadgesRouteParam = param as BadgesRouteParam;
  return typeof candidate.username === 'string' && candidate.username.length > 0;
}

// 用户动态列表参数:filter 见 UserActionType(4=话题 5=回复 1=点赞,可逗号组合)。
export interface ActivityRouteParam {
  username: string;
  filter: string;
  title: string;
}

export function buildActivityRouteParam(username: string, filter: string, title: string): ActivityRouteParam {
  return {
    username: username,
    filter: filter,
    title: title
  };
}

export function isActivityRouteParam(param: Object | undefined): boolean {
  if (!param) {
    return false;
  }
  const candidate: ActivityRouteParam = param as ActivityRouteParam;
  return typeof candidate.username === 'string' && candidate.username.length > 0 &&
    typeof candidate.filter === 'string' && candidate.filter.length > 0 &&
    typeof candidate.title === 'string';
}

export function buildNotificationsRouteParam(source: string): NotificationsRouteParam {
  return {
    source: source
  };
}

// 通用 WebView 页参数:要打开的 URL 与可选标题(缺省时页面用域名兜底)。
export interface WebRouteParam {
  url: string;
  title?: string;
}

export function buildTopicDetailRouteParam(topicId: number, slug: string | undefined, title: string, targetPostNumber?: number, highlightTarget?: boolean): TopicDetailRouteParam {
  return {
    topicId: topicId,
    slug: slug,
    title: title,
    targetPostNumber: targetPostNumber,
    highlightTarget: highlightTarget
  };
}

export function buildProfileRouteParam(source: string): ProfileRouteParam {
  return {
    source: source
  };
}

export function buildWebRouteParam(url: string, title?: string): WebRouteParam {
  return {
    url: url,
    title: title
  };
}

export function isWebRouteParam(param: Object | undefined): boolean {
  if (!param) {
    return false;
  }

  const candidate: WebRouteParam = param as WebRouteParam;
  return typeof candidate.url === 'string' && candidate.url.length > 0 &&
    (candidate.title === undefined || typeof candidate.title === 'string');
}

export function isTopicDetailRouteParam(param: Object | undefined): boolean {
  if (!param) {
    return false;
  }

  const candidate: TopicDetailRouteParam = param as TopicDetailRouteParam;
  return typeof candidate.topicId === 'number' &&
    typeof candidate.title === 'string' &&
    (candidate.slug === undefined || typeof candidate.slug === 'string') &&
    (candidate.targetPostNumber === undefined || typeof candidate.targetPostNumber === 'number');
}
