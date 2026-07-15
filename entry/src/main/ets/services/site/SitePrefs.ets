import { Log } from '../logging/Log';
import { SiteIconStore } from './SiteIconStore';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][Site]';
// 与 DohManager/FeedPrefs 共用同一个 preferences 库,只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
// 单键存全量站点(JSON 数组)。约定:已显示站点在前、未显示在后,数组顺序即抽屉展示顺序。
const PREF_KEY_SITES: string = 'user_sites';
// 抽屉「我的站点」区总开关。默认开:新用户拉开抽屉就能看见入口,否则功能无从发现。
const PREF_KEY_ENTRY_ENABLED: string = 'sites_entry_enabled';

/**
 * 用户自行添加的站点。id 只用于列表 key 与增删定位,不展示。
 * showInDrawer 关闭的站点不进抽屉,仍可从站点管理页打开(收藏但不置顶)。
 */
export interface SiteDef {
  id: string;
  name: string;
  url: string;
  showInDrawer: boolean;
  // 本地缓存的 favicon uri(file://...);空=还没抓到,渲染时回退默认图标。
  // 由 getSites 查文件系统填充,不吃持久化字段——文件才是唯一事实来源。
  iconUri: string;
}

/**
 * 用户站点的持久化读写。与 FeedPrefs 同款职责边界:本类只管存取与校验,
 * 增删改排序的数组组装在站点管理页里做,写回时整体 setSites。
 *
 * 不预置任何站点——站点全部由用户自己添加,App 只做容器。
 */
export class SitePrefs {
  private static getStore(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
  }

  /** 抽屉「我的站点」区是否显示(设置页开关,默认开)。 */
  static isEntryEnabled(context: common.Context): boolean {
    try {
      const store: preferences.Preferences = SitePrefs.getStore(context);
      return store.getSync(PREF_KEY_ENTRY_ENABLED, true) as boolean;
    } catch (err) {
      Log.e(`${LOG_TAG} read entry flag failed: ${JSON.stringify(err)}`);
      return true;
    }
  }

  static setEntryEnabled(context: common.Context, enabled: boolean): void {
    try {
      const store: preferences.Preferences = SitePrefs.getStore(context);
      store.putSync(PREF_KEY_ENTRY_ENABLED, enabled);
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} write entry flag failed: ${JSON.stringify(err)}`);
    }
  }

  /** 读全量站点(有序;非法项与重复 id 被剔除)。 */
  static getSites(context: common.Context): SiteDef[] {
    try {
      const store: preferences.Preferences = SitePrefs.getStore(context);
      const raw: string = store.getSync(PREF_KEY_SITES, '') as string;
      if (raw.length === 0) {
        return [];
      }
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const valid: SiteDef[] = [];
      for (let index: number = 0; index < parsed.length; index++) {
        const site: SiteDef | undefined = SitePrefs.parseSite(parsed[index] as Object);
        if (site && !SitePrefs.containsId(valid, site.id)) {
          // 图标现查现填:favicon 由 WEB 页在用户打开站点时异步落盘,存进 JSON 会立刻过期。
          site.iconUri = SiteIconStore.uriOf(context, site.id);
          valid.push(site);
        }
      }
      return valid;
    } catch (err) {
      Log.e(`${LOG_TAG} read sites failed: ${JSON.stringify(err)}`);
      return [];
    }
  }

  /** 写全量站点。调用方须保证「已显示在前、未显示在后」,数组顺序即抽屉顺序。 */
  static setSites(context: common.Context, sites: SiteDef[]): void {
    try {
      const store: preferences.Preferences = SitePrefs.getStore(context);
      store.putSync(PREF_KEY_SITES, JSON.stringify(sites));
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} write sites failed: ${JSON.stringify(err)}`);
    }
  }

  /** 抽屉要渲染的站点:入口开关开 + 站点自身 showInDrawer,按存储顺序。 */
  static drawerSites(context: common.Context): SiteDef[] {
    if (!SitePrefs.isEntryEnabled(context)) {
      return [];
    }
    const all: SiteDef[] = SitePrefs.getSites(context);
    const result: SiteDef[] = [];
    for (let index: number = 0; index < all.length; index++) {
      if (all[index].showInDrawer) {
        result.push(all[index]);
      }
    }
    return result;
  }

  /** 新站点 id。时间戳 + 随机后缀:同一毫秒内连加两个站点也不撞。 */
  static newId(): string {
    const random: number = Math.floor(Math.random() * 100000);
    return `s${Date.now()}${random}`;
  }

  // ==================== URL 处理 ====================

  /** 补全裸域名为 https:// 并去首尾空白。从论坛复制来的多是全 URL,手输的多是裸域名。 */
  static normalizeUrl(input: string): string {
    const trimmed: string = input.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const lower: string = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    return `https://${trimmed}`;
  }

  /** 粗校验:必须 http(s) 且 host 带点。挡空输入与明显笔误,不做严格 RFC 解析。 */
  static isValidUrl(url: string): boolean {
    const lower: string = url.trim().toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    const host: string = SitePrefs.hostOf(url);
    return host.length > 0 && host.indexOf('.') > 0;
  }

  /** 取 host(不含协议/路径/端口);解析不出时返回空串。 */
  static hostOf(url: string): string {
    const trimmed: string = url.trim();
    const schemeEnd: number = trimmed.indexOf('://');
    if (schemeEnd < 0) {
      return '';
    }
    let rest: string = trimmed.substring(schemeEnd + 3);
    const slash: number = rest.indexOf('/');
    if (slash >= 0) {
      rest = rest.substring(0, slash);
    }
    const colon: number = rest.indexOf(':');
    if (colon >= 0) {
      rest = rest.substring(0, colon);
    }
    return rest;
  }

  // ==================== 内部 ====================

  private static containsId(sites: SiteDef[], id: string): boolean {
    for (let index: number = 0; index < sites.length; index++) {
      if (sites[index].id === id) {
        return true;
      }
    }
    return false;
  }

  // 逐字段校验:id/url 不合法即整条丢弃(宁可少一个站点,不让脏数据渲染崩页面);name 空则用域名兜底。
  private static parseSite(raw: Object): SiteDef | undefined {
    if (!raw) {
      return undefined;
    }
    const candidate: SiteDef = raw as SiteDef;
    if (typeof candidate.id !== 'string' || candidate.id.length === 0) {
      return undefined;
    }
    if (typeof candidate.url !== 'string' || !SitePrefs.isValidUrl(candidate.url)) {
      return undefined;
    }
    const name: string = typeof candidate.name === 'string' && candidate.name.length > 0
      ? candidate.name
      : SitePrefs.hostOf(candidate.url);
    // iconUri 一律留空,由 getSites 查文件系统回填;JSON 里存的旧值(若有)在此被丢弃。
    return {
      id: candidate.id,
      name: name,
      url: candidate.url,
      showInDrawer: candidate.showInDrawer === true,
      iconUri: ''
    };
  }
}
