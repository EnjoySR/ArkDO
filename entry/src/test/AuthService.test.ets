import { describe, it, expect } from '@ohos/hypium';
import { User } from '../main/ets/models/User';
import { AuthService } from '../main/ets/services/auth/AuthService';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';

class FakeBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }
}

export default function authServiceTest() {
  describe('authServiceTest', () => {
    it('loadsCurrentUserFromDiscourseSessionPayload', 0, async () => {
      const payload: string = '{"current_user":{"id":7,"username":"linuxdo_user","name":"Linux.do User","avatar_template":"/user_avatar/linux.do/linuxdo_user/{size}/1_2.png"}}';
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: payload
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(bridge.requestedPath).assertEqual('/session/current.json');
      expect(result.success).assertTrue();
      expect(result.data?.id).assertEqual(7);
      expect(result.data?.username).assertEqual('linuxdo_user');
      expect(result.data?.displayName).assertEqual('Linux.do User');
      expect(result.data?.avatarTemplate).assertEqual('/user_avatar/linux.do/linuxdo_user/{size}/1_2.png');
    });

    it('returnsUndefinedWhenCurrentSessionIsAnonymous', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: '{}'
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(result.success).assertTrue();
      expect(result.data).assertEqual(undefined);
    });

    it('preservesChallengeRequiredResult', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: false,
        statusCode: 403,
        challengeState: ChallengeState.REQUIRED,
        error: {
          code: NetworkErrorCode.CHALLENGE_REQUIRED,
          message: 'Cloudflare challenge required.',
          requiresChallenge: true
        }
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(result.success).assertFalse();
      expect(result.statusCode).assertEqual(403);
      expect(result.challengeState).assertEqual(ChallengeState.REQUIRED);
      expect(result.error?.requiresChallenge).assertTrue();
    });

    it('returnsUnexpectedResponseForInvalidCurrentUserPayload', 0, async () => {
      const bridge: FakeBridge = new FakeBridge({
        success: true,
        statusCode: 200,
        challengeState: ChallengeState.NONE,
        data: '{"current_user":{"id":"7","username":"linuxdo_user"}}'
      });
      const service: AuthService = new AuthService(bridge);

      const result: NetworkResult<User | undefined> = await service.getCurrentUser();

      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual(NetworkErrorCode.UNEXPECTED_RESPONSE);
    });
  });
}
