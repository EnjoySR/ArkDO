import { Log } from '../logging/Log';
import { ArkWebNetworkBridge } from '../network/ArkWebNetworkBridge';
import { WebSessionManager } from '../web/WebSessionManager';
import { ChallengeResolutionProbe } from './ChallengeResolutionProbe';

const DIAG_TAG: string = '[ARKDO_CF_DIAG]';
// 探测节拍与上限:每 2s 用 /latest.json 探一次是否放行(权威判定,不看可能残留的 cf_clearance);
// 第 6 次(~12s)仍未过则再重载一次 host;第 12 次(~24s)仍未过则升级到交互弹窗。
const PROBE_INTERVAL_MS: number = 2000;
const RELOAD_RETRY_AT_POLL: number = 6;
const MAX_POLL: number = 12;
// 恢复成功后的冷却期:期间吞掉新挑战信号,杜绝"探测放行→重试请求→CF 抖动又拦→再弹"的弹跳。
const COOLDOWN_MS: number = 30000;

export enum ChallengeRecoveryState {
  IDLE = 0,
  RESOLVING = 1,
  AWAITING_SHEET = 2,
  COOLDOWN = 3
}

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
  private pollTimer: number = -1;
  private cooldownTimer: number = -1;
  private pollCount: number = 0;
  private probing: boolean = false;

  constructor(bridge: ArkWebNetworkBridge, onRecovered: () => void, onEscalateToSheet: () => void) {
    this.bridge = bridge;
    this.probe = new ChallengeResolutionProbe(bridge);
    this.onRecovered = onRecovered;
    this.onEscalateToSheet = onEscalateToSheet;
  }

  getState(): ChallengeRecoveryState {
    return this.state;
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

  // 用户手动关闭兜底弹窗且未解决:回到空闲,下次挑战再试。
  notifySheetDismissed(): void {
    if (this.state === ChallengeRecoveryState.AWAITING_SHEET) {
      Log.i(`${DIAG_TAG} stage=recoverySheetDismissed`);
      this.reset();
    }
  }

  private startRecovery(source: string): void {
    this.state = ChallengeRecoveryState.RESOLVING;
    this.pollCount = 0;
    Log.i(`${DIAG_TAG} stage=recoveryStart source=${source}`);
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
    this.state = ChallengeRecoveryState.AWAITING_SHEET;
    this.onEscalateToSheet();
  }

  private enterCooldown(): void {
    this.state = ChallengeRecoveryState.COOLDOWN;
    this.clearCooldownTimer();
    Log.i(`${DIAG_TAG} stage=recoveryCooldownStart ms=${COOLDOWN_MS}`);
    this.cooldownTimer = setTimeout(() => {
      this.cooldownTimer = -1;
      this.state = ChallengeRecoveryState.IDLE;
      Log.i(`${DIAG_TAG} stage=recoveryCooldownEnd`);
    }, COOLDOWN_MS);
  }

  private reset(): void {
    this.clearPollTimer();
    this.clearCooldownTimer();
    this.pollCount = 0;
    this.state = ChallengeRecoveryState.IDLE;
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
