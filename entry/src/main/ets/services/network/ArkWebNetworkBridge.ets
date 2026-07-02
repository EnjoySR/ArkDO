import { ChallengeState, NetworkErrorCode, NetworkResult } from './NetworkTypes';

export class ArkWebNetworkBridge {
  getJson(path: string): Promise<NetworkResult<string>> {
    const result: NetworkResult<string> = {
      success: false,
      statusCode: 0,
      challengeState: ChallengeState.NONE,
      error: {
        code: NetworkErrorCode.NOT_IMPLEMENTED,
        message: `ArkWeb fetch is not available in phase one. Requested path: ${path}`,
        requiresChallenge: false
      }
    };

    return Promise.resolve(result);
  }
}
