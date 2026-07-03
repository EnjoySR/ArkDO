export enum AppRouteName {
  TOPIC_DETAIL = 'topicDetail'
}

export interface TopicDetailRouteParam {
  topicId: number;
  slug?: string;
  title: string;
}

export function buildTopicDetailRouteParam(topicId: number, slug: string | undefined, title: string): TopicDetailRouteParam {
  return {
    topicId: topicId,
    slug: slug,
    title: title
  };
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
