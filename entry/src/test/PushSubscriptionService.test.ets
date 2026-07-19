import { describe, it, expect } from '@ohos/hypium';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';
import {
  PushRelayClient,
  PushRelayRegistration,
  PushRelayUser,
  PushRegistrationResult,
  PushStatusResult,
  PushSubscriptionService,
  PushTokenProvider
} from '../main/ets/services/push/PushSubscriptionService';
import { buildPushTokenDebugLogLine, isDebugBuildInfo, maskPushToken } from '../main/ets/services/push/PushTokenDebugLog';
import { nextPushRefreshStart } from '../main/ets/services/push/PushRefreshGate';

class FakePushTokenProvider implements PushTokenProvider {
  private token: string;

  constructor(token: string) {
    this.token = token;
  }

  getToken(): Promise<string> {
    return Promise.resolve(this.token);
  }
}

class ThrowingPushTokenProvider implements PushTokenProvider {
  getToken(): Promise<string> {
    return Promise.reject({
      code: 1001,
      message: 'token unavailable'
    });
  }
}

class FakeRelayClient implements PushRelayClient {
  requestedToken: string = '';
  requestedUserId: number = 0;
  requestedUsername: string = '';
  requestedExistingSubId: string = '';
  disabledSubId: string = '';
  disabledEndpoint: string = '';
  sentTestSubId: string = '';
  sentTestUserId: number = 0;
  sentTestUsername: string = '';
  sentTestToken: string = '';
  private registration: PushRelayRegistration;

  constructor(registration: PushRelayRegistration) {
    this.registration = registration;
  }

  ensure(deviceToken: string, user: PushRelayUser, existingSubId?: string): Promise<PushRelayRegistration> {
    this.requestedToken = deviceToken;
    this.requestedUserId = user.userId;
    this.requestedUsername = user.username;
    this.requestedExistingSubId = existingSubId ?? '';
    return Promise.resolve(this.registration);
  }

  // 非空时 disable 抛错,用于验证"中继解绑失败要整体失败、且不再动 linux.do"。
  disableError: string = '';

  disable(registration: PushRelayRegistration): Promise<void> {
    this.disabledSubId = registration.subId ?? '';
    this.disabledEndpoint = registration.endpoint;
    if (this.disableError.length > 0) {
      return Promise.reject(new Error(this.disableError));
    }
    return Promise.resolve();
  }

  sendTest(registration: PushRelayRegistration, user: PushRelayUser, deviceToken: string): Promise<void> {
    this.sentTestSubId = registration.subId ?? '';
    this.sentTestUserId = user.userId;
    this.sentTestUsername = user.username;
    this.sentTestToken = deviceToken;
    return Promise.resolve();
  }
}

class ThrowingRelayClient implements PushRelayClient {
  requestedToken: string = '';

  ensure(deviceToken: string): Promise<PushRelayRegistration> {
    this.requestedToken = deviceToken;
    return Promise.reject(new Error('relay http 503'));
  }

  disable(): Promise<void> {
    return Promise.resolve();
  }

  sendTest(): Promise<void> {
    return Promise.resolve();
  }
}

class FakeBridge implements JsonNetworkClient {
  requestedPath: string = '';
  requestedBody: string = '';
  private result: NetworkResult<string>;

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedBody = body;
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedBody = body;
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedBody = body;
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    this.requestedBody = body;
    return Promise.resolve(this.result);
  }

  uploadImage(_base64: string, _fileName: string, _mimeType: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }
}

function successText(data: string): NetworkResult<string> {
  return {
    success: true,
    statusCode: 200,
    challengeState: ChallengeState.NONE,
    data: data
  };
}

export default function pushSubscriptionServiceTest() {
  describe('pushSubscriptionServiceTest', () => {
    it('buildsPushTokenDebugLogOnlyWhenEnabled', 0, () => {
      expect(buildPushTokenDebugLogLine('[ArkDO][HarmonyPush]', 'token-123', false)).assertEqual('');
      // 短 token 脱敏后只剩长度,不泄内容。
      expect(buildPushTokenDebugLogLine('[ArkDO][HarmonyPush]', 'token-123', true)).assertEqual('[ArkDO][HarmonyPush] token=<len=9>');
    });

    // 日志会落盘且可导出,完整 deviceToken 等同于可向本机投递推送的凭据,绝不能整条进日志。
    it('masksPushTokenInDebugLog', 0, () => {
      const token: string = 'ABCDEF0123456789abcdefXYZ789';
      const masked: string = maskPushToken(token);

      expect(masked).assertEqual('ABCDEF…XYZ789(len=28)');
      expect(masked.indexOf(token) < 0).assertTrue();
      expect(buildPushTokenDebugLogLine('[ArkDO][HarmonyPush]', token, true).indexOf(token) < 0).assertTrue();
    });

    it('logsPushTokenOnlyForDebugBuilds', 0, () => {
      expect(isDebugBuildInfo('debug', false)).assertTrue();
      expect(isDebugBuildInfo('release', true)).assertTrue();
      expect(isDebugBuildInfo('release', false)).assertFalse();
    });

    it('doesNotAdvancePushRefreshSequenceWhenRefreshIsAlreadyRunning', 0, () => {
      const running = nextPushRefreshStart(7, true);
      expect(running.shouldStart).assertFalse();
      expect(running.sequence).assertEqual(7);

      const idle = nextPushRefreshStart(7, false);
      expect(idle.shouldStart).assertTrue();
      expect(idle.sequence).assertEqual(8);
    });

    it('registersRelaySubscriptionWithLinuxDo', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const bridge: FakeBridge = new FakeBridge(successText('{"success":"OK"}'));
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.enable({ userId: 42, username: 'joey' }, 'old-sub');

      expect(result.success).assertTrue();
      expect(result.subId).assertEqual('sub123');
      expect(result.endpoint).assertEqual('https://relay.example.test/wp/sub123');
      expect(relay.requestedToken).assertEqual('device-token-1');
      expect(relay.requestedUserId).assertEqual(42);
      expect(relay.requestedUsername).assertEqual('joey');
      expect(relay.requestedExistingSubId).assertEqual('old-sub');
      expect(bridge.requestedPath).assertEqual('/push_notifications/subscribe');
      expect(bridge.requestedBody).assertContain('subscription%5Bendpoint%5D=https%3A%2F%2Frelay.example.test%2Fwp%2Fsub123');
      expect(bridge.requestedBody).assertContain('subscription%5Bkeys%5D%5Bp256dh%5D=public-key');
      expect(bridge.requestedBody).assertContain('subscription%5Bkeys%5D%5Bauth%5D=auth-secret');
      expect(bridge.requestedBody).assertContain('send_confirmation=false');
    });

    // 掉登录态时 linux.do 会用 200 回一个登录页 HTML,只看 HTTP 状态会假成功。
    it('failsWhenSubscribeReturnsLoginPageHtml', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const bridge: FakeBridge = new FakeBridge(successText('<!DOCTYPE html><html lang="zh-CN"><body>登录</body></html>'));
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.enable({ userId: 42, username: 'joey' });

      expect(result.success).assertFalse();
      expect(result.message).assertContain('登录态');
    });

    // 服务端 JSON 错误体也要判失败,并把原因带给用户。
    it('failsWhenSubscribeReturnsJsonErrors', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const bridge: FakeBridge = new FakeBridge(successText('{"errors":["订阅参数无效"]}'));
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.enable({ userId: 42, username: 'joey' });

      expect(result.success).assertFalse();
      expect(result.message).assertContain('订阅参数无效');
    });

    // 实测 linux.do 的 subscribe 会返回 200 + 空体,这条必须仍算成功,否则可用链路会被误判。
    it('treatsEmptySubscribeBodyAsSuccess', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const bridge: FakeBridge = new FakeBridge(successText(''));
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.enable({ userId: 42, username: 'joey' });

      expect(result.success).assertTrue();
      expect(result.endpoint).assertEqual('https://relay.example.test/wp/sub123');
    });

    it('doesNotSubscribeWhenRelayResponseIsInvalid', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        endpoint: '',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const bridge: FakeBridge = new FakeBridge(successText('{"success":"OK"}'));
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.enable({ userId: 42, username: 'joey' });

      expect(result.success).assertFalse();
      expect(result.message).assertEqual('中继订阅参数无效');
      expect(bridge.requestedPath).assertEqual('');
    });

    it('returnsFailureWhenLinuxDoSubscribeFails', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
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
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.enable({ userId: 42, username: 'joey' });

      expect(result.success).assertFalse();
      // 失败消息会带上诊断信息(status=403 + 服务端原因),故只断言包含前缀,不锁死拼接格式。
      expect(result.message).assertContain('linux.do 推送订阅失败');
      expect(result.message).assertContain('403');
      expect(result.requiresChallenge).assertTrue();
    });

    it('returnsTokenProviderErrorDetails', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(successText('{"success":"OK"}'));
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new ThrowingPushTokenProvider(),
        relay
      );

      const result: PushRegistrationResult = await service.enable({ userId: 42, username: 'joey' });

      expect(result.success).assertFalse();
      expect(result.message).assertContain('获取 Push Token 失败');
      expect(result.message).assertContain('1001');
      expect(bridge.requestedPath).assertEqual('');
    });

    it('returnsRelayRegistrationErrorDetails', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(successText('{"success":"OK"}'));
      const relay: ThrowingRelayClient = new ThrowingRelayClient();
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.enable({ userId: 42, username: 'joey' });

      expect(result.success).assertFalse();
      expect(result.message).assertContain('中继注册失败');
      expect(result.message).assertContain('relay http 503');
      expect(relay.requestedToken).assertEqual('device-token-1');
      expect(bridge.requestedPath).assertEqual('');
    });

    // 关闭订阅刻意是"先中继、后 linux.do"。中继解绑失败必须整体失败、且不去动 linux.do:
    // 否则 Discourse 先删了订阅就再也不会投递,中继上那条带 deviceToken 的记录便永远
    // 等不到 410 清理,沦为只能人工删的孤儿。改动此顺序前请先想清楚这一点。
    it('failsAndSkipsLinuxDoWhenRelayDisableFails', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      relay.disableError = 'relay unreachable';
      const bridge: FakeBridge = new FakeBridge(successText('{"success":"OK"}'));
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.disable({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });

      expect(result.success).assertFalse();
      expect(result.message).assertContain('中继解绑失败');
      // 关键:linux.do 一步都没走,订阅仍在服务端,用户可原样重试。
      expect(bridge.requestedPath).assertEqual('');
    });

    // 反向失败是安全的:中继已停止转发,设备收不到推送;Discourse 下次投递撞 410 自行删订阅。
    it('succeedsWhenRelayDisabledButLinuxDoUnsubscribeFails', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const bridge: FakeBridge = new FakeBridge({
        success: false,
        statusCode: 500,
        challengeState: ChallengeState.NONE
      });
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.disable({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });

      expect(result.success).assertTrue();
      expect(relay.disabledSubId).assertEqual('sub123');
    });

    it('unsubscribesLinuxDoAndDisablesRelayRecord', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const bridge: FakeBridge = new FakeBridge(successText('{"success":"OK"}'));
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushRegistrationResult = await service.disable({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });

      expect(result.success).assertTrue();
      expect(result.message).assertEqual('推送订阅已关闭');
      expect(bridge.requestedPath).assertEqual('/push_notifications/unsubscribe');
      expect(bridge.requestedBody).assertContain('subscription%5Bendpoint%5D=https%3A%2F%2Frelay.example.test%2Fwp%2Fsub123');
      expect(relay.disabledSubId).assertEqual('sub123');
      expect(relay.disabledEndpoint).assertEqual('https://relay.example.test/wp/sub123');
    });

    it('sendsTestPushThroughRelayForExistingSubscription', 0, async () => {
      const relay: FakeRelayClient = new FakeRelayClient({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      });
      const bridge: FakeBridge = new FakeBridge(successText('{"success":"OK"}'));
      const service: PushSubscriptionService = new PushSubscriptionService(
        bridge,
        new FakePushTokenProvider('device-token-1'),
        relay
      );

      const result: PushStatusResult = await service.sendTest({
        subId: 'sub123',
        endpoint: 'https://relay.example.test/wp/sub123',
        p256dh: 'public-key',
        auth: 'auth-secret'
      }, { userId: 42, username: 'joey' });

      expect(result.enabled).assertTrue();
      expect(result.message).assertEqual('测试推送已发送');
      expect(relay.sentTestSubId).assertEqual('sub123');
      expect(relay.sentTestUserId).assertEqual(42);
      expect(relay.sentTestUsername).assertEqual('joey');
      expect(relay.sentTestToken).assertEqual('device-token-1');
      expect(bridge.requestedPath).assertEqual('');
    });
  });
}
