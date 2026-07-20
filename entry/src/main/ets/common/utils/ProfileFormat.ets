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

// 信任等级标签。两页的取法不同,这不是漂移,是布局决定的——改之前务必先看清楚:
//
//   「我的」页(ProfilePage)   头衔没有独立位置,`@username · TL3 ___` 是它唯一的露出。
//                            故用 trustLabelWithTitleOf,头衔优先,否则自己的头衔永远看不见。
//   他人页(UserProfilePage)  头衔已在 `@username 指导顾问` 单独占一行(特殊头衔还有全息效果)。
//                            故用 trustLabelOf 显示等级名;若也走头衔优先,同一个头衔会显示两遍,
//                            且「TL3 指导顾问」读起来像在说 TL3 的等级名就叫指导顾问。
//
// 换言之:哪一侧承担"展示头衔"的职责,另一侧就该让位。谁调哪个由页面布局定,不可想当然统一。

// 只用信任等级名,形如「TL3 活跃用户」。用于页面别处已经展示过头衔的场合。
export function trustLabelOf(detail?: UserProfileDetail): string {
  if (!detail || detail.trustLevel === undefined) {
    return '';
  }
  const levelName: string = trustLevelNameOf(detail.trustLevel);
  return levelName.length > 0 ? `TL${detail.trustLevel} ${levelName}` : `TL${detail.trustLevel}`;
}

// 头衔优先,缺省回落到等级名,形如「TL3 赞助商」或「TL3 活跃用户」。
// 用于页面别处没有头衔展示位、这里是头衔唯一露出的场合。
export function trustLabelWithTitleOf(detail?: UserProfileDetail): string {
  if (!detail || detail.trustLevel === undefined) {
    return '';
  }
  const title: string = detail.title && detail.title.length > 0 ? detail.title : '';
  const levelName: string = title.length > 0 ? title : trustLevelNameOf(detail.trustLevel);
  return levelName.length > 0 ? `TL${detail.trustLevel} ${levelName}` : `TL${detail.trustLevel}`;
}

// 等级号 → 内置中文名。站点新增等级导致超出名表时返回空串,由调用方只显示 TL 号。
function trustLevelNameOf(trustLevel: number): string {
  return trustLevel >= 0 && trustLevel < TRUST_LEVEL_NAMES.length ? TRUST_LEVEL_NAMES[trustLevel] : '';
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
