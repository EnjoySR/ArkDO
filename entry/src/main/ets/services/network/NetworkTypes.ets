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

export interface JsonRequestOptions {
  notifyChallenge?: boolean;
  // POST 专用:把请求的 Referer 设成同源的某个页面(如帖子页),让请求更像浏览器真实发出的。
  referrer?: string;
}

export interface JsonNetworkClient {
  getJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>>;
  postForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>>;
  // PUT + 空 body(表情回应 toggle 用),CSRF/cookie 与 postForm 同源自动处理。
  putJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>>;
}
