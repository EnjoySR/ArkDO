import { ChallengeState } from './NetworkTypes';

const CLOUDFLARE_MARKERS: string[] = [
  'cloudflare',
  'cf-chl',
  'challenge-platform',
  'turnstile',
  'just a moment'
];

export function detectChallenge(statusCode: number, contentType: string, body: string): ChallengeState {
  const normalizedContentType: string = contentType.toLowerCase();
  const normalizedBody: string = body.toLowerCase();
  const isJson: boolean =
    normalizedContentType.indexOf('application/json') >= 0 || looksLikeJson(normalizedBody);

  // 真正的 Cloudflare 校验页永远是 HTML（text/html，状态码 403/503 等），绝不会是合法 JSON。
  // 因此对 2xx + 合法 JSON 的响应直接放行，避免帖子标题里的 "Cloudflare" 等子串被误判成校验。
  if (isJson && statusCode >= 200 && statusCode < 300) {
    return ChallengeState.NONE;
  }

  // 关键字子串匹配只作用于非 JSON（HTML/文本）正文。
  if (!isJson && containsCloudflareMarker(normalizedBody)) {
    return ChallengeState.REQUIRED;
  }

  if (statusCode === 403 || statusCode === 429) {
    return ChallengeState.SUSPECTED;
  }

  if (isHtmlResponse(normalizedContentType, normalizedBody) && !isJson) {
    return ChallengeState.SUSPECTED;
  }

  return ChallengeState.NONE;
}

function containsCloudflareMarker(normalizedBody: string): boolean {
  for (let index: number = 0; index < CLOUDFLARE_MARKERS.length; index++) {
    if (normalizedBody.indexOf(CLOUDFLARE_MARKERS[index]) >= 0) {
      return true;
    }
  }
  return false;
}

function isHtmlResponse(normalizedContentType: string, normalizedBody: string): boolean {
  return normalizedContentType.indexOf('text/html') >= 0 || normalizedBody.indexOf('<html') >= 0;
}

function looksLikeJson(normalizedBody: string): boolean {
  const trimmedBody: string = normalizedBody.trim();
  return trimmedBody.startsWith('{') || trimmedBody.startsWith('[');
}
