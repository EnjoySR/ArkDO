import { Log } from '../logging/Log';
import { ArkWebNetworkBridge } from '../network/ArkWebNetworkBridge';
import { WebSessionManager } from '../web/WebSessionManager';
import { ChallengeResolutionProbe } from './ChallengeResolutionProbe';
import { ChallengeRecoveryEventBus, ChallengeRecoveryState } from './ChallengeRecoveryEventBus';

export { ChallengeRecoveryState };

const DIAG_TAG: string = '[ARKDO_CF_DIAG]';
// 探测节拍与上限:每 2s 用 /latest.json 探一次是否放行(权威判定,不看可能残留的 cf_clearance)。
// 自动盾(managed)一般重载后几秒内就静默跑通,所以窗口不必长;交互盾(需点勾选框)静默永远过不了,
// 越早升级弹窗越好。故:第 3 次(~6s)仍未过则再重载一次 host;第 6 次(~12s)仍未过则升级到交互弹窗。
// (这几个值是"给自动盾的静默宽限"与"交互盾少干等"之间的取舍点,后期调参改这里。)
const PROBE_INTERVAL_MS: number = 2000;
const RELOAD_RETRY_AT_POLL: number = 3;
const MAX_POLL: number = 6;
// 恢复成功后的冷却期:期间吞掉新挑战信号,杜绝"探测放行→重试请求→CF 抖动又拦→再弹"的弹跳。
const COOLDOWN_MS: number = 30000;
// 用户关掉弹窗放弃后的"等手动"保持期:期间吞掉自动挑战信号,只等用户点手动验证再弹。
// 超时回 IDLE 允许后续自动重试,避免永久卡死(无"过盾成功"广播可依赖)。
const DISMISS_HOLDOFF_MS: number = 60000;

// CF 挑战恢复协调器:收到挑战信号后,优先在后台重载 host webview 让挑战 JS 静默跑通拿 cf_clearance,
// 用接口探测判定是否放行;两次重载仍不通才升级到交互弹窗。状态机吞掉恢复中/冷却中的重复信号。
export class ChallengeRecoveryCoordinator {
  private state: ChallengeRecoveryState = ChallengeRecoveryState.IDLE;
  private bridge: ArkWebNetworkBridge;
  private probe: ChallengeResolutionProbe;
  // 静默恢复成功/弹窗解决后调用:广播会话刷新(重载 host、复查登录态、刷新列表)。
  private onRecovered: () => void;
  // 静默两次失败后调用:打开交互式挑战弹窗兜底。
  private onEscalateToSheet: () => void;
  // 过盾窗口开始/结束回调:让上层临时借用/还原 DoH 的 AUTO 模式(解 challenges.cloudflare.com)。
  private onWindowBegin?: () => void;
  private onWindowEnd?: () => void;
  // 窗口活动标志:保证 begin/end 各只触发一次、且 end 不早于 begin。
  private windowActive: boolean = false;
  private pollTimer: number = -1;
  private cooldownTimer: number = -1;
  private pollCount: number = 0;
  private probing: boolean = false;

  constructor(bridge: ArkWebNetworkBridge, onRecovered: () => void, onEscalateToSheet: () => void,
    onWindowBegin?: () => void, onWindowEnd?: () => void) {
    this.bridge = bridge;
    this.probe = new ChallengeResolutionProbe(bridge);
    this.onRecovered = onRecovered;
    this.onEscalateToSheet = onEscalateToSheet;
    this.onWindowBegin = onWindowBegin;
    this.onWindowEnd = onWindowEnd;
  }

  // 过盾窗口开始:只触发一次,让上层临时借用 AUTO(解 challenges.cloudflare.com)。
  private beginWindow(): void {
    if (this.windowActive) {
      return;
    }
    this.windowActive = true;
    const fn: (() => void) | undefined = this.onWindowBegin;
    if (fn) {
      fn();
    }
  }

  // 过盾窗口结束(成功进冷却 / 关闭放弃 / 销毁):还原持久化的 DoH 模式。幂等,可反复调用。
  private endWindow(): void {
    if (!this.windowActive) {
      return;
    }
    this.windowActive = false;
    const fn: (() => void) | undefined = this.onWindowEnd;
    if (fn) {
      fn();
    }
  }

  getState(): ChallengeRecoveryState {
    return this.state;
  }

  // 统一状态迁移出口:落值并广播,让首页空态在"静默中/终态"间跟随切换。
  private setState(next: ChallengeRecoveryState): void {
    this.state = next;
    ChallengeRecoveryEventBus.notifyState(next);
  }

  // 组件销毁时清理计时器。
  dispose(): void {
    this.reset();
  }

  // 收到挑战信号:仅在空闲态开启一轮静默恢复;恢复中/冷却中一律吞掉。
  handleChallengeSignal(source: string): void {
    if (this.state !== ChallengeRecoveryState.IDLE) {
      Log.i(`${DIAG_TAG} stage=recoverySwallow state=${this.state} source=${source}`);
      return;
    }
    this.startRecovery(source);
  }

  // 兜底弹窗验证成功(升级路径的出口):刷新并进入冷却。
  notifySheetResolved(): void {
    Log.i(`${DIAG_TAG} stage=recoverySheetResolved`);
    this.onRecovered();
    this.enterCooldown();
  }

  // 首页"手动验证"按钮:用户主动接管。停掉后台轮询并直接升级到可见弹窗,
  // 后台与前台过验从此互斥,杜绝"弹窗开着后台又探通刷新"的双刷竞态。
  // 冷却期(刚过验完)无活跃挑战,不接管,交回调用方走普通刷新。
  forceEscalate(): boolean {
    if (this.state === ChallengeRecoveryState.COOLDOWN || this.state === ChallengeRecoveryState.AWAITING_SHEET) {
      Log.i(`${DIAG_TAG} stage=recoveryManualIgnored state=${this.state}`);
      return false;
    }
    Log.i(`${DIAG_TAG} stage=recoveryManualEscalate state=${this.state}`);
    this.escalate();
    return true;
  }

  // 用户手动关闭兜底弹窗且未解决:进入"等手动"保持期而非直接回 IDLE。
  // 关键:回 IDLE 会让紧随其后的接口 429 立刻又触发一整轮后台静默探测(十几秒),期间弹窗还没到,
  // 页面卡在"正在自动验证…"转圈的空白死窗口。改为进 DISMISSED——吞掉自动信号、停在终态手动入口,
  // 只有用户点手动验证才重新弹窗;保持期超时回 IDLE 兜底,避免永久卡死。
  notifySheetDismissed(): void {
    if (this.state === ChallengeRecoveryState.AWAITING_SHEET) {
      Log.i(`${DIAG_TAG} stage=recoverySheetDismissed`);
      // 放弃即窗口结束:还原持久化 DoH,等手动期间正常浏览走 SECURE_ONLY;再点手动时 escalate 会重新借用 AUTO。
      this.endWindow();
      this.clearPollTimer();
      this.clearCooldownTimer();
      this.setState(ChallengeRecoveryState.DISMISSED);
      Log.i(`${DIAG_TAG} stage=recoveryDismissHoldoffStart ms=${DISMISS_HOLDOFF_MS}`);
      this.cooldownTimer = setTimeout(() => {
        this.cooldownTimer = -1;
        this.setState(ChallengeRecoveryState.IDLE);
        Log.i(`${DIAG_TAG} stage=recoveryDismissHoldoffEnd`);
      }, DISMISS_HOLDOFF_MS);
    }
  }

  private startRecovery(source: string): void {
    this.setState(ChallengeRecoveryState.RESOLVING);
    this.pollCount = 0;
    Log.i(`${DIAG_TAG} stage=recoveryStart source=${source}`);
    // 先借用 AUTO 再重载 host:让接下来 host/弹窗里对 challenges.cloudflare.com 的请求能回退系统 DNS。
    this.beginWindow();
    this.reloadHost('attempt1');
    this.startPolling();
  }

  private reloadHost(label: string): void {
    const ok: boolean = this.bridge.reloadHost();
    Log.i(`${DIAG_TAG} stage=recoveryReloadHost label=${label} ok=${ok}`);
  }

  private startPolling(): void {
    this.clearPollTimer();
    this.pollTimer = setInterval(() => {
      this.poll();
    }, PROBE_INTERVAL_MS);
  }

  private async poll(): Promise<void> {
    if (this.state !== ChallengeRecoveryState.RESOLVING || this.probing) {
      return;
    }
    this.pollCount++;
    this.probing = true;
    const resolved: boolean = await this.probe.canAccessLatestJson();
    this.probing = false;
    // await 期间状态可能已被 sheet/dismiss 改变,重新校验。
    if (this.state !== ChallengeRecoveryState.RESOLVING) {
      return;
    }
    Log.i(`${DIAG_TAG} stage=recoveryProbe attempt=${this.pollCount}/${MAX_POLL} resolved=${resolved} hasCfClearance=${WebSessionManager.hasCfClearance()}`);
    if (resolved) {
      this.resolvedSilently();
      return;
    }
    if (this.pollCount === RELOAD_RETRY_AT_POLL) {
      this.reloadHost('attempt2');
    }
    if (this.pollCount >= MAX_POLL) {
      this.escalate();
    }
  }

  private resolvedSilently(): void {
    Log.i(`${DIAG_TAG} stage=recoveredSilently attempts=${this.pollCount}`);
    this.clearPollTimer();
    this.onRecovered();
    this.enterCooldown();
  }

  private escalate(): void {
    Log.i(`${DIAG_TAG} stage=recoveryEscalate attempts=${this.pollCount}`);
    this.clearPollTimer();
    // 清掉可能在跑的 DISMISSED 保持期计时:用户点手动验证从放弃态直接重新升级弹窗。
    this.clearCooldownTimer();
    // 幂等借用 AUTO:自动路径下窗口已开(no-op);从 DISMISSED/IDLE 纯手动升级时窗口未开,这里补开,
    // 保证弹窗内 challenges.cloudflare.com 能回退系统 DNS 解出来。
    this.beginWindow();
    this.setState(ChallengeRecoveryState.AWAITING_SHEET);
    this.onEscalateToSheet();
  }

  private enterCooldown(): void {
    // 过盾已结束(成功):还原持久化 DoH 模式,回到 SECURE_ONLY 稳态。
    this.endWindow();
    this.setState(ChallengeRecoveryState.COOLDOWN);
    this.clearCooldownTimer();
    Log.i(`${DIAG_TAG} stage=recoveryCooldownStart ms=${COOLDOWN_MS}`);
    this.cooldownTimer = setTimeout(() => {
      this.cooldownTimer = -1;
      this.setState(ChallengeRecoveryState.IDLE);
      Log.i(`${DIAG_TAG} stage=recoveryCooldownEnd`);
    }, COOLDOWN_MS);
  }

  private reset(): void {
    // 放弃/关闭/销毁也算窗口结束:还原持久化 DoH 模式,避免 AUTO 泄漏到正常浏览期。
    this.endWindow();
    this.clearPollTimer();
    this.clearCooldownTimer();
    this.pollCount = 0;
    this.setState(ChallengeRecoveryState.IDLE);
  }

  private clearPollTimer(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private clearCooldownTimer(): void {
    if (this.cooldownTimer >= 0) {
      clearTimeout(this.cooldownTimer);
      this.cooldownTimer = -1;
    }
  }
}
