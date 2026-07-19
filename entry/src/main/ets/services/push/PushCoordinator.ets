import { common } from '@kit.AbilityKit';
import { Log } from '../logging/Log';
import { User } from '../../models/User';
import { JsonNetworkClient } from '../network/NetworkTypes';
import {
  PushNotificationPermissionResult,
  PushNotificationPermissionService
} from './PushNotificationPermissionService';
import {
  PushRegistrationResult,
  PushRelayRegistration,
  PushRelayUser,
  PushStatusResult,
  PushSubscriptionService
} from './PushSubscriptionService';
import { HarmonyPushTokenProvider } from './HarmonyPushTokenProvider';
import { HttpPushRelayClient } from './PushRelayClient';
import { isPushRelayConfigured, PushRelayConfig, resolvePushRelayConfig } from './PushRelayConfig';
import { PushSubscriptionStore, StoredPushSubscription } from './PushSubscriptionStore';

const LOG_TAG: string = '[ArkDO][PushCoordinator]';

// 同一账号连续自愈失败的重试上限。到顶就停手,等下次启动或 token 轮换再说,
// 免得每轮会话轮询都白打一次网络。
const PUSH_RECONCILE_MAX_ATTEMPTS: number = 3;

export type ContextFn = () => common.UIAbilityContext | undefined;
export type CurrentUserFn = () => User | undefined;
export type BridgeFn = () => JsonNetworkClient;

// 系统推送的开关/状态/自愈/登出清理。
//
// 从 RootTabPage 抽出——那里原本是 238 行、占该文件 13.7%,而它与页面渲染毫无关系:
// 不读也不写任何 @State,全部状态是三个普通字段(在途标志 + 账号键 + 重试计数)。
// RootTabPage 是全项目改动最频繁的文件(半年 48 次),把这块搬走能显著减少它的噪音。
//
// 三个依赖全部经闭包惰性读取,不在字段初始化器里按值捕获:
// RootTabPage 创建本类时,父组件注入的 bridge prop 还没覆盖默认值,按值捕获会拿到
// 未连接宿主的空壳(项目里已实测翻车过,PostActions 的注释记录了同一个坑)。
// context 同理:UIAbility 上下文要在 UI 就绪后才取得到。
export class PushCoordinator {
  private getContext: ContextFn;
  private getUser: CurrentUserFn;
  private getBridge: BridgeFn;
  private permissionService: PushNotificationPermissionService = new PushNotificationPermissionService();
  // 自愈在途闸:调用方是即发即忘,不加这个会在会话轮询密集时并发重跑。
  private reconcileInFlight: boolean = false;
  private reconcileAccountKey: string = '';
  private reconcileAttempts: number = 0;

  constructor(getContext: ContextFn, getUser: CurrentUserFn, getBridge: BridgeFn) {
    this.getContext = getContext;
    this.getUser = getUser;
    this.getBridge = getBridge;
  }

  async enable(): Promise<PushRegistrationResult> {
    return this.ensure(true);
  }

  async refreshStatus(): Promise<PushStatusResult> {
    const context: common.UIAbilityContext | undefined = this.getContext();
    const user: User | undefined = this.getUser();
    if (!context || user === undefined || user.id <= 0 || user.username.length === 0) {
      return { enabled: false, message: '请先登录 linux.do' };
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    if (!stored.desiredEnabled || PushSubscriptionStore.toRegistration(stored) === undefined) {
      return { enabled: false, message: '未开启' };
    }

    // 只报状态,不重注册。以前这里跑的是完整 ensure(取 token→中继→linux.do 写请求),
    // 于是离线或中继暂时不可达时进一次设置页,就把开关误翻成"关闭"——而服务端订阅其实还在。
    // 订阅的保活/自愈交给 reconcilePushSubscription 在后台静默做,不参与本页开关的显示。
    const permission: PushNotificationPermissionResult = await this.permissionService.checkEnabled();
    if (!permission.enabled) {
      // 订阅还在,只是系统通知权限被关了:开关保持"开",但把原因说清楚。
      return { enabled: true, message: permission.message };
    }

    return {
      enabled: true,
      message: '已开启'
    };
  }

  async ensure(requestPermission: boolean): Promise<PushRegistrationResult> {
    const context: common.UIAbilityContext | undefined = this.getContext();
    if (!context) {
      return {
        success: false,
        message: '通知权限申请失败: 缺少 AbilityContext'
      };
    }
    const user: User | undefined = this.getUser();
    if (user === undefined || user.id <= 0 || user.username.length === 0) {
      return {
        success: false,
        message: '请先登录 linux.do 账号'
      };
    }
    // 中继地址来自随包配置(不进版本控制)或用户自填。自行编译且没配的话推送不可用,
    // 这里明确说清楚,免得用户以为是网络或账号问题。
    if (!isPushRelayConfigured(context)) {
      return {
        success: false,
        message: '未配置推送中继,请在设置中填写中继地址'
      };
    }

    const permission: PushNotificationPermissionResult = requestPermission
      ? await this.permissionService.ensureEnabled(context)
      : await this.permissionService.checkEnabled();
    if (!permission.enabled) {
      return {
        success: false,
        message: permission.message
      };
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    const relayUser: PushRelayUser = {
      userId: user.id,
      username: user.username
    };
    const result: PushRegistrationResult = await this.serviceRef(context).enable(relayUser, stored.subId);
    if (result.success && result.endpoint !== undefined && result.p256dh !== undefined && result.auth !== undefined) {
      PushSubscriptionStore.saveEnabled(context, user.id, {
        subId: result.subId,
        endpoint: result.endpoint,
        p256dh: result.p256dh,
        auth: result.auth
      });
    }
    return result;
  }

  async disable(): Promise<PushRegistrationResult> {
    const context: common.UIAbilityContext | undefined = this.getContext();
    const user: User | undefined = this.getUser();
    if (!context || user === undefined || user.id <= 0 || user.username.length === 0) {
      return { success: false, message: '请先登录 linux.do 账号' };
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    const registration: PushRelayRegistration | undefined = PushSubscriptionStore.toRegistration(stored);
    if (registration === undefined) {
      PushSubscriptionStore.saveDisabled(context, user.id);
      return { success: true, message: '推送订阅已关闭' };
    }
    const relayUser: PushRelayUser = {
      userId: user.id,
      username: user.username
    };
    const result: PushRegistrationResult = await this.serviceRef(context).disable(registration, relayUser);
    if (result.success) {
      PushSubscriptionStore.saveDisabled(context, user.id);
    }
    return result;
  }

  // 推送保活/自愈:订阅不是"开一次永久有效"——中继连续投递失败超 1 天会被 Discourse 删掉
  // (MAX_ERRORS),设备 token 也会因重装/恢复出厂/系统刷新而轮换,两种情况都会让推送静默失效。
  // 故在登录态落定与 token 轮换时,对"用户开过推送"的账号静默重跑一遍订阅登记。
  // 这套动作本就幂等:中继按 (deviceToken, user) 复用同一 subId,linux.do 同 endpoint 重复
  // subscribe 也不会重复建,所以代价很小。
  // 全程静默:这是后台自愈而非用户发起的操作,失败不弹 toast、不翻设置页开关。
  async reconcile(force: boolean): Promise<void> {
    const context: common.UIAbilityContext | undefined = this.getContext();
    const user: User | undefined = this.getUser();
    if (!context || user === undefined || user.id <= 0 || user.username.length === 0) {
      return;
    }
    if (this.reconcileInFlight) {
      return;
    }

    const accountKey: string = `${user.id}`;
    if (accountKey !== this.reconcileAccountKey) {
      // 换号(或本次启动首次落定):重置重试预算。
      this.reconcileAttempts = 0;
    } else if (!force && this.reconcileAttempts >= PUSH_RECONCILE_MAX_ATTEMPTS) {
      // 同一账号已连续失败到上限:停手,等下次启动或 token 轮换再说,免得每轮会话轮询都打网络。
      return;
    }

    // 只兑现用户自己开过的推送,绝不擅自替用户开启。
    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    if (!stored.desiredEnabled) {
      this.reconcileAccountKey = accountKey;
      return;
    }
    if (!force && accountKey === this.reconcileAccountKey && this.reconcileAttempts === 0) {
      // 本账号本次启动已自愈成功过,无须重复。
      return;
    }

    this.reconcileInFlight = true;
    this.reconcileAccountKey = accountKey;
    // 调用方是即发即忘(不 await),异常不能逃逸成未处理拒绝;失败一律按"本次自愈没成"记账。
    try {
      const result: PushRegistrationResult = await this.ensure(false);
      if (result.success) {
        this.reconcileAttempts = 0;
        Log.i(`${LOG_TAG} push reconcile ok userId=${user.id} force=${force}`);
        return;
      }
      this.reconcileAttempts++;
      Log.i(`${LOG_TAG} push reconcile failed userId=${user.id} attempts=${this.reconcileAttempts} message=${result.message}`);
    } catch (err) {
      this.reconcileAttempts++;
      Log.i(`${LOG_TAG} push reconcile exception userId=${user.id} attempts=${this.reconcileAttempts} error=${JSON.stringify(err)}`);
    } finally {
      this.reconcileInFlight = false;
    }
  }

  // 服务依赖惰性构造:this.getBridge() 是父注入的 prop,字段初始化器里取到的是空壳,须调用时再读。
  // 中继地址/密钥每次都重新解析:用户可能刚在设置页改过自建地址,缓存住会用错服务器。
  serviceRef(context: common.Context): PushSubscriptionService {
    const config: PushRelayConfig = resolvePushRelayConfig(context);
    return new PushSubscriptionService(
      this.getBridge(),
      new HarmonyPushTokenProvider(),
      new HttpPushRelayClient(config.baseUrl, config.apiKey)
    );
  }

  // 登出前清理系统推送。必须在 AuthService.logout 之前跑完:linux.do 退订要带登录 cookie,
  // 登出后就退不掉了,那条订阅会连同中继里的 deviceToken 一起留存——本机继续收到该账号的
  // 私信/回复推送(换号后亦然,属跨账号泄露),而设置页此时因未登录连开关都点不动。
  // 失败不阻断登出:中继解绑成功即可,之后中继返回 410,Discourse 自行删除订阅。
  async disableForLogout(): Promise<void> {
    const context: common.UIAbilityContext | undefined = this.getContext();
    const user: User | undefined = this.getUser();
    if (!context || user === undefined || user.id <= 0) {
      return;
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    const registration: PushRelayRegistration | undefined = PushSubscriptionStore.toRegistration(stored);
    if (registration === undefined) {
      // 没有有效订阅:仅把本地开关落回关闭,避免重新登录后误显示"已开启"。
      if (stored.desiredEnabled) {
        PushSubscriptionStore.saveDisabled(context, user.id);
      }
      return;
    }

    Log.i(`${LOG_TAG} logout push cleanup start userId=${user.id} subId=${stored.subId}`);
    await this.serviceRef(context).disableForLogout(registration, {
      userId: user.id,
      username: user.username
    });
    // 无论两侧结果如何都清本地:登出后已无登录态可重试,留着只会让 UI 显示错误的"已开启"。
    PushSubscriptionStore.saveDisabled(context, user.id);
    Log.i(`${LOG_TAG} logout push cleanup done userId=${user.id}`);
  }

  async sendTest(): Promise<PushStatusResult> {
    const context: common.UIAbilityContext | undefined = this.getContext();
    const user: User | undefined = this.getUser();
    if (!context || user === undefined || user.id <= 0 || user.username.length === 0) {
      return { enabled: false, message: '请先登录 linux.do 账号' };
    }

    const ensureResult: PushRegistrationResult = await this.ensure(false);
    if (!ensureResult.success) {
      return {
        enabled: false,
        message: ensureResult.message
      };
    }

    const stored: StoredPushSubscription = PushSubscriptionStore.get(context, user.id);
    const registration: PushRelayRegistration | undefined = PushSubscriptionStore.toRegistration(stored);
    if (registration === undefined || (registration.subId ?? '').length === 0) {
      return { enabled: false, message: '推送订阅参数无效' };
    }

    const relayUser: PushRelayUser = {
      userId: user.id,
      username: user.username
    };
    return this.serviceRef(context).sendTest(registration, relayUser);
  }

  // 登出/换号时清掉自愈基准,让下一个账号登录时重新兑现自己的订阅
  // (否则新账号会被上一个账号的 accountKey 挡住,首次登录不自愈)。
  resetReconcileState(): void {
    this.reconcileAccountKey = '';
    this.reconcileAttempts = 0;
  }
}
