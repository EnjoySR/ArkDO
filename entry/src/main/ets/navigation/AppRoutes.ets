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
  READ_TOPICS = 'readTopics',
  SITES = 'sites',
  // 他人主页:点任意头像进这里。PROFILE 是「我的」页,与本页无关(那页混着登出/设置/草稿)。
  USER_PROFILE = 'userProfile',
  // 他被采纳为解决方案的回复列表,入口是他人主页统计格里的「解决方案」。
  SOLVED = 'solved',
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

// 站点管理页参数:站点全存在本地 preferences,页面自己读,只留来源标记。
export interface SitesRouteParam {
  source: string;
}

export function buildSitesRouteParam(source: string): SitesRouteParam {
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

// 已读帖子列表参数:/read.json 取的就是当前登录用户,无需用户名,只留来源标记。
export interface ReadTopicsRouteParam {
  source: string;
}

export function buildReadTopicsRouteParam(source: string): ReadTopicsRouteParam {
  return {
    source: source
  };
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

// 他人主页参数:username 是取数的唯一 key(/u/{username}.json 等全按它取)。
// displayName/avatarTemplate 由点击来源(帖子作者、互动圈头像等)顺手透传:
// 资料请求回来前身份区就能先画出名字和头像,避免首屏跳动。缺省则等 detail。
export interface UserProfileRouteParam {
  username: string;
  displayName?: string;
  avatarTemplate?: string;
  // 点击来源的用户 id 一并透传:头像形状按 id 决定(id===1 方形圆角,其余圆形),
  // 种子缺 id 会先以 0 渲染成圆形、detail 回来再变方形,导致 Neo(id=1)头像圆→方闪一下。
  userId?: number;
}

export function buildUserProfileRouteParam(username: string, displayName?: string, avatarTemplate?: string, userId?: number): UserProfileRouteParam {
  return {
    username: username,
    displayName: displayName,
    avatarTemplate: avatarTemplate,
    userId: userId
  };
}

export function isUserProfileRouteParam(param: Object | undefined): boolean {
  if (!param) {
    return false;
  }
  const candidate: UserProfileRouteParam = param as UserProfileRouteParam;
  return typeof candidate.username === 'string' && candidate.username.length > 0;
}

// 解决方案列表参数:目标用户名 + 总数(用于标题「解决方案 · N」,0 表示未知)。
export interface SolvedRouteParam {
  username: string;
  solvedCount: number;
}

export function buildSolvedRouteParam(username: string, solvedCount: number): SolvedRouteParam {
  return {
    username: username,
    solvedCount: solvedCount
  };
}

export function isSolvedRouteParam(param: Object | undefined): boolean {
  if (!param) {
    return false;
  }
  const candidate: SolvedRouteParam = param as SolvedRouteParam;
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
// siteId:从「我的站点」打开时带上,WEB 页据此把引擎交出的 favicon 缓存为该站点图标;
// 帖子外链不带,favicon 直接丢弃(不给随手点开的外链留缓存文件)。
export interface WebRouteParam {
  url: string;
  title?: string;
  siteId?: string;
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

export function buildWebRouteParam(url: string, title?: string, siteId?: string): WebRouteParam {
  return {
    url: url,
    title: title,
    siteId: siteId
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
