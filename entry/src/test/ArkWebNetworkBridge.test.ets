import { describe, it, expect } from '@ohos/hypium';
import { ArkWebJsonExecutor, ArkWebNetworkBridge } from '../main/ets/services/network/ArkWebNetworkBridge';
import { ChallengeState, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';
import { ChallengeEventBus, ChallengeRequiredEvent } from '../main/ets/services/challenge/ChallengeEventBus';

class FakeJsonExecutor implements ArkWebJsonExecutor {
  private result: string;
  lastScript: string = '';

  constructor(result: string) {
    this.result = result;
  }

  run(script: string): Promise<string> {
    this.lastScript = script;
    return Promise.resolve(this.result);
  }
}

export default function arkWebNetworkBridgeTest() {
  describe('arkWebNetworkBridgeTest', () => {
    it('returnsNetworkFailureBeforeArkWebHostIsReady', 0, async () => {
      const bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
      const result: NetworkResult<string> = await bridge.getJson('/latest.json');

      expect(result.success).assertFalse();
      expect(result.statusCode).assertEqual(0);
      expect(result.challengeState).assertEqual(ChallengeState.NONE);
      expect(result.error?.code).assertEqual(NetworkErrorCode.NETWORK_FAILURE);
      expect(result.error?.requiresChallenge).assertFalse();
    });

    it('returnsJsonBodyFromArkWebExecutor', 0, async () => {
      const executor: FakeJsonExecutor = new FakeJsonExecutor('{"statusCode":200,"contentType":"application/json","body":"{\\"topic_list\\":{\\"topics\\":[]}}"}');
      const bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
      bridge.setExecutor(executor);

      const result: NetworkResult<string> = await bridge.getJson('/latest.json');

      expect(executor.lastScript).assertContain('/latest.json');
      expect(result.success).assertTrue();
      expect(result.statusCode).assertEqual(200);
      expect(result.challengeState).assertEqual(ChallengeState.NONE);
      expect(result.data).assertEqual('{"topic_list":{"topics":[]}}');
    });

    it('returnsChallengeRequiredForCloudflareHtml', 0, async () => {
      const executor: FakeJsonExecutor = new FakeJsonExecutor('{"statusCode":403,"contentType":"text/html","body":"<html><title>Just a moment...</title><body>cf-chl</body></html>"}');
      const bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
      bridge.setExecutor(executor);

      const result: NetworkResult<string> = await bridge.getJson('/latest.json');

      expect(result.success).assertFalse();
      expect(result.statusCode).assertEqual(403);
      expect(result.challengeState).assertEqual(ChallengeState.REQUIRED);
      expect(result.error?.code).assertEqual(NetworkErrorCode.CHALLENGE_REQUIRED);
      expect(result.error?.requiresChallenge).assertTrue();
    });

    it('publishesChallengeEventForCloudflareHtml', 0, async () => {
      const executor: FakeJsonExecutor = new FakeJsonExecutor('{"statusCode":403,"contentType":"text/html","body":"<html><title>Just a moment...</title><body>cf-chl</body></html>"}');
      const bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
      let receivedSource: string = '';
      let receivedStatusCode: number = 0;
      let receivedChallengeState: ChallengeState = ChallengeState.NONE;
      const unsubscribe: () => void = ChallengeEventBus.subscribe((event: ChallengeRequiredEvent) => {
        receivedSource = event.source;
        receivedStatusCode = event.statusCode;
        receivedChallengeState = event.challengeState;
      });
      bridge.setExecutor(executor);

      await bridge.getJson('/latest.json');
      unsubscribe();

      expect(receivedSource).assertEqual('/latest.json');
      expect(receivedStatusCode).assertEqual(403);
      expect(receivedChallengeState).assertEqual(ChallengeState.REQUIRED);
    });

    it('canSuppressChallengeEventForInternalProbe', 0, async () => {
      const executor: FakeJsonExecutor = new FakeJsonExecutor('{"statusCode":403,"contentType":"text/html","body":"<html><title>Just a moment...</title><body>cf-chl</body></html>"}');
      const bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
      let receivedSource: string = '';
      const unsubscribe: () => void = ChallengeEventBus.subscribe((event: ChallengeRequiredEvent) => {
        receivedSource = event.source;
      });
      bridge.setExecutor(executor);

      await bridge.getJson('/latest.json', { notifyChallenge: false });
      unsubscribe();

      expect(receivedSource).assertEqual('');
    });
  });
}
