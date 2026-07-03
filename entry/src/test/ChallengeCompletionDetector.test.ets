import { describe, it, expect } from '@ohos/hypium';
import { isChallengeCompletionResponse } from '../main/ets/services/challenge/ChallengeCompletionDetector';

export default function challengeCompletionDetectorTest() {
  describe('challengeCompletionDetectorTest', () => {
    it('resolvesWhenChallengeMainFrameReturnsOrigin404', 0, () => {
      expect(isChallengeCompletionResponse({
        url: 'https://linux.do/challenge',
        statusCode: 404,
        isMainFrame: true,
        cfMitigatedHeader: ''
      })).assertTrue();
    });

    it('doesNotResolveWhenResponseIsStillCloudflareChallenge', 0, () => {
      expect(isChallengeCompletionResponse({
        url: 'https://linux.do/challenge',
        statusCode: 404,
        isMainFrame: true,
        cfMitigatedHeader: 'challenge'
      })).assertFalse();
    });

    it('doesNotResolveForSubresourceOrOtherUrls', 0, () => {
      expect(isChallengeCompletionResponse({
        url: 'https://linux.do/challenge',
        statusCode: 404,
        isMainFrame: false,
        cfMitigatedHeader: ''
      })).assertFalse();
      expect(isChallengeCompletionResponse({
        url: 'https://linux.do/t/123',
        statusCode: 404,
        isMainFrame: true,
        cfMitigatedHeader: ''
      })).assertFalse();
    });
  });
}
