import { describe, it, expect } from '@ohos/hypium';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../main/ets/services/challenge/ChallengeEventBus';
import { ChallengeState } from '../main/ets/services/network/NetworkTypes';

export default function challengeEventBusTest() {
  describe('challengeEventBusTest', () => {
    it('notifiesSubscribersWhenChallengeIsRequired', 0, () => {
      let receivedVersion: number = 0;
      let receivedSource: string = '';
      let receivedStatusCode: number = 0;
      let receivedChallengeState: ChallengeState = ChallengeState.NONE;
      const unsubscribe: () => void = ChallengeEventBus.subscribe((event: ChallengeRequiredEvent) => {
        receivedVersion = event.version;
        receivedSource = event.source;
        receivedStatusCode = event.statusCode;
        receivedChallengeState = event.challengeState;
      });

      const version: number = ChallengeEventBus.notifyChallengeRequired('/latest.json', 403, ChallengeState.REQUIRED);
      unsubscribe();

      expect(receivedVersion).assertEqual(version);
      expect(receivedSource).assertEqual('/latest.json');
      expect(receivedStatusCode).assertEqual(403);
      expect(receivedChallengeState).assertEqual(ChallengeState.REQUIRED);
    });
  });
}
