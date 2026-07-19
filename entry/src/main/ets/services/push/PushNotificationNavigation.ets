import { AppConstants } from '../../common/constants/AppConstants';

export const ARKDO_PUSH_URL_KEY: string = 'arkdo_url';
export const ARKDO_PUSH_TITLE_KEY: string = 'arkdo_title';
export const ARKDO_PUSH_DATA_KEY: string = 'arkdo_push_data';

export interface PushNotificationRoute {
  id: number;
  url: string;
  title?: string;
  source: string;
  createdAt: number;
}

interface DiscoursePushPayload {
  title?: string;
  url?: string;
  base_url?: string;
}

interface PushClickParameters {
  arkdo_url?: string;
  arkdo_title?: string;
  arkdo_push_data?: string | Object;
  url?: string;
  title?: string;
  data?: string | Object;
  pushData?: string | Object;
  notificationData?: string | Object;
}

interface PushClickData {
  arkdo_url?: string;
  arkdo_title?: string;
  url?: string;
  title?: string;
}

let routeSequence: number = 0;

export function buildPushClickData(url: string, title?: string): string {
  const data: PushClickData = {
    arkdo_url: url
  };
  if (title && title.length > 0) {
    data.arkdo_title = title;
  }
  return JSON.stringify(data);
}

export function extractRouteFromDiscoursePayload(payload: Object | undefined): PushNotificationRoute | undefined {
  if (!payload) {
    return undefined;
  }
  const data: DiscoursePushPayload = payload as DiscoursePushPayload;
  if (typeof data.url !== 'string' || data.url.length === 0) {
    return undefined;
  }
  return buildRoute(data.url, typeof data.title === 'string' ? data.title : undefined, data.base_url, 'discourse');
}

export function parsePushNotificationRouteFromParameters(parameters: Object | undefined): PushNotificationRoute | undefined {
  if (!parameters) {
    return undefined;
  }
  const source: PushClickParameters = parameters as PushClickParameters;
  const direct: PushNotificationRoute | undefined = buildRoute(
    firstNonEmpty(source.arkdo_url, source.url),
    firstNonEmpty(source.arkdo_title, source.title),
    undefined,
    'want'
  );
  if (direct) {
    return direct;
  }

  return parseClickData(source.arkdo_push_data) ??
    parseClickData(source.data) ??
    parseClickData(source.pushData) ??
    parseClickData(source.notificationData);
}

export function resolveDiscoursePushUrl(rawUrl: string | undefined, baseUrl?: string): string {
  const raw: string = rawUrl ? rawUrl.trim() : '';
  if (raw.length === 0) {
    return '';
  }
  if (raw.startsWith('/')) {
    const base: string = sameHostBase(baseUrl) ? (baseUrl as string).replace(/\/+$/, '') : AppConstants.BASE_URL;
    return `${base}${raw}`;
  }
  if (/^https?:\/\//i.test(raw)) {
    return sameHostBase(raw) ? raw : '';
  }
  return '';
}

export function describePushNotificationRoute(route: PushNotificationRoute): string {
  return route.url.replace(/^https?:\/\/[^\/?#]+/i, '').replace(/[?#].*$/, '');
}

function parseClickData(value: string | Object | undefined): PushNotificationRoute | undefined {
  if (!value) {
    return undefined;
  }

  if (typeof value === 'string') {
    if (value.length === 0) {
      return undefined;
    }
    try {
      const parsed: PushClickData = JSON.parse(value) as PushClickData;
      return routeFromClickData(parsed);
    } catch (err) {
      return buildRoute(value, undefined, undefined, 'want-data');
    }
  }

  return routeFromClickData(value as PushClickData);
}

function routeFromClickData(data: PushClickData): PushNotificationRoute | undefined {
  return buildRoute(
    firstNonEmpty(data.arkdo_url, data.url),
    firstNonEmpty(data.arkdo_title, data.title),
    undefined,
    'want-data'
  );
}

function buildRoute(rawUrl: string | undefined, title: string | undefined, baseUrl: string | undefined, source: string): PushNotificationRoute | undefined {
  const url: string = resolveDiscoursePushUrl(rawUrl, baseUrl);
  if (url.length === 0) {
    return undefined;
  }
  routeSequence++;
  const route: PushNotificationRoute = {
    id: routeSequence,
    url: url,
    source: source,
    createdAt: Date.now()
  };
  const cleanTitle: string = title ? title.trim() : '';
  if (cleanTitle.length > 0) {
    route.title = cleanTitle;
  }
  return route;
}

function firstNonEmpty(first?: string, second?: string): string | undefined {
  const a: string = first ? first.trim() : '';
  if (a.length > 0) {
    return a;
  }
  const b: string = second ? second.trim() : '';
  return b.length > 0 ? b : undefined;
}

function sameHostBase(url: string | undefined): boolean {
  if (!url || url.length === 0) {
    return false;
  }
  return hostOf(url) === hostOf(AppConstants.BASE_URL);
}

function hostOf(url: string): string {
  const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/?#]+)/i);
  return match ? match[1].toLowerCase() : '';
}
