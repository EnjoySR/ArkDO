// connect.linux.do「信任级别要求」页解析出的结构化数据。
// 页面为服务端渲染,数值直接在 DOM 里(见 .tl3-ring/.tl3-bar-item/.tl3-quota-card/.tl3-veto-item)。

// 活跃程度环形项:current/target 为展示文本(如 "45"、"/ 50"),val/max 为环形填充用数值。
export interface ConnectRingItem {
  label: string;
  current: string;
  target: string;
  val: number;
  max: number;
  met: boolean;
}

// 互动参与进度条项:nums 为展示文本(如 "157/10"),val/max 驱动填充宽度。
export interface ConnectBarItem {
  label: string;
  nums: string;
  val: number;
  max: number;
  met: boolean;
}

// 合规配额卡(被举报帖子/举报用户):slots 为总格数,used 为已占用(违规)格数。
export interface ConnectQuotaItem {
  label: string;
  nums: string;
  slots: number;
  used: number;
  met: boolean;
}

// 否决项(被禁言/被封禁):value 为次数文本,met=true 达标(0 次)。
export interface ConnectVetoItem {
  label: string;
  desc: string;
  value: string;
  met: boolean;
}

export interface ConnectLevelData {
  title: string;
  statusLabel: string;
  statusIsMet: boolean;
  subtitle: string;
  rings: ConnectRingItem[];
  bars: ConnectBarItem[];
  quotas: ConnectQuotaItem[];
  vetos: ConnectVetoItem[];
  hint: string;
  conclusion: string;
  conclusionIsMet: boolean;
}
