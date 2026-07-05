import { describe, it, expect } from '@ohos/hypium';
import { ChallengeState, JsonNetworkClient, JsonRequestOptions, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';
import { ChallengeResolutionProbe } from '../main/ets/services/challenge/ChallengeResolutionProbe';

class FakeProbeClient implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';
  notifyChallenge?: boolean = undefined;

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.notifyChallenge = options?.notifyChallenge;
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.notifyChallenge = options?.notifyChallenge;
    return Promise.resolve(this.result);
  }

  putJson(path: string, options?: JsonRequestOptions): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.notifyChallenge = options?.notifyChallenge;
    return Promise.resolve(this.result);
  }
}

export default function challengeResolutionProbeTest() {
  describe('challengeResolutionProbeTest', () => {
    it('resolvesWhenLatestJsonIsAccessible', 0, async () => {
      const client: FakeProbeClient = new FakeProbeClient({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: '{"topic_list":{"topics":[]}}'
      });
      const probe: ChallengeResolutionProbe = new ChallengeResolutionProbe(client);

      const resolved: boolean = await probe.canAccessLatestJson();

      expect(client.requestedPath).assertEqual('/latest.json');
      expect(client.notifyChallenge).assertFalse();
      expect(resolved).assertTrue();
    });

    it('doesNotResolveForChallengeOrUnexpectedPayload', 0, async () => {
      const challengeClient: FakeProbeClient = new FakeProbeClient({
        success: false,
        statusCode: 403,
        challengeState: ChallengeState.REQUIRED,
        error: {
          code: NetworkErrorCode.CHALLENGE_REQUIRED,
          message: 'Challenge required.',
          requiresChallenge: true
        }
      });
      const badPayloadClient: FakeProbeClient = new FakeProbeClient({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: '<html></html>'
      });

      expect(await new ChallengeResolutionProbe(challengeClient).canAccessLatestJson()).assertFalse();
      expect(await new ChallengeResolutionProbe(badPayloadClient).canAccessLatestJson()).assertFalse();
    });
  });
}
