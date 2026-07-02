import { describe, it, expect } from '@ohos/hypium';
import { ArkWebNetworkBridge } from '../main/ets/services/network/ArkWebNetworkBridge';
import { ChallengeState, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';

export default function arkWebNetworkBridgeTest() {
  describe('arkWebNetworkBridgeTest', () => {
    it('returnsNotImplementedResultWithoutNetworkAccess', 0, async () => {
      const bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
      const result: NetworkResult<string> = await bridge.getJson('/latest.json');

      expect(result.success).assertFalse();
      expect(result.statusCode).assertEqual(0);
      expect(result.challengeState).assertEqual(ChallengeState.NONE);
      expect(result.error?.code).assertEqual(NetworkErrorCode.NOT_IMPLEMENTED);
      expect(result.error?.requiresChallenge).assertFalse();
    });
  });
}
