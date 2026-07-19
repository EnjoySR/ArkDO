import { ChallengeState, NetworkErrorCode, NetworkResult } from './NetworkTypes';

// NetworkResult 失败态的三个构造器。
//
// 原先这两个函数在 7 个 service 里各复制一份(TopicService/UserProfileService/SiteService/
// UserRelationService/AuthService/BookmarkService/DraftService),且已经开始漂移:
//   - 3 份丢了泛型,把返回类型硬编码成 User|undefined / BookmarkPage / DraftPage;
//   - 1 份把 unexpectedResponse 改名成 unexpected 并换了入参形态。
// 集中到这里后,「失败该长什么样」只有一处定义。

// 把下层(bridge)的失败原样上抛,只换泛型形参。
// 用于「请求本身就没成功」——状态码、挑战态、错误对象全部沿用下层判定,不做二次解释。
export function forwardFailure<T>(response: NetworkResult<string>): NetworkResult<T> {
  return {
    success: false,
    statusCode: response.statusCode,
    challengeState: response.challengeState,
    error: response.error
  };
}

// 请求成功但响应不是预期形态(空 body / 非 JSON / 缺关键字段)。
// requiresChallenge 由挑战态推导:被 CF 拦时返回的往往是 HTML,同样会落到这里,
// 需要让上层区分「服务端结构变了」和「该过盾了」。
export function unexpectedResponse<T>(
  statusCode: number,
  challengeState: ChallengeState,
  message: string
): NetworkResult<T> {
  return {
    success: false,
    statusCode: statusCode,
    challengeState: challengeState,
    error: {
      code: NetworkErrorCode.UNEXPECTED_RESPONSE,
      message: message,
      requiresChallenge: challengeState !== ChallengeState.NONE
    }
  };
}

// unexpectedResponse 的便捷形态:直接从原始响应取状态码与挑战态,省去调用方手动拆包。
export function unexpectedFrom<T>(response: NetworkResult<string>, message: string): NetworkResult<T> {
  return unexpectedResponse<T>(response.statusCode, response.challengeState, message);
}
