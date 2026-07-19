import { Log } from '../logging/Log';
import { User } from '../../models/User';
import { AuthService } from '../auth/AuthService';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { AppStateEventBus } from '../session/AppStateEventBus';
import { NotificationEventBus } from './NotificationEventBus';
import { MarkReadByTopicResult, NotificationApi } from './NotificationApi';

// 私信/邀请进私信属高优先级未读(highPriority),标记已读时要连带把 highPriority 也减 1。
const HIGH_PRIORITY_TYPES: number[] = [6, 7];

const LOG_TAG: string = '[ArkDO][Notification]';
// 前台轮询基准周期与抖动幅度:固定 45s 整节拍是 CF 行为分析的典型机器人特征,
// 每次在 ±20% 内随机取值打散节拍(用 setTimeout 链而非 setInterval)。
const POLL_INTERVAL_BASE_MS: number = 45000;
const POLL_JITTER_RATIO: number = 0.2;

// 头像未读数轮询服务:登录后由 RootTabPage start(),前台时每 POLL_INTERVAL_MS 拉一次
// /session/current.json(复用 AuthService),解析未读并发到 NotificationEventBus。
// 特意"静默":不经过 RootTabPage.checkCurrentUser 那条会更新 isCheckingSession 的路径,
// 否则头像会每 45s 闪一下 loading。后台自动停表,回前台再拉一次+续表。
export class NotificationService {
  private authService: AuthService;
  private api: NotificationApi;
  private started: boolean = false;
  private intervalId: number = -1;
  private unsubscribeAppState?: () => void = undefined;
  // 请求序号:丢弃过期/stop 后返回的响应,避免旧结果覆盖新状态。
  private refreshSequence: number = 0;

  constructor(bridge: JsonNetworkClient) {
    this.authService = new AuthService(bridge);
    this.api = new NotificationApi(bridge);
  }

  // 点系统推送打开帖子时调用:把该帖对应楼层那条未读通知标记已读,并乐观地把铃铛未读数减 1。
  // 即发即忘,失败静默——标不上(找不到匹配/网络失败)就维持现状,等下次轮询用服务端值覆盖,
  // 绝不擅自改动铃铛(见 NotificationEventBus.decrementUnread 的 0/空窗保护)。
  async markPushNotificationRead(topicId: number, postNumber?: number): Promise<void> {
    try {
      const result: MarkReadByTopicResult = await this.api.markReadByTopic(topicId, postNumber);
      if (!result.marked) {
        return;
      }
      const highPriority: boolean = HIGH_PRIORITY_TYPES.indexOf(result.notificationType) >= 0;
      NotificationEventBus.decrementUnread(highPriority);
    } catch (err) {
      Log.i(`${LOG_TAG} markPushNotificationRead failed topicId=${topicId} error=${JSON.stringify(err)}`);
    }
  }

  // 登录成功/会话确认后调用。重复调用安全:已启动则只补拉一次。
  start(): void {
    if (this.started) {
      this.refresh();
      return;
    }
    this.started = true;
    this.unsubscribeAppState = AppStateEventBus.subscribe((isForeground: boolean) => {
      this.handleForegroundChanged(isForeground);
    });
    Log.i(`${LOG_TAG} start foreground=${AppStateEventBus.isForeground()}`);
    if (AppStateEventBus.isForeground()) {
      this.refresh();
      this.startInterval();
    }
  }

  // 登出/会话失效时调用:停表、退订、未读清零。
  stop(): void {
    if (!this.started) {
      return;
    }
    this.started = false;
    this.stopInterval();
    if (this.unsubscribeAppState) {
      this.unsubscribeAppState();
      this.unsubscribeAppState = undefined;
    }
    this.refreshSequence++; // 作废进行中的请求
    Log.i(`${LOG_TAG} stop`);
    NotificationEventBus.publish({ unread: 0, highPriority: 0 });
  }

  // 拉一次未读数并广播。网络/验证失败时保留上次值(不清零),仅登出才清零。
  async refresh(): Promise<void> {
    const seq: number = this.refreshSequence + 1;
    this.refreshSequence = seq;

    const result: NetworkResult<User | undefined> = await this.authService.getCurrentUser();
    if (seq !== this.refreshSequence || !this.started) {
      return; // 已过期或已 stop
    }

    if (!result.success) {
      Log.i(`${LOG_TAG} refresh failed status=${result.statusCode} challenge=${result.challengeState}`);
      return;
    }

    if (result.data === undefined) {
      // 会话已失效(登出):清零。
      NotificationEventBus.publish({ unread: 0, highPriority: 0 });
      return;
    }

    const user: User = result.data;
    NotificationEventBus.publish({
      unread: user.unreadNotifications !== undefined ? user.unreadNotifications : 0,
      highPriority: user.unreadHighPriorityNotifications !== undefined ? user.unreadHighPriorityNotifications : 0
    });
  }

  private handleForegroundChanged(isForeground: boolean): void {
    if (!this.started) {
      return;
    }
    if (isForeground) {
      this.refresh();
      this.startInterval();
    } else {
      this.stopInterval();
    }
  }

  // setTimeout 链自调度:每次刷新后按抖动后的间隔再排下一次,避免固定节拍。
  private startInterval(): void {
    if (this.intervalId !== -1) {
      return;
    }
    this.scheduleNextPoll();
  }

  private scheduleNextPoll(): void {
    this.intervalId = setTimeout(() => {
      this.refresh();
      // stop()/后台会置 -1;仅在仍处于计时态时续排下一次。
      if (this.intervalId !== -1) {
        this.intervalId = -1;
        this.scheduleNextPoll();
      }
    }, this.nextPollDelayMs());
  }

  private nextPollDelayMs(): number {
    const jitter: number = (Math.random() * 2 - 1) * POLL_JITTER_RATIO;
    return Math.round(POLL_INTERVAL_BASE_MS * (1 + jitter));
  }

  private stopInterval(): void {
    if (this.intervalId === -1) {
      return;
    }
    clearTimeout(this.intervalId);
    this.intervalId = -1;
  }
}
