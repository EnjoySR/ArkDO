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
  // POST + application/json body(发表评论/回复用),CSRF/cookie 与 postForm 同源自动处理。
  postJson(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>>;
  // PUT + 空 body(表情回应 toggle 用),CSRF/cookie 与 postForm 同源自动处理。
  putJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>>;
  // PUT + application/x-www-form-urlencoded body(投票 PUT /polls/vote 用),CSRF/cookie 同源自动处理。
  putForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>>;
  // DELETE + application/x-www-form-urlencoded body(撤销投票 DELETE /polls/vote 用),CSRF/cookie 同源自动处理。
  deleteForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>>;
  // 上传图片到 /uploads.json(multipart):base64 为压缩后图片字节的 base64,在 host webview 内还原成
  // Blob 拼 FormData 提交(原生 netstack 会被 CF 挡,只有 webview fetch 能过盾并带会话 Cookie)。
  // 返回 /uploads.json 的 JSON 响应文本(含 short_url 短码与真实 url),由上层解析。
  uploadImage(base64: string, fileName: string, mimeType: string, options?: JsonRequestOptions): Promise<NetworkResult<string>>;
}
