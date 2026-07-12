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
  // 用 startsWith 而非严格等于:CF Managed Challenge 过盾成功后回跳的 URL 会带查询参数
  // (如 /challenge?__cf_chl_rt_tk=...),严格等于会漏掉这类"真过盾后的 404",导致过盾页不自动关。
  return url.startsWith(AppConstants.CHALLENGE_URL);
}
