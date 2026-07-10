import {
  ConnectBarItem,
  ConnectLevelData,
  ConnectQuotaItem,
  ConnectRingItem,
  ConnectVetoItem
} from '../../models/ConnectLevel';

// 注入到 connect.linux.do 文档里执行的抽取脚本(纯浏览器 JS,非 ArkTS)。
// 在「升级要求」卡片就绪时把各区块数值抠成 JSON 字符串返回;页面未就绪(SSO 跳转/挑战页)返回空串。
// 运行环境是 Chromium,可用箭头函数与 Array.from,与 .ets 的 ArkTS 限制无关。
export const CONNECT_EXTRACT_SCRIPT: string = `(function(){
  try {
    var card = document.querySelector('.page-content .card') || document.querySelector('.card');
    if (!card || !card.querySelector('.tl3-rings')) { return ''; }
    var txt = function(el, sel){ if(!el) return ''; var n = el.querySelector(sel); return n ? (n.textContent || '').trim() : ''; };
    var numFrom = function(style, key){ if(!style) return 0; var m = style.match(new RegExp('--' + key + ':\\\\s*([0-9.]+)')); return m ? parseFloat(m[1]) : 0; };
    var badgeEl = card.querySelector('.card-header .badge');
    var rings = Array.from(card.querySelectorAll('.tl3-ring')).map(function(r){
      var c = r.querySelector('.tl3-ring-circle');
      var style = c ? (c.getAttribute('style') || '') : '';
      return {
        label: txt(r, '.tl3-ring-label'),
        current: txt(r, '.tl3-ring-current'),
        target: txt(r, '.tl3-ring-target'),
        val: numFrom(style, 'val'),
        max: numFrom(style, 'max'),
        met: !!(c && c.classList.contains('met'))
      };
    });
    var bars = Array.from(card.querySelectorAll('.tl3-bar-item')).map(function(b){
      var nums = b.querySelector('.tl3-bar-nums');
      var fill = b.querySelector('.tl3-bar-fill');
      var style = fill ? (fill.getAttribute('style') || '') : '';
      return {
        label: txt(b, '.tl3-bar-label'),
        nums: nums ? (nums.textContent || '').trim() : '',
        val: numFrom(style, 'val'),
        max: numFrom(style, 'max'),
        met: !!(nums && nums.classList.contains('met'))
      };
    });
    var quotas = Array.from(card.querySelectorAll('.tl3-quota-card')).map(function(qc){
      return {
        label: txt(qc, '.tl3-quota-label'),
        nums: txt(qc, '.tl3-quota-nums'),
        slots: qc.querySelectorAll('.tl3-slot').length,
        used: qc.querySelectorAll('.tl3-slot.used').length,
        met: qc.classList.contains('met')
      };
    });
    var vetos = Array.from(card.querySelectorAll('.tl3-veto-item')).map(function(v){
      var met = v.classList.contains('met');
      var face = v.querySelector(met ? '.tl3-veto-front' : '.tl3-veto-back') || v;
      return {
        label: txt(face, '.tl3-veto-label'),
        desc: txt(face, '.tl3-veto-desc'),
        value: txt(face, '.tl3-veto-value'),
        met: met
      };
    });
    var conc = card.querySelector('.status-unmet, .status-met');
    return JSON.stringify({
      title: txt(card, '.card-title'),
      statusLabel: badgeEl ? (badgeEl.textContent || '').trim() : '',
      statusIsMet: !!(badgeEl && badgeEl.classList.contains('badge-success')),
      subtitle: txt(card, '.card-subtitle'),
      rings: rings,
      bars: bars,
      quotas: quotas,
      vetos: vetos,
      hint: txt(card, '.text-hint'),
      conclusion: conc ? (conc.textContent || '').trim() : '',
      conclusionIsMet: !!(conc && conc.classList.contains('status-met'))
    });
  } catch (e) { return ''; }
})();`;

export class ConnectLevelParser {
  // 把 runJavaScript 的返回值解析成结构化数据。返回 null 表示页面尚未就绪或格式异常(调用方据此重试)。
  // runJavaScript 对「字符串返回值」会再套一层 JSON 编码(带引号转义),故可能需要先解包一次。
  static parse(raw: string): ConnectLevelData | null {
    if (!raw) {
      return null;
    }
    let text: string = raw.trim();
    if (text.length === 0 || text === 'null' || text === 'undefined' || text === '""') {
      return null;
    }
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        text = JSON.parse(text) as string;
      } catch (error) {
        return null;
      }
    }
    text = text.trim();
    if (!text.startsWith('{')) {
      return null;
    }
    let obj: ConnectLevelData;
    try {
      obj = JSON.parse(text) as ConnectLevelData;
    } catch (error) {
      return null;
    }
    if (!obj || !Array.isArray(obj.rings)) {
      return null;
    }
    return ConnectLevelParser.normalize(obj);
  }

  // 逐字段防御性归一:补齐缺失字段、强制数值/布尔类型,避免 DOM 变动导致运行期访问 undefined。
  private static normalize(obj: ConnectLevelData): ConnectLevelData {
    const rings: ConnectRingItem[] = (obj.rings ? obj.rings : []).map((r: ConnectRingItem): ConnectRingItem => {
      return {
        label: r.label ? r.label : '',
        current: r.current ? r.current : '',
        target: r.target ? r.target : '',
        val: Number(r.val) || 0,
        max: Number(r.max) || 0,
        met: r.met === true
      };
    });
    const bars: ConnectBarItem[] = (obj.bars ? obj.bars : []).map((b: ConnectBarItem): ConnectBarItem => {
      return {
        label: b.label ? b.label : '',
        nums: b.nums ? b.nums : '',
        val: Number(b.val) || 0,
        max: Number(b.max) || 0,
        met: b.met === true
      };
    });
    const quotas: ConnectQuotaItem[] = (obj.quotas ? obj.quotas : []).map((q: ConnectQuotaItem): ConnectQuotaItem => {
      return {
        label: q.label ? q.label : '',
        nums: q.nums ? q.nums : '',
        slots: Number(q.slots) || 0,
        used: Number(q.used) || 0,
        met: q.met === true
      };
    });
    const vetos: ConnectVetoItem[] = (obj.vetos ? obj.vetos : []).map((v: ConnectVetoItem): ConnectVetoItem => {
      return {
        label: v.label ? v.label : '',
        desc: v.desc ? v.desc : '',
        value: v.value ? v.value : '',
        met: v.met === true
      };
    });
    return {
      title: obj.title ? obj.title : '信任级别要求',
      statusLabel: obj.statusLabel ? obj.statusLabel : '',
      statusIsMet: obj.statusIsMet === true,
      subtitle: obj.subtitle ? obj.subtitle : '',
      rings: rings,
      bars: bars,
      quotas: quotas,
      vetos: vetos,
      hint: obj.hint ? obj.hint : '',
      conclusion: obj.conclusion ? obj.conclusion : '',
      conclusionIsMet: obj.conclusionIsMet === true
    };
  }
}
