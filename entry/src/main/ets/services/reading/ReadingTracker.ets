import { Log } from '../logging/Log';
import { ChallengeState, NetworkResult } from '../network/NetworkTypes';

// ArkTS 版 Discourse screen-track:详情页停留时按 1 秒 tick 累加在屏楼层时间,
// 满足条件即 POST /topics/timings 上报;上报成功后回调标记这些楼层已读(蓝点淡出)。
// 常量与 flush/rush/退避逻辑对齐官方 frontend/discourse/app/services/screen-track.js。

const LOG_TAG: string = '[ARKDO][ReadingTracker]';

const TICK_INTERVAL_MS: number = 1000;
const NEXT_FLUSH_MS: number = 60 * 1000;
const PAUSE_UNLESS_SCROLLED_MS: number = 1000 * 60 * 3;
const MAX_TRACKING_TIME_MS: number = 1000 * 60 * 6;
const AJAX_FAILURE_DELAYS: number[] = [5000, 10000, 20000, 40000];
const ALLOWED_AJAX_FAILURES: number[] = [405, 429, 500, 501, 502, 503, 504];
// 单次上报常在 1s 内返回,"呼吸"窗口太短会看不清;保证至少完整来回一次(变浅再变回,700ms×2)再收尾。
const MIN_REPORTING_VISIBLE_MS: number = 1400;
// ── 攒批上报间隔(可调)──────────────────────────────────────────────
// 看到未读楼即起闪(pending),但 POST /topics/timings 压到每隔这么久才合并提交一次,
// 大幅降低 timings 请求频次 → 降低触发 CF 全局 429 速率盾的概率。
// 后期调参验证多少最合适就改这一个值(单位 ms)。
const REPORT_BATCH_INTERVAL_MS: number = 5000;

export type ReportTimingsFn =
  (topicId: number, timings: Map<number, number>, topicTime: number) => Promise<NetworkResult<string>>;
export type MarkReadFn = (postNumbers: number[]) => void;
// 上报态回调:上报开始 reporting=true(蓝点呼吸),结束(成功/失败)reporting=false。
export type ReportingStateFn = (postNumbers: number[], reporting: boolean) => void;

interface ConsolidatedTiming {
  topicId: number;
  timings: Map<number, number>;
  topicTime: number;
}

export class ReadingTracker {
  private topicId: number = 0;
  private reportFn?: ReportTimingsFn;
  private onRead?: MarkReadFn;
  private onReporting?: ReportingStateFn;

  private timings: Map<number, number> = new Map();
  private totalTimings: Map<number, number> = new Map();
  private readPosts: Set<number> = new Set();
  private onscreen: number[] = [];
  private topicTime: number = 0;
  private lastTick: number = 0;
  private lastScrolled: number = 0;
  private lastFlush: number = 0;
  private hasFocus: boolean = true;
  private inProgress: boolean = false;
  private consolidated: ConsolidatedTiming[] = [];
  private ajaxFailures: number = 0;
  private blockSendingTill: number = 0;
  // 上次实际发出上报的时间戳:用于把 rush(看到新楼即发)节流为每 REPORT_BATCH_INTERVAL_MS 一批。
  private lastReportAt: number = 0;
  // 本次浏览已"看到并已起闪"的未读楼层:避免每个 tick 对同一楼重复发起闪烁;
  // 上报成功后该楼进 readPosts,由 readPosts 过滤接管(不再起闪)。
  private seenBlinking: Set<number> = new Set();
  private intervalId: number = -1;
  // running:start 到 stop 之间为 true(即使后台暂停也保持 true);
  // paused:前台恢复/后台暂停的开关,决定 tick 循环是否在跑。
  private running: boolean = false;
  private paused: boolean = false;

  start(topicId: number, reportFn: ReportTimingsFn, onRead: MarkReadFn, onReporting?: ReportingStateFn): void {
    if (this.running) {
      this.stop();
    }
    this.reset();
    this.topicId = topicId;
    this.reportFn = reportFn;
    this.onRead = onRead;
    this.onReporting = onReporting;
    const now: number = Date.now();
    this.lastTick = now;
    this.lastScrolled = now;
    // 进帖子首批立即发一次(尽快建立已读水位),之后才进入 REPORT_BATCH_INTERVAL_MS 攒批。
    // 把 lastReportAt 置于一个攒批周期之前 → 首个 tick 的 batchDue 即为 true,首批马上发;
    // 发完 flush 会把 lastReportAt 归位到当前,后续 rush 就正常按 5 秒攒批了。
    this.lastReportAt = now - REPORT_BATCH_INTERVAL_MS;
    this.running = true;
    this.paused = false;
    this.startInterval();
    Log.i(`${LOG_TAG} start topicId=${topicId}`);
  }

  stop(): void {
    if (!this.running) {
      return;
    }
    this.running = false;
    this.paused = false;
    // 结算:若还在跑,最后累加一次并清定时器;否则(后台暂停态)只做 flush。
    if (this.intervalId >= 0) {
      this.tick();
      clearInterval(this.intervalId);
      this.intervalId = -1;
    }
    this.flush();
    // 把队列里剩余的批次(含正好碰上 inProgress/退避而没发出的最后一批)强制发出去,避免丢读。
    this.drainRemaining();
    Log.i(`${LOG_TAG} stop topicId=${this.topicId}`);
    this.reset();
  }

  private startInterval(): void {
    if (this.intervalId >= 0) {
      return;
    }
    this.intervalId = setInterval(() => {
      this.tick();
    }, TICK_INTERVAL_MS);
  }

  // 退到后台:停表并结算上报当前在屏楼层,避免后台期间定时器被系统冻结后计时错乱。
  pause(): void {
    if (!this.running || this.paused) {
      return;
    }
    if (this.intervalId >= 0) {
      this.tick();
      this.flush();
      clearInterval(this.intervalId);
      this.intervalId = -1;
    }
    this.paused = true;
    Log.i(`${LOG_TAG} pause topicId=${this.topicId}`);
  }

  // 回到前台:重置时间基准(避免后台的巨大 diff 与过期的滚动暂停闸门)并重启 tick 循环。
  resume(): void {
    if (!this.running || !this.paused) {
      return;
    }
    const now: number = Date.now();
    this.lastTick = now;
    this.lastScrolled = now;
    this.paused = false;
    this.startInterval();
    Log.i(`${LOG_TAG} resume topicId=${this.topicId}`);
  }

  setOnscreen(postNumbers: number[]): void {
    this.onscreen = postNumbers;
  }

  setFocus(hasFocus: boolean): void {
    this.hasFocus = hasFocus;
    // 前后台即计时循环的恢复/暂停(对齐 Discourse 的 visibilitychange)。
    if (hasFocus) {
      this.resume();
    } else {
      this.pause();
    }
  }

  scrolled(): void {
    this.lastScrolled = Date.now();
  }

  // 把已读楼层预置进 readPosts/totalTimings,避免对已读楼重复计时上报。
  seedRead(postNumbers: number[]): void {
    for (const postNumber of postNumbers) {
      this.readPosts.add(postNumber);
      if (!this.totalTimings.has(postNumber)) {
        this.totalTimings.set(postNumber, 0);
      }
    }
  }

  private reset(): void {
    const now: number = Date.now();
    this.timings.clear();
    this.totalTimings.clear();
    this.readPosts.clear();
    this.onscreen = [];
    this.topicTime = 0;
    this.lastTick = now;
    this.lastScrolled = now;
    this.lastFlush = 0;
    this.inProgress = false;
    this.consolidated = [];
    this.ajaxFailures = 0;
    this.blockSendingTill = 0;
    this.lastReportAt = now;
    this.seenBlinking.clear();
  }

  private tick(): void {
    const now: number = Date.now();

    // 长时间没滚动就停止计时(防挂机误读)。
    if (now - this.lastScrolled > PAUSE_UNLESS_SCROLLED_MS) {
      return;
    }

    const diff: number = now - this.lastTick;
    this.lastFlush += diff;
    this.lastTick = now;

    let rush: boolean = false;
    this.timings.forEach((timing: number, postNumber: number) => {
      const alreadyTotalled: number = this.totalTimings.get(postNumber) ?? 0;
      if (timing > 0 && alreadyTotalled === 0 && !this.readPosts.has(postNumber)) {
        rush = true;
      }
    });

    // rush(看到新楼)不再"下一秒立即发",而是攒到距上次上报满 REPORT_BATCH_INTERVAL_MS 才发一批;
    // 60s 常规兜底(lastFlush > NEXT_FLUSH_MS)不受攒批门闩限制。
    const batchDue: boolean = (now - this.lastReportAt) >= REPORT_BATCH_INTERVAL_MS;
    if (!this.inProgress && (this.lastFlush > NEXT_FLUSH_MS || (rush && batchDue))) {
      this.flush();
    }
    if (!this.inProgress) {
      this.sendNextConsolidatedTiming();
    }

    if (this.hasFocus) {
      this.topicTime += diff;
      const newlySeen: number[] = [];
      for (const postNumber of this.onscreen) {
        const current: number = this.timings.get(postNumber) ?? 0;
        this.timings.set(postNumber, current + diff);
        // 看到未读楼即起闪(pending 提交),不等到网络请求真正发出才闪。已读楼(readPosts)跳过。
        if (!this.readPosts.has(postNumber) && !this.seenBlinking.has(postNumber)) {
          this.seenBlinking.add(postNumber);
          newlySeen.push(postNumber);
        }
      }
      if (newlySeen.length > 0) {
        this.setReporting(newlySeen, true);
      }
    }
  }

  private flush(): void {
    const newTimings: Map<number, number> = new Map();
    this.timings.forEach((time: number, postNumber: number) => {
      if (!this.totalTimings.has(postNumber)) {
        this.totalTimings.set(postNumber, 0);
      }
      const total: number = this.totalTimings.get(postNumber) ?? 0;
      // 已确认已读的楼层(readPosts:服务端已读 + 已成功上报)不再重复上报——
      // 来回滚动让它们重回视口也不会再发 timings,避免冗余请求喂出速率盾。
      if (time > 0 && total < MAX_TRACKING_TIME_MS && !this.readPosts.has(postNumber)) {
        this.totalTimings.set(postNumber, total + time);
        newTimings.set(postNumber, time);
      }
      this.timings.set(postNumber, 0);
    });

    let highestSeen: number = 0;
    newTimings.forEach((_time: number, postNumber: number) => {
      if (postNumber > highestSeen) {
        highestSeen = postNumber;
      }
    });

    if (highestSeen > 0) {
      // 记录本批发出时刻:下一次 rush 攒批从这里重新计 REPORT_BATCH_INTERVAL_MS。
      this.lastReportAt = Date.now();
      this.consolidate(newTimings, this.topicTime);
      this.sendNextConsolidatedTiming();
      this.topicTime = 0;
    }
    this.lastFlush = 0;
  }

  // 本 tracker 只跟一个 topicId,合并策略从简:未发出的批次累加进同一条。
  private consolidate(timings: Map<number, number>, topicTime: number): void {
    if (this.consolidated.length > 0) {
      const found: ConsolidatedTiming = this.consolidated[this.consolidated.length - 1];
      timings.forEach((ms: number, postNumber: number) => {
        found.timings.set(postNumber, (found.timings.get(postNumber) ?? 0) + ms);
      });
      found.topicTime += topicTime;
    } else {
      this.consolidated.push({ topicId: this.topicId, timings: timings, topicTime: topicTime });
    }
  }

  private sendNextConsolidatedTiming(): void {
    const reportFn: ReportTimingsFn | undefined = this.reportFn;
    if (this.consolidated.length === 0 || this.inProgress || !reportFn) {
      return;
    }
    if (this.blockSendingTill > Date.now()) {
      return;
    }

    const item: ConsolidatedTiming | undefined = this.consolidated.pop();
    if (!item) {
      return;
    }

    // 本批涉及的楼号:上报期间让这些楼的蓝点"呼吸",结束时清除。
    const postNumbers: number[] = [];
    item.timings.forEach((_ms: number, postNumber: number) => {
      postNumbers.push(postNumber);
    });

    this.inProgress = true;
    this.setReporting(postNumbers, true);
    const startedAt: number = Date.now();

    reportFn(item.topicId, item.timings, item.topicTime).then((result: NetworkResult<string>) => {
      this.inProgress = false;
      this.lastFlush = 0;
      if (result.success) {
        this.ajaxFailures = 0;
        for (let index: number = 0; index < postNumbers.length; index++) {
          this.readPosts.add(postNumbers[index]);
        }
        Log.i(`${LOG_TAG} report success topicId=${item.topicId} posts=[${postNumbers.join(',')}]`);
        // 呼吸至少完整跑一下再收尾:清呼吸 → 触发淡出(现有 onRead 逻辑不变)。
        this.afterMinReporting(startedAt, () => {
          this.setReporting(postNumbers, false);
          const onRead: MarkReadFn | undefined = this.onRead;
          if (onRead && postNumbers.length > 0) {
            onRead(postNumbers);
          }
        });
      } else {
        Log.i(`${LOG_TAG} report failed topicId=${item.topicId} status=${result.statusCode} challenge=${result.challengeState} posts=${item.timings.size}`);
        // 失败/challenge:清呼吸,蓝点停回静态。
        this.afterMinReporting(startedAt, () => this.setReporting(postNumbers, false));
        if (result.challengeState !== ChallengeState.NONE) {
          // 命中 CF 质询:请求隐藏 host 静默刷新 clearance,成功后重试一次(Method B 验证路径)。
          this.handleChallenge(item);
        } else {
          this.handleFailure(item, result.statusCode);
        }
      }
    }).catch((error: Object) => {
      this.inProgress = false;
      this.lastFlush = 0;
      Log.i(`${LOG_TAG} report error topicId=${item.topicId} posts=${item.timings.size} error=${JSON.stringify(error)}`);
      this.afterMinReporting(startedAt, () => this.setReporting(postNumbers, false));
      this.handleFailure(item, 0);
    });
  }

  private setReporting(postNumbers: number[], reporting: boolean): void {
    const fn: ReportingStateFn | undefined = this.onReporting;
    if (fn && postNumbers.length > 0) {
      fn(postNumbers, reporting);
    }
  }

  // 保证"呼吸"至少可见 MIN_REPORTING_VISIBLE_MS:上报秒回时也让脉动完整跑一下再收尾。
  // 只延迟视觉收尾,网络状态机(inProgress/退避/重试)已在调用前同步推进。
  private afterMinReporting(startedAt: number, action: () => void): void {
    const wait: number = MIN_REPORTING_VISIBLE_MS - (Date.now() - startedAt);
    if (wait <= 0) {
      action();
    } else {
      setTimeout(action, wait);
    }
  }

  // stop 时把队列里剩余的批次全部发出去(忽略 inProgress/退避门闩),确保离开页面前的已读不丢。
  private drainRemaining(): void {
    const reportFn: ReportTimingsFn | undefined = this.reportFn;
    if (!reportFn || this.consolidated.length === 0) {
      return;
    }
    Log.i(`${LOG_TAG} drain remaining batches=${this.consolidated.length} topicId=${this.topicId}`);
    while (this.consolidated.length > 0) {
      const item: ConsolidatedTiming | undefined = this.consolidated.pop();
      if (!item) {
        break;
      }
      const postCount: number = item.timings.size;
      reportFn(item.topicId, item.timings, item.topicTime).then((result: NetworkResult<string>) => {
        Log.i(`${LOG_TAG} drain report topicId=${item.topicId} posts=${postCount} success=${result.success} status=${result.statusCode}`);
      }).catch((error: Object) => {
        Log.i(`${LOG_TAG} drain report topicId=${item.topicId} posts=${postCount} error=${JSON.stringify(error)}`);
      });
    }
  }

  // 命中 CF 质询:静默丢弃本批。Referer 修复后 403 已很少,且多发生在从后台回前台的头一两分钟;
  // 这些楼层仍在屏、会随下一次周期 flush 自然重试并成功(日志已验证),因此无需弹验证、无需特殊处理。
  private handleChallenge(item: ConsolidatedTiming): void {
    Log.i(`${LOG_TAG} challenge detected, drop batch silently (will retry on next flush) topicId=${item.topicId} posts=${item.timings.size}`);
  }

  private handleFailure(item: ConsolidatedTiming, statusCode: number): void {
    // 仅对允许的状态码退避重试并重新入队;其它(如 403 challenge)直接丢弃这批。
    if (!ALLOWED_AJAX_FAILURES.includes(statusCode)) {
      Log.i(`${LOG_TAG} report dropped (non-retryable) topicId=${item.topicId} status=${statusCode} posts=${item.timings.size}`);
      return;
    }
    const delay: number | undefined = AJAX_FAILURE_DELAYS[this.ajaxFailures];
    this.ajaxFailures += 1;
    if (delay) {
      this.blockSendingTill = Date.now() + delay;
      this.consolidate(item.timings, item.topicTime);
      Log.i(`${LOG_TAG} report retry scheduled topicId=${item.topicId} status=${statusCode} attempt=${this.ajaxFailures} delayMs=${delay}`);
    } else {
      Log.i(`${LOG_TAG} report retry exhausted topicId=${item.topicId} status=${statusCode} attempts=${this.ajaxFailures}`);
    }
  }
}
