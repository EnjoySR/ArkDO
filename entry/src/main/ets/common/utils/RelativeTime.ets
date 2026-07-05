/**
 * 相对时间格式化工具。
 *
 * 输入 Discourse 返回的 UTC ISO 字符串(结尾带 Z),输出与网页 relativeAgeTiny 对齐的
 * 相对时间文案:刚刚 / N 分钟 / N 小时 / N 天,超出范围回退绝对日期。
 *
 * 分档与取整刻意对齐 Discourse 的 relativeAgeTiny(小时、天都用 Math.round),
 * 否则在小时边界处会比网页少 1,例如 17.5 小时网页显示 18、我们显示 17。
 */
export class RelativeTime {
  /** 输入 ISO 字符串,返回相对时间文案;空串或解析失败返回 ''。 */
  static fromNow(iso?: string): string {
    if (!iso || iso.length === 0) {
      return '';
    }
    const then: number = RelativeTime.parseUtcMillis(iso);
    if (isNaN(then)) {
      return '';
    }
    let seconds: number = Math.floor((Date.now() - then) / 1000);
    if (seconds < 0) {
      seconds = 0;
    }
    const minutes: number = Math.round(seconds / 60);
    if (minutes < 1) {
      return '刚刚';
    }
    if (minutes <= 44) {
      return `${minutes} 分钟`;
    }
    if (minutes <= 89) {
      return '1 小时';
    }
    if (minutes <= 1409) {
      return `${Math.round(minutes / 60)} 小时`;
    }
    if (minutes <= 2519) {
      return '1 天';
    }
    if (minutes <= 20160) {
      return `${Math.round(minutes / 1440)} 天`;
    }
    return RelativeTime.formatAbsoluteDate(iso);
  }

  private static formatAbsoluteDate(iso: string): string {
    const match: RegExpMatchArray | null = iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!match) {
      return '';
    }
    const year: number = Number(match[1]);
    const month: number = Number(match[2]);
    const day: number = Number(match[3]);
    if (year === new Date().getFullYear()) {
      return `${month}月${day}日`;
    }
    return `${year}年${month}月${day}日`;
  }

  // Discourse 的时间戳恒为 UTC(结尾带 Z)。用 Date.UTC 按 UTC 解析,
  // 避免 ArkTS 的 Date.parse 对带时区 ISO 字符串再叠加一次本地偏移(会把时间算到未来)。
  private static parseUtcMillis(iso: string): number {
    const match: RegExpMatchArray | null =
      iso.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/);
    if (!match) {
      return NaN;
    }
    return Date.UTC(
      Number(match[1]),
      Number(match[2]) - 1,
      Number(match[3]),
      Number(match[4]),
      Number(match[5]),
      Number(match[6])
    );
  }
}
