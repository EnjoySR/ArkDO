export enum ChallengeState {
  NONE = 'none',
  SUSPECTED = 'suspected',
  REQUIRED = 'required'
}

export enum NetworkErrorCode {
  NOT_IMPLEMENTED = 'not_implemented',
  CHALLENGE_REQUIRED = 'challenge_required',
  UNEXPECTED_RESPONSE = 'unexpected_response',
  NETWORK_FAILURE = 'network_failure'
}

export interface NetworkError {
  code: NetworkErrorCode;
  message: string;
  requiresChallenge: boolean;
}

export interface NetworkResult<T> {
  success: boolean;
  statusCode: number;
  challengeState: ChallengeState;
  data?: T;
  error?: NetworkError;
}
