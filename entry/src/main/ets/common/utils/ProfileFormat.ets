import { UserBadgeItem, UserProfileDetail } from '../../models/UserProfile';

// 徽章墙每行的格数。
const BADGE_COLUMNS: number = 3;

// 「我的」页与「他人主页」共用的资料展示格式化。
//
// 这两页是孪生页(UserProfilePage 自己的注释里就这么称呼),此前 21 个同名私有方法各写一份。
// 复制粘贴已经导致过真实的显示分叉:getTrustLabel 在两页给同一份数据算出不同结果。
// 集中到这里,格式规则只有一处。

// Discourse 信任等级中文名(0-4)。user.title 缺省时的兜底展示。
export const TRUST_LEVEL_NAMES: string[] = ['新用户', '基本用户', '成员', '活跃用户', '领导者'];

// 计数缩写:1000 以下原样,1000-9999 保留一位小数(1.2k),万以上取整(12k)。
export function formatCount(value: number): string {
  if (value < 1000) {
    return `${value}`;
  }
  if (value < 10000) {
    const tenths: number = Math.floor(value / 100);
    const whole: number = Math.floor(tenths / 10);
    const frac: number = tenths % 10;
    return frac === 0 ? `${whole}k` : `${whole}.${frac}k`;
  }
  return `${Math.floor(value / 1000)}k`;
}

// 阅读时长:不足 1 小时按分钟(至少 1m),否则按小时。
export function formatTimeRead(seconds: number): string {
  if (seconds < 3600) {
    return `${Math.max(1, Math.round(seconds / 60))}m`;
  }
  return `${Math.round(seconds / 3600)}h`;
}

// 信任等级标签,形如「TL3 活跃用户」或「TL3 赞助商」。
//
// 优先取站点头衔(user.title),缺省才回落到 TL 默认名——这是两页注释里都写明的约定,
// 但 UserProfilePage 的实现漏掉了 title 分支,导致同一个用户在「我的」页显示自定义头衔、
// 在他人主页显示 TL 默认名。此处按注释声明的契约统一。
export function trustLabelOf(detail?: UserProfileDetail): string {
  if (!detail || detail.trustLevel === undefined) {
    return '';
  }
  const levelName: string = detail.title && detail.title.length > 0
    ? detail.title
    : (detail.trustLevel >= 0 && detail.trustLevel < TRUST_LEVEL_NAMES.length
      ? TRUST_LEVEL_NAMES[detail.trustLevel]
      : '');
  return levelName.length > 0 ? `TL${detail.trustLevel} ${levelName}` : `TL${detail.trustLevel}`;
}

// 注册至今天数。ISO 时间戳只取日期段做 UTC 归一,不引入时区偏移。
export function daysSince(iso?: string): number {
  const parts: number[] | undefined = isoDateParts(iso);
  if (!parts) {
    return 0;
  }
  const thenMillis: number = Date.UTC(parts[0], parts[1] - 1, parts[2]);
  const days: number = Math.floor((Date.now() - thenMillis) / 86400000);
  return days > 0 ? days : 1;
}

// 注册日期,形如「2024年1月18日」。
export function formatJoinDate(iso?: string): string {
  const parts: number[] | undefined = isoDateParts(iso);
  if (!parts) {
    return '';
  }
  return `${parts[0]}年${parts[1]}月${parts[2]}日`;
}

// 从 ISO 时间戳取 [年, 月, 日]。取不到返回 undefined。
function isoDateParts(iso?: string): number[] | undefined {
  if (!iso || iso.length === 0) {
    return undefined;
  }
  const match: RegExpMatchArray | null = iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!match) {
    return undefined;
  }
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

// 徽章墙按每行 3 格切分。
export function badgeRowsOf(badges: UserBadgeItem[]): UserBadgeItem[][] {
  const rows: UserBadgeItem[][] = [];
  for (let index: number = 0; index < badges.length; index += BADGE_COLUMNS) {
    rows.push(badges.slice(index, index + BADGE_COLUMNS));
  }
  return rows;
}

// 末行不足 3 格时的占位下标。ForEach 需要可迭代的数据源,故返回下标数组而非计数。
export function badgeRowFillers(row: UserBadgeItem[]): number[] {
  const fillers: number[] = [];
  for (let index: number = row.length; index < BADGE_COLUMNS; index++) {
    fillers.push(index);
  }
  return fillers;
}

// 徽章分组标题,形如「徽章 · 12」;总数缺省或为 0 时只显示「徽章」。
export function badgeHeadLabel(badgeCount?: number): string {
  return badgeCount !== undefined && badgeCount > 0 ? `徽章 · ${badgeCount}` : '徽章';
}
