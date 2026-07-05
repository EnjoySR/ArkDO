import { describe, it, expect } from '@ohos/hypium';
import { detectChallenge } from '../main/ets/services/network/ChallengeDetector';
import { ChallengeState } from '../main/ets/services/network/NetworkTypes';

export default function challengeDetectorTest() {
  describe('challengeDetectorTest', () => {
    it('returnsSuspectedForForbiddenStatus', 0, () => {
      const state: ChallengeState = detectChallenge(403, 'application/json', '{"error":"forbidden"}');
      expect(state).assertEqual(ChallengeState.SUSPECTED);
    });

    it('returnsSuspectedForTooManyRequests', 0, () => {
      const state: ChallengeState = detectChallenge(429, 'application/json', '{"error":"rate limited"}');
      expect(state).assertEqual(ChallengeState.SUSPECTED);
    });

    it('returnsRequiredForCloudflareHtml', 0, () => {
      const body: string = '<html><title>Just a moment...</title><body>cf-chl challenge-platform</body></html>';
      const state: ChallengeState = detectChallenge(200, 'text/html; charset=utf-8', body);
      expect(state).assertEqual(ChallengeState.REQUIRED);
    });

    it('returnsSuspectedForUnexpectedHtml', 0, () => {
      const body: string = '<html><body>Unexpected HTML</body></html>';
      const state: ChallengeState = detectChallenge(200, 'text/html', body);
      expect(state).assertEqual(ChallengeState.SUSPECTED);
    });

    it('returnsNoneForJsonResponse', 0, () => {
      const state: ChallengeState = detectChallenge(200, 'application/json', '{"topic_list":{"topics":[]}}');
      expect(state).assertEqual(ChallengeState.NONE);
    });

    it('returnsNoneForJsonWithCloudflareInTitle', 0, () => {
      // 回归:合法帖子标题里含 "Cloudflare" 不应被误判为校验(见上拉加载更多误弹 CF 页 bug)。
      const body: string = '{"topic_list":{"topics":[{"id":1,"title":"自建Cloudflare临时邮箱教程 Just a moment turnstile"}]}}';
      const state: ChallengeState = detectChallenge(200, 'application/json; charset=utf-8', body);
      expect(state).assertEqual(ChallengeState.NONE);
    });

    it('returnsNoneForJsonBodyWithoutContentType', 0, () => {
      // 即使 content-type 缺失,body 以 { 开头即视为 JSON,含关键字也不误判。
      const body: string = '[{"title":"cloudflare challenge-platform"}]';
      const state: ChallengeState = detectChallenge(200, '', body);
      expect(state).assertEqual(ChallengeState.NONE);
    });
  });
}
