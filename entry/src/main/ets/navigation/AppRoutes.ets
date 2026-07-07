export enum AppRouteName {
  TOPIC_DETAIL = 'topicDetail',
  PROFILE = 'profile',
  WEB = 'web',
  NOTIFICATIONS = 'notifications'
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

export interface NotificationsRouteParam {
  source: string;
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
