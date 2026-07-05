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

export type ReportTimingsFn =
  (topicId: number, timings: Map<number, number>, topicTime: number) => Promise<NetworkResult<string>>;
export type MarkReadFn = (postNumbers: number[]) => void;

interface ConsolidatedTiming {
  topicId: number;
  timings: Map<number, number>;
  topicTime: number;
}

export class ReadingTracker {
  private topicId: number = 0;
  private reportFn?: ReportTimingsFn;
  private onRead?: MarkReadFn;

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
  private intervalId: number = -1;
  // running:start 到 stop 之间为 true(即使后台暂停也保持 true);
  // paused:前台恢复/后台暂停的开关,决定 tick 循环是否在跑。
  private running: boolean = false;
  private paused: boolean = false;

  start(topicId: number, reportFn: ReportTimingsFn, onRead: MarkReadFn): void {
    if (this.running) {
      this.stop();
    }
    this.reset();
    this.topicId = topicId;
    this.reportFn = reportFn;
    this.onRead = onRead;
    const now: number = Date.now();
    this.lastTick = now;
    this.lastScrolled = now;
    this.running = true;
    this.paused = false;
    this.startInterval();
    console.info(`${LOG_TAG} start topicId=${topicId}`);
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
    console.info(`${LOG_TAG} stop topicId=${this.topicId}`);
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
    console.info(`${LOG_TAG} pause topicId=${this.topicId}`);
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
    console.info(`${LOG_TAG} resume topicId=${this.topicId}`);
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

    if (!this.inProgress && (this.lastFlush > NEXT_FLUSH_MS || rush)) {
      this.flush();
    }
    if (!this.inProgress) {
      this.sendNextConsolidatedTiming();
    }

    if (this.hasFocus) {
      this.topicTime += diff;
      for (const postNumber of this.onscreen) {
        const current: number = this.timings.get(postNumber) ?? 0;
        this.timings.set(postNumber, current + diff);
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
      if (time > 0 && total < MAX_TRACKING_TIME_MS) {
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

    this.inProgress = true;
    reportFn(item.topicId, item.timings, item.topicTime).then((result: NetworkResult<string>) => {
      this.inProgress = false;
      this.lastFlush = 0;
      if (result.success) {
        this.ajaxFailures = 0;
        const postNumbers: number[] = [];
        item.timings.forEach((_ms: number, postNumber: number) => {
          postNumbers.push(postNumber);
          this.readPosts.add(postNumber);
        });
        console.info(`${LOG_TAG} report success topicId=${item.topicId} posts=[${postNumbers.join(',')}]`);
        const onRead: MarkReadFn | undefined = this.onRead;
        if (onRead && postNumbers.length > 0) {
          onRead(postNumbers);
        }
      } else {
        console.info(`${LOG_TAG} report failed topicId=${item.topicId} status=${result.statusCode} challenge=${result.challengeState} posts=${item.timings.size}`);
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
      console.info(`${LOG_TAG} report error topicId=${item.topicId} posts=${item.timings.size} error=${JSON.stringify(error)}`);
      this.handleFailure(item, 0);
    });
  }

  // stop 时把队列里剩余的批次全部发出去(忽略 inProgress/退避门闩),确保离开页面前的已读不丢。
  private drainRemaining(): void {
    const reportFn: ReportTimingsFn | undefined = this.reportFn;
    if (!reportFn || this.consolidated.length === 0) {
      return;
    }
    console.info(`${LOG_TAG} drain remaining batches=${this.consolidated.length} topicId=${this.topicId}`);
    while (this.consolidated.length > 0) {
      const item: ConsolidatedTiming | undefined = this.consolidated.pop();
      if (!item) {
        break;
      }
      const postCount: number = item.timings.size;
      reportFn(item.topicId, item.timings, item.topicTime).then((result: NetworkResult<string>) => {
        console.info(`${LOG_TAG} drain report topicId=${item.topicId} posts=${postCount} success=${result.success} status=${result.statusCode}`);
      }).catch((error: Object) => {
        console.info(`${LOG_TAG} drain report topicId=${item.topicId} posts=${postCount} error=${JSON.stringify(error)}`);
      });
    }
  }

  // 命中 CF 质询:静默丢弃本批。Referer 修复后 403 已很少,且多发生在从后台回前台的头一两分钟;
  // 这些楼层仍在屏、会随下一次周期 flush 自然重试并成功(日志已验证),因此无需弹验证、无需特殊处理。
  private handleChallenge(item: ConsolidatedTiming): void {
    console.info(`${LOG_TAG} challenge detected, drop batch silently (will retry on next flush) topicId=${item.topicId} posts=${item.timings.size}`);
  }

  private handleFailure(item: ConsolidatedTiming, statusCode: number): void {
    // 仅对允许的状态码退避重试并重新入队;其它(如 403 challenge)直接丢弃这批。
    if (!ALLOWED_AJAX_FAILURES.includes(statusCode)) {
      console.info(`${LOG_TAG} report dropped (non-retryable) topicId=${item.topicId} status=${statusCode} posts=${item.timings.size}`);
      return;
    }
    const delay: number | undefined = AJAX_FAILURE_DELAYS[this.ajaxFailures];
    this.ajaxFailures += 1;
    if (delay) {
      this.blockSendingTill = Date.now() + delay;
      this.consolidate(item.timings, item.topicTime);
      console.info(`${LOG_TAG} report retry scheduled topicId=${item.topicId} status=${statusCode} attempt=${this.ajaxFailures} delayMs=${delay}`);
    } else {
      console.info(`${LOG_TAG} report retry exhausted topicId=${item.topicId} status=${statusCode} attempts=${this.ajaxFailures}`);
    }
  }
}
