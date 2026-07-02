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
  });
}
