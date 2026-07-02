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

  if (containsCloudflareMarker(normalizedBody)) {
    return ChallengeState.REQUIRED;
  }

  if (statusCode === 403 || statusCode === 429) {
    return ChallengeState.SUSPECTED;
  }

  if (isHtmlResponse(normalizedContentType, normalizedBody) && !looksLikeJson(normalizedBody)) {
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
