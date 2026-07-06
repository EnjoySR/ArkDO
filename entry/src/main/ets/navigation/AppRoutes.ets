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

export function buildTopicDetailRouteParam(topicId: number, slug: string | undefined, title: string): TopicDetailRouteParam {
  return {
    topicId: topicId,
    slug: slug,
    title: title
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
    (candidate.slug === undefined || typeof candidate.slug === 'string');
}
