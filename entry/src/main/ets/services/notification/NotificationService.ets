import { Log } from '../logging/Log';
import { User } from '../../models/User';
import { AuthService } from '../auth/AuthService';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { AppStateEventBus } from '../session/AppStateEventBus';
import { NotificationEventBus } from './NotificationEventBus';

const LOG_TAG: string = '[ArkDO][Notification]';
const POLL_INTERVAL_MS: number = 45000; // 前台驻留时的轮询周期

// 头像未读数轮询服务:登录后由 RootTabPage start(),前台时每 POLL_INTERVAL_MS 拉一次
// /session/current.json(复用 AuthService),解析未读并发到 NotificationEventBus。
// 特意"静默":不经过 RootTabPage.checkCurrentUser 那条会更新 isCheckingSession 的路径,
// 否则头像会每 45s 闪一下 loading。后台自动停表,回前台再拉一次+续表。
export class NotificationService {
  private authService: AuthService;
  private started: boolean = false;
  private intervalId: number = -1;
  private unsubscribeAppState?: () => void = undefined;
  // 请求序号:丢弃过期/stop 后返回的响应,避免旧结果覆盖新状态。
  private refreshSequence: number = 0;

  constructor(bridge: JsonNetworkClient) {
    this.authService = new AuthService(bridge);
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

  private startInterval(): void {
    if (this.intervalId !== -1) {
      return;
    }
    this.intervalId = setInterval(() => {
      this.refresh();
    }, POLL_INTERVAL_MS);
  }

  private stopInterval(): void {
    if (this.intervalId === -1) {
      return;
    }
    clearInterval(this.intervalId);
    this.intervalId = -1;
  }
}
