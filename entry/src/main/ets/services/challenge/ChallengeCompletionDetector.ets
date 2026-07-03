import { AppConstants } from '../../common/constants/AppConstants';

export interface ChallengeCompletionResponse {
  url: string;
  statusCode: number;
  isMainFrame: boolean;
  cfMitigatedHeader: string;
}

export function isChallengeCompletionResponse(response: ChallengeCompletionResponse): boolean {
  if (!response.isMainFrame || response.statusCode !== 404) {
    return false;
  }

  if (!isBareChallengeUrl(response.url)) {
    return false;
  }

  return response.cfMitigatedHeader.toLowerCase().indexOf('challenge') < 0;
}

function isBareChallengeUrl(url: string): boolean {
  if (url !== AppConstants.CHALLENGE_URL && url !== `${AppConstants.CHALLENGE_URL}/`) {
    return false;
  }

  return true;
}
