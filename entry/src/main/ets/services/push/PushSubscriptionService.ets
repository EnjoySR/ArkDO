import { BusinessError } from '@kit.BasicServicesKit';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][PushSubscription]';

export interface PushTokenProvider {
  getToken(): Promise<string>;
}

export interface PushRelayRegistration {
  subId?: string;
  endpoint: string;
  p256dh: string;
  auth: string;
}

export interface PushRelayUser {
  userId: number;
  username: string;
}

export interface PushRelayClient {
  ensure(deviceToken: string, user: PushRelayUser, existingSubId?: string): Promise<PushRelayRegistration>;
  disable(registration: PushRelayRegistration, user?: PushRelayUser): Promise<void>;
  sendTest(registration: PushRelayRegistration, user: PushRelayUser, deviceToken: string): Promise<void>;
}

export interface PushRegistrationResult {
  success: boolean;
  message: string;
  subId?: string;
  endpoint?: string;
  p256dh?: string;
  auth?: string;
  requiresChallenge?: boolean;
}

export interface PushStatusResult {
  enabled: boolean;
  message: string;
}

// linux.do subscribe 的失败响应体形状(成功时为空体或 {"success":"OK"},无需建模)。
interface SubscribeResponseBody {
  errors?: string[];
  failed?: string;
}

const LINUXDO_SUBSCRIBE_PATH: string = '/push_notifications/subscribe';
const LINUXDO_UNSUBSCRIBE_PATH: string = '/push_notifications/unsubscribe';
const LINUXDO_SUBSCRIBE_REFERRER: string = '/my/preferences/notifications';

export class PushSubscriptionService {
  private bridge: JsonNetworkClient;
  private tokenProvider: PushTokenProvider;
  private relayClient: PushRelayClient;

  constructor(bridge: JsonNetworkClient, tokenProvider: PushTokenProvider, relayClient: PushRelayClient) {
    this.bridge = bridge;
    this.tokenProvider = tokenProvider;
    this.relayClient = relayClient;
  }

  async enable(user: PushRelayUser, existingSubId?: string): Promise<PushRegistrationResult> {
    if (user.userId <= 0 || user.username.length === 0) {
      return { success: false, message: '请先登录 linux.do 账号' };
    }

    Log.i(`${LOG_TAG} enable start`);
    let deviceToken: string = '';
    try {
      Log.i(`${LOG_TAG} getToken start`);
      deviceToken = (await this.tokenProvider.getToken()).trim();
      Log.i(`${LOG_TAG} getToken ok tokenLength=${deviceToken.length}`);
    } catch (err) {
      return this.failure('获取 Push Token 失败', err);
    }
    if (deviceToken.length === 0) {
      Log.i(`${LOG_TAG} getToken empty`);
      return { success: false, message: 'Push Token 为空' };
    }

    let registration: PushRelayRegistration;
    try {
      Log.i(`${LOG_TAG} relay ensure start tokenLength=${deviceToken.length} userId=${user.userId} existing=${existingSubId ?? ''}`);
      registration = await this.relayClient.ensure(deviceToken, user, existingSubId);
      Log.i(`${LOG_TAG} relay register ok endpointLength=${registration.endpoint.length} p256dhLength=${registration.p256dh.length} authLength=${registration.auth.length}`);
    } catch (err) {
      return this.failure('中继注册失败', err);
    }
    if (!this.isValidRelayRegistration(registration)) {
      Log.i(`${LOG_TAG} relay registration invalid endpointLength=${registration.endpoint.length} p256dhLength=${registration.p256dh.length} authLength=${registration.auth.length}`);
      return { success: false, message: '中继订阅参数无效' };
    }

    let response: NetworkResult<string>;
    try {
      Log.i(`${LOG_TAG} linuxdo subscribe start bodyLength=${this.buildSubscribeBody(registration).length}`);
      response = await this.bridge.postForm(
        LINUXDO_SUBSCRIBE_PATH,
        this.buildSubscribeBody(registration),
        {
          notifyChallenge: true,
          referrer: LINUXDO_SUBSCRIBE_REFERRER
        }
      );
      Log.i(`${LOG_TAG} linuxdo subscribe result success=${response.success} status=${response.statusCode} challenge=${response.challengeState}`);
    } catch (err) {
      return this.failure('linux.do 订阅请求异常', err);
    }

    if (!response.success) {
      return {
        success: false,
        message: this.networkFailureMessage(response),
        requiresChallenge: response.error?.requiresChallenge === true
      };
    }

    // HTTP 200 不等于订阅真建上了:登录 cookie 过期时,linux.do 会用 200 回一个登录页 HTML,
    // 只看 response.success 会假成功——本地落盘"已开启"、UI 显示已订阅,服务端却一条订阅都没有,
    // 用户此后永远收不到推送且无从察觉(本仓既有约定:匿名响应同样返回 200,不能据此推断登录态)。
    const bodyFailure: string = this.subscribeBodyFailure(response.data);
    if (bodyFailure.length > 0) {
      Log.i(`${LOG_TAG} linuxdo subscribe rejected by body check: ${bodyFailure}`);
      return {
        success: false,
        message: bodyFailure
      };
    }

    return {
      success: true,
      message: '推送订阅已开启',
      subId: registration.subId,
      endpoint: registration.endpoint,
      p256dh: registration.p256dh,
      auth: registration.auth
    };
  }

  async disable(registration: PushRelayRegistration, user?: PushRelayUser): Promise<PushRegistrationResult> {
    if (!this.isValidRelayRegistration(registration)) {
      return { success: false, message: '中继订阅参数无效' };
    }

    // 顺序刻意是"先中继、后 linux.do",两边的失败模式因此都是安全的:
    //   · 中继失败 → 直接返回失败,两侧都没动,调用方保留本地状态,用户可重试;
    //   · 中继成功但 linux.do 退订失败 → 设备已经收不到推送了(中继不再转发),
    //     且 Discourse 下次投递会撞上中继的 410,自行删掉那条订阅 —— 链路自愈。
    // 反过来(先 linux.do)则会留下"中继上带着 deviceToken 的孤儿记录":Discourse 已经删了
    // 订阅、再也不会投递,那条记录便永远没有触发清理的机会,只能人工去服务器上删。
    try {
      Log.i(`${LOG_TAG} relay disable start subId=${registration.subId ?? ''}`);
      await this.relayClient.disable(registration, user);
      Log.i(`${LOG_TAG} relay disable ok subId=${registration.subId ?? ''}`);
    } catch (err) {
      return this.failure('中继解绑失败', err);
    }

    try {
      Log.i(`${LOG_TAG} linuxdo unsubscribe start endpointLength=${registration.endpoint.length}`);
      const response: NetworkResult<string> = await this.bridge.postForm(
        LINUXDO_UNSUBSCRIBE_PATH,
        this.buildUnsubscribeBody(registration),
        {
          notifyChallenge: true,
          referrer: LINUXDO_SUBSCRIBE_REFERRER
        }
      );
      Log.i(`${LOG_TAG} linuxdo unsubscribe result success=${response.success} status=${response.statusCode} challenge=${response.challengeState}`);
      if (!response.success) {
        // 同样不算失败:中继已停止转发,Discourse 撞 410 后会自行删除订阅。
        Log.i(`${LOG_TAG} linuxdo unsubscribe failed, relay already disabled (self-heals via 410): ${this.networkFailureMessage(response)}`);
      }
    } catch (err) {
      Log.i(`${LOG_TAG} linuxdo unsubscribe exception, relay already disabled (self-heals via 410): ${this.describeError(err)}`);
    }

    return {
      success: true,
      message: '推送订阅已关闭',
      subId: registration.subId,
      endpoint: registration.endpoint
    };
  }

  // 登出前清理:必须赶在 logout 请求之前调用——登出后 ArkWeb 的登录 cookie 就没了,
  // linux.do 那条订阅再也退不掉,本机会继续收到该账号的推送。
  // 与 disable() 的区别:两侧都尽力做,任一侧失败都不阻断登出。中继解绑是安全网——
  // 摘掉 deviceToken 后中继对该 subId 返回 410,Discourse 下次投递时自行删除订阅,链路自愈。
  async disableForLogout(registration: PushRelayRegistration, user?: PushRelayUser): Promise<void> {
    if (!this.isValidRelayRegistration(registration)) {
      return;
    }

    // 与 disable() 同样"先中继、后 linux.do":中继才是真正卡住投递的那一环,
    // 先把它摘掉,即便随后 linux.do 退订失败,设备也已收不到推送,且 Discourse 撞 410 后自愈。
    try {
      await this.relayClient.disable(registration, user);
      Log.i(`${LOG_TAG} logout relay disable ok subId=${registration.subId ?? ''}`);
    } catch (err) {
      Log.i(`${LOG_TAG} logout relay disable failed ${this.describeError(err)}`);
    }

    try {
      // 登出途中不弹 CF 验证:此时用户意图是离开,打断体验且拿不到有意义的重试。
      const response: NetworkResult<string> = await this.bridge.postForm(
        LINUXDO_UNSUBSCRIBE_PATH,
        this.buildUnsubscribeBody(registration),
        {
          notifyChallenge: false,
          referrer: LINUXDO_SUBSCRIBE_REFERRER
        }
      );
      Log.i(`${LOG_TAG} logout unsubscribe linuxdo success=${response.success} status=${response.statusCode}`);
    } catch (err) {
      Log.i(`${LOG_TAG} logout unsubscribe linuxdo failed ${this.describeError(err)}`);
    }
  }

  async sendTest(registration: PushRelayRegistration, user: PushRelayUser): Promise<PushStatusResult> {
    if (user.userId <= 0 || user.username.length === 0) {
      return { enabled: false, message: '请先登录 linux.do 账号' };
    }
    if (!this.isValidRelayRegistration(registration) || (registration.subId ?? '').length === 0) {
      return { enabled: false, message: '推送订阅参数无效' };
    }

    let deviceToken: string = '';
    try {
      Log.i(`${LOG_TAG} relay test getToken start`);
      deviceToken = (await this.tokenProvider.getToken()).trim();
      Log.i(`${LOG_TAG} relay test getToken ok tokenLength=${deviceToken.length}`);
    } catch (err) {
      return {
        enabled: false,
        message: this.failure('获取 Push Token 失败', err).message
      };
    }
    if (deviceToken.length === 0) {
      return { enabled: false, message: 'Push Token 为空' };
    }

    try {
      Log.i(`${LOG_TAG} relay test start subId=${registration.subId ?? ''} userId=${user.userId}`);
      await this.relayClient.sendTest(registration, user, deviceToken);
      Log.i(`${LOG_TAG} relay test ok subId=${registration.subId ?? ''}`);
      return { enabled: true, message: '测试推送已发送' };
    } catch (err) {
      return {
        enabled: false,
        message: this.failure('测试推送发送失败', err).message
      };
    }
  }

  private isValidRelayRegistration(registration: PushRelayRegistration): boolean {
    return registration.endpoint.startsWith('https://') &&
      registration.p256dh.length > 0 &&
      registration.auth.length > 0;
  }

  private buildSubscribeBody(registration: PushRelayRegistration): string {
    return [
      this.formPart('subscription[endpoint]', registration.endpoint),
      this.formPart('subscription[keys][p256dh]', registration.p256dh),
      this.formPart('subscription[keys][auth]', registration.auth),
      this.formPart('send_confirmation', 'false')
    ].join('&');
  }

  private buildUnsubscribeBody(registration: PushRelayRegistration): string {
    return this.formPart('subscription[endpoint]', registration.endpoint);
  }

  private formPart(key: string, value: string): string {
    return `${encodeURIComponent(key)}=${encodeURIComponent(value)}`;
  }

  // 校验 subscribe 的响应体。返回空串表示"没有失败证据、按成功处理"。
  // 取"只在有明确失败证据时才判失败"的口径,而不是强求 success:"OK" 标记——实测 linux.do 的
  // subscribe 会返回 200 且响应体为空,若强求标记会把当前可用的链路误判成失败。
  private subscribeBodyFailure(body: string | undefined): string {
    const text: string = body === undefined ? '' : body.trim();
    if (text.length === 0) {
      // 200 + 空体:Discourse 侧的正常形态之一,无失败证据。
      return '';
    }

    const lowered: string = text.toLowerCase();
    // 登录页/挑战页等 HTML:典型的"掉登录态但仍回 200"。
    if (lowered.indexOf('<html') >= 0 || lowered.indexOf('<!doctype html') >= 0) {
      return 'linux.do 推送订阅失败: 登录态可能已失效,请重新登录后再试';
    }

    // JSON 错误体:Discourse 失败时回 {"errors":[...]} / {"failed":"FAILED"}。
    if (text.startsWith('{')) {
      try {
        const parsed: SubscribeResponseBody = JSON.parse(text) as SubscribeResponseBody;
        if (parsed.errors !== undefined && parsed.errors.length > 0) {
          return `linux.do 推送订阅失败: ${parsed.errors.join('; ')}`;
        }
        if (typeof parsed.failed === 'string' && parsed.failed.length > 0) {
          return `linux.do 推送订阅失败: ${parsed.failed}`;
        }
      } catch (err) {
        // 解析不了的 JSON 不当作失败证据,交给上层按成功处理,避免误伤。
        Log.i(`${LOG_TAG} subscribe body parse failed, treated as success bodyLength=${text.length}`);
      }
    }

    return '';
  }

  private networkFailureMessage(response: NetworkResult<string>): string {
    const parts: string[] = ['linux.do 推送订阅失败'];
    if (response.statusCode > 0) {
      parts.push(`status=${response.statusCode}`);
    }
    if (response.error?.message && response.error.message.length > 0) {
      parts.push(response.error.message);
    }
    return parts.join(' ');
  }

  private failure(stage: string, err: Object): PushRegistrationResult {
    const detail: string = this.describeError(err);
    const message: string = detail.length > 0 ? `${stage}: ${detail}` : stage;
    Log.i(`${LOG_TAG} ${message}`);
    return {
      success: false,
      message: message
    };
  }

  private describeError(err: Object): string {
    const error = err as Error;
    const businessError = err as BusinessError;
    const parts: string[] = [];
    if (businessError.code !== undefined) {
      parts.push(`code=${businessError.code}`);
    }
    if (error.message !== undefined && error.message.length > 0) {
      parts.push(error.message);
    }
    return parts.join(' ');
  }
}
