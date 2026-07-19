import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { Log } from '../logging/Log';
import { PushRelayClient, PushRelayRegistration, PushRelayUser } from './PushSubscriptionService';

const LOG_TAG: string = '[ArkDO][PushRelay]';
const REQUEST_TIMEOUT_MS: number = 8000;
// 中继鉴权头。密钥随包分发、可被反编译取出,只用于挡掉扫描器与脚本化滥用,
// 真正的防线是中继侧的限流与容量上限,不能当作身份认证。
const RELAY_API_KEY_HEADER: string = 'X-ArkDO-Key';

interface RelayRegisterResponse {
  subId?: string;
  endpoint?: string;
  p256dh?: string;
  auth?: string;
}

interface RelayEnsureRequest {
  device_token: string;
  user_id: number;
  username: string;
  sub_id: string;
}

interface RelayDisableRequest {
  sub_id: string;
  endpoint: string;
  user_id: number;
  username: string;
}

// 中继在测试推送冷却期内返回的响应体。
interface RelayCooldownResponse {
  error?: string;
  retryAfter?: number;
}

interface RelayTestRequest {
  device_token: string;
  sub_id: string;
  endpoint: string;
  user_id: number;
  username: string;
}

export class HttpPushRelayClient implements PushRelayClient {
  private baseUrl: string;
  private apiKey: string;

  // 地址与密钥一律由调用方注入(来自随包的 relay-config.json 或用户自填),
  // 源码里不留任何真实部署信息——本仓库开源,中继地址与密钥属于部署配置。
  constructor(baseUrl: string, apiKey: string = '') {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.apiKey = apiKey;
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    if (this.apiKey.length > 0) {
      headers[RELAY_API_KEY_HEADER] = this.apiKey;
    }
    return headers;
  }

  async ensure(deviceToken: string, user: PushRelayUser, existingSubId?: string): Promise<PushRelayRegistration> {
    const payload: RelayEnsureRequest = {
      device_token: deviceToken,
      user_id: user.userId,
      username: user.username,
      sub_id: existingSubId ?? ''
    };
    return this.postRegistration('/subscription/ensure', payload);
  }

  async disable(registration: PushRelayRegistration, user?: PushRelayUser): Promise<void> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const payload: RelayDisableRequest = {
        sub_id: registration.subId ?? '',
        endpoint: registration.endpoint,
        user_id: user?.userId ?? 0,
        username: user?.username ?? ''
      };
      Log.i(`${LOG_TAG} disable start subId=${registration.subId ?? ''} endpointLength=${registration.endpoint.length}`);
      const response: http.HttpResponse = await request.request(`${this.baseUrl}/subscription/disable`, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(),
        extraData: JSON.stringify(payload),
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });
      const raw: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      Log.i(`${LOG_TAG} disable response code=${response.responseCode} bodyLength=${raw.length}`);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`relay http ${response.responseCode}`);
      }
    } catch (err) {
      const detail: string = this.describeError(err);
      Log.i(`${LOG_TAG} disable failed ${detail}`);
      throw new Error(detail.length > 0 ? detail : 'relay disable failed');
    } finally {
      request.destroy();
    }
  }

  async sendTest(registration: PushRelayRegistration, user: PushRelayUser, deviceToken: string): Promise<void> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const payload: RelayTestRequest = {
        device_token: deviceToken,
        sub_id: registration.subId ?? '',
        endpoint: registration.endpoint,
        user_id: user.userId,
        username: user.username
      };
      Log.i(`${LOG_TAG} test start subId=${registration.subId ?? ''} endpointLength=${registration.endpoint.length} tokenLength=${deviceToken.length} userId=${user.userId}`);
      const response: http.HttpResponse = await request.request(`${this.baseUrl}/subscription/test`, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(),
        extraData: JSON.stringify(payload),
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });
      const raw: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      Log.i(`${LOG_TAG} test response code=${response.responseCode} bodyLength=${raw.length}`);
      // 429=中继的测试推送冷却(每条订阅每分钟一次),翻成人话而不是抛 "relay http 429"。
      if (response.responseCode === 429) {
        throw new Error(this.describeCooldown(raw));
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`relay http ${response.responseCode}`);
      }
    } catch (err) {
      const detail: string = this.describeError(err);
      Log.i(`${LOG_TAG} test failed ${detail}`);
      throw new Error(detail.length > 0 ? detail : 'relay test failed');
    } finally {
      request.destroy();
    }
  }

  private async postRegistration(path: string, requestPayload: RelayEnsureRequest): Promise<PushRelayRegistration> {
    const request: http.HttpRequest = http.createHttp();
    try {
      Log.i(`${LOG_TAG} ensure start tokenLength=${requestPayload.device_token.length} userId=${requestPayload.user_id}`);
      const response: http.HttpResponse = await request.request(`${this.baseUrl}${path}`, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(),
        extraData: JSON.stringify(requestPayload),
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });
      const raw: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      Log.i(`${LOG_TAG} ensure response code=${response.responseCode} bodyLength=${raw.length}`);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`relay http ${response.responseCode}`);
      }
      const responsePayload: RelayRegisterResponse = JSON.parse(raw) as RelayRegisterResponse;
      if (typeof responsePayload.endpoint !== 'string' ||
        typeof responsePayload.p256dh !== 'string' ||
        typeof responsePayload.auth !== 'string') {
        throw new Error('invalid relay response');
      }
      return {
        subId: responsePayload.subId,
        endpoint: responsePayload.endpoint,
        p256dh: responsePayload.p256dh,
        auth: responsePayload.auth
      };
    } catch (err) {
      const detail: string = this.describeError(err);
      Log.i(`${LOG_TAG} ensure failed ${detail}`);
      throw new Error(detail.length > 0 ? detail : 'relay ensure failed');
    } finally {
      request.destroy();
    }
  }

  // 把中继的冷却响应 {"error":"cooldown","retryAfter":N} 翻成提示文案。
  // 解析不出秒数也要给句人话,不能把原始 JSON 甩给用户。
  private describeCooldown(raw: string): string {
    try {
      const payload: RelayCooldownResponse = JSON.parse(raw) as RelayCooldownResponse;
      const seconds: number = typeof payload.retryAfter === 'number' ? payload.retryAfter : 0;
      if (seconds > 0) {
        return `操作过于频繁，请 ${seconds} 秒后再试`;
      }
    } catch (err) {
      Log.i(`${LOG_TAG} cooldown parse failed`);
    }
    return '操作过于频繁，请稍后再试';
  }

  private describeError(err: Object): string {
    const error: BusinessError = err as BusinessError;
    const parts: string[] = [];
    if (error.code !== undefined) {
      parts.push(`code=${error.code}`);
    }
    if (error.message !== undefined && error.message.length > 0) {
      parts.push(error.message);
    }
    return parts.join(' ');
  }
}
