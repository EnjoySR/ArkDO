import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { webview } from '@kit.ArkWeb';

const LOG_TAG: string = '[ArkDO][Doh]';
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_SERVERS: string = 'doh_servers';
const PREF_KEY_ACTIVE_ID: string = 'doh_active_id';
const PREF_KEY_ENABLED: string = 'doh_enabled';
const PREF_KEY_MODE: string = 'doh_mode';
const PREF_KEY_ID_SEQ: string = 'doh_id_seq';
// 一次性迁移标记:把早期版本种下的 auto 翻成 secure_only(AUTO 实测不走 DoH)。只跑一次,
// 之后用户仍可自行改回 AUTO。
const PREF_KEY_MIGRATED_SECURE: string = 'doh_migrated_secure_v1';

/**
 * 内置 DoH:不可删除,首次启动种子数据,也是删除 active 后的兜底。
 * 两条内置项都恒在列表中(缺失自动补回):edge 为默认激活项(装机即用),arkdo 为备用预设。
 */
export const DOH_EDGE_ID: string = 'builtin-edge';
const DOH_EDGE_NAME: string = 'Linux.do 优选';
const DOH_EDGE_URL: string = 'https://edge.47258.xyz/linuxdo';

// 保留原 id 兼容旧安装(旧版持久化里 active/列表都引用它);现降为第二预设。
export const DOH_BUILTIN_ID: string = 'builtin-default';
const DOH_BUILTIN_NAME: string = '系统默认';
const DOH_BUILTIN_URL: string = 'https://arkdo.ddd.oaifree.com/query-dns';

/** DoH 解析模式:AUTO 失败回退系统 DNS(稳妥);SECURE_ONLY 只用 DoH,失败即加载失败。 */
export enum DohResolveMode {
  AUTO = 'auto',
  SECURE_ONLY = 'secure_only'
}

/** 一条 DoH 服务器预设。latencyMs 仅内存态(测速结果),不参与持久化。 */
export interface DohServer {
  id: string;
  name: string;
  url: string;
  builtin: boolean;
}

/**
 * 集中管理 DoH 配置:preferences 持久化服务器列表/当前选择/开关/模式,并把当前选择
 * 通过 webview.WebviewController.setHttpDns 下发到 ArkWeb 引擎(全 app 所有 Web 组件生效)。
 *
 * setHttpDns 是全局静态方法,可在 initializeWebEngine 之前调用并被引擎捕获,因此在
 * EntryAbility.onCreate 里 init 一次即可保证宿主 webview 首次加载 linux.do 时 DoH 已就位。
 */
export class DohManager {
  private static getStore(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
  }

  /** 应用启动时调用:首次无记录则写入内置默认并选中;随后把当前选择下发引擎。 */
  static init(context: common.Context): void {
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      const rawServers: string = store.getSync(PREF_KEY_SERVERS, '') as string;
      if (rawServers.length === 0) {
        // 首次启动:种子两条内置项(edge 置顶为默认激活 + arkdo 备用)+ 默认开启。
        const seed: DohServer[] = DohManager.builtinServers();
        store.putSync(PREF_KEY_SERVERS, JSON.stringify(seed));
        store.putSync(PREF_KEY_ACTIVE_ID, DOH_EDGE_ID);
        store.putSync(PREF_KEY_ENABLED, true);
        // 防污染用途默认 SECURE_ONLY:AUTO(Chromium AUTOMATIC)对自定义 DoH 保守,实测
        // 仍以 useHttpDns:0 走污染系统 DNS;SECURE_ONLY 强制所有解析走 DoH。
        store.putSync(PREF_KEY_MODE, DohResolveMode.SECURE_ONLY);
        store.putSync(PREF_KEY_MIGRATED_SECURE, true);
        store.flush();
      }
      // 一次性迁移:早期安装种下的 auto 翻成 secure_only(AUTO 不走 DoH),仅执行一次。
      const migrated: boolean = store.getSync(PREF_KEY_MIGRATED_SECURE, false) as boolean;
      if (!migrated) {
        store.putSync(PREF_KEY_MODE, DohResolveMode.SECURE_ONLY);
        store.putSync(PREF_KEY_MIGRATED_SECURE, true);
        store.flush();
        Log.i(`${LOG_TAG} migrated doh_mode -> secure_only`);
      }
    } catch (err) {
      Log.e(`${LOG_TAG} init store failed: ${JSON.stringify(err)}`);
    }
    DohManager.applyActive(context);
  }

  /** 读取全部服务器预设(内置项恒在列表首位)。 */
  static getServers(context: common.Context): DohServer[] {
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      const raw: string = store.getSync(PREF_KEY_SERVERS, '') as string;
      const list: DohServer[] = DohManager.parseServers(raw);
      return list.length > 0 ? list : DohManager.builtinServers();
    } catch (err) {
      Log.e(`${LOG_TAG} read servers failed: ${JSON.stringify(err)}`);
      return DohManager.builtinServers();
    }
  }

  static getActiveId(context: common.Context): string {
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      return store.getSync(PREF_KEY_ACTIVE_ID, DOH_EDGE_ID) as string;
    } catch (err) {
      return DOH_EDGE_ID;
    }
  }

  static isEnabled(context: common.Context): boolean {
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      return store.getSync(PREF_KEY_ENABLED, true) as boolean;
    } catch (err) {
      return true;
    }
  }

  static getMode(context: common.Context): DohResolveMode {
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      const raw: string = store.getSync(PREF_KEY_MODE, DohResolveMode.SECURE_ONLY) as string;
      return raw === DohResolveMode.AUTO ? DohResolveMode.AUTO : DohResolveMode.SECURE_ONLY;
    } catch (err) {
      return DohResolveMode.SECURE_ONLY;
    }
  }

  /** 便捷:返回当前选中的服务器(找不到则回退内置默认)。 */
  static getActiveServer(context: common.Context): DohServer {
    const activeId: string = DohManager.getActiveId(context);
    const servers: DohServer[] = DohManager.getServers(context);
    for (const server of servers) {
      if (server.id === activeId) {
        return server;
      }
    }
    return servers[0];
  }

  static setEnabled(context: common.Context, enabled: boolean): void {
    DohManager.putBool(context, PREF_KEY_ENABLED, enabled);
    DohManager.applyActive(context);
  }

  static setActive(context: common.Context, id: string): void {
    DohManager.putString(context, PREF_KEY_ACTIVE_ID, id);
    DohManager.applyActive(context);
  }

  static setMode(context: common.Context, mode: DohResolveMode): void {
    DohManager.putString(context, PREF_KEY_MODE, mode);
    DohManager.applyActive(context);
  }

  /** 新增自定义服务器;返回新建项(id 由持久化自增计数器生成,避免依赖时间/随机)。 */
  static addServer(context: common.Context, name: string, url: string): DohServer | undefined {
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      const seq: number = (store.getSync(PREF_KEY_ID_SEQ, 0) as number) + 1;
      const server: DohServer = {
        id: `custom-${seq}`,
        name: name,
        url: url,
        builtin: false
      };
      const servers: DohServer[] = DohManager.getServers(context);
      servers.push(server);
      store.putSync(PREF_KEY_ID_SEQ, seq);
      store.putSync(PREF_KEY_SERVERS, JSON.stringify(servers));
      store.flush();
      return server;
    } catch (err) {
      Log.e(`${LOG_TAG} add server failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  /** 删除自定义服务器;内置项拒删。若删的是当前选中项,回退到内置默认并重新下发。 */
  static removeServer(context: common.Context, id: string): void {
    if (id === DOH_BUILTIN_ID || id === DOH_EDGE_ID) {
      return;
    }
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      const servers: DohServer[] = DohManager.getServers(context).filter((s: DohServer) => s.id !== id);
      store.putSync(PREF_KEY_SERVERS, JSON.stringify(servers));
      if (DohManager.getActiveId(context) === id) {
        store.putSync(PREF_KEY_ACTIVE_ID, DOH_EDGE_ID);
      }
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} remove server failed: ${JSON.stringify(err)}`);
    }
    DohManager.applyActive(context);
  }

  /** 把当前选择下发到 ArkWeb 引擎:未启用或无选中则撤销(走系统 DNS)。 */
  static applyActive(context: common.Context): void {
    const enabled: boolean = DohManager.isEnabled(context);
    const active: DohServer = DohManager.getActiveServer(context);
    try {
      if (!enabled || active.url.length === 0) {
        webview.WebviewController.setHttpDns(webview.SecureDnsMode.OFF, '');
        Log.i(`${LOG_TAG} setHttpDns OFF`);
        return;
      }
      const mode: DohResolveMode = DohManager.getMode(context);
      const secureMode: webview.SecureDnsMode =
        mode === DohResolveMode.SECURE_ONLY ? webview.SecureDnsMode.SECURE_ONLY : webview.SecureDnsMode.AUTO;
      webview.WebviewController.setHttpDns(secureMode, active.url);
      Log.i(`${LOG_TAG} setHttpDns mode=${mode} name=${active.name}`);
    } catch (err) {
      Log.e(`${LOG_TAG} setHttpDns failed: ${JSON.stringify(err)}`);
    }
  }

  // ==================== 私有辅助 ====================

  private static edgeServer(): DohServer {
    return {
      id: DOH_EDGE_ID,
      name: DOH_EDGE_NAME,
      url: DOH_EDGE_URL,
      builtin: true
    };
  }

  private static builtinServer(): DohServer {
    return {
      id: DOH_BUILTIN_ID,
      name: DOH_BUILTIN_NAME,
      url: DOH_BUILTIN_URL,
      builtin: true
    };
  }

  // 两条内置项,edge 置顶为默认激活项、arkdo 备用。种子/兜底统一走这里。
  private static builtinServers(): DohServer[] {
    return [DohManager.edgeServer(), DohManager.builtinServer()];
  }

  // 解析持久化 JSON:逐项校验字段类型,内置项缺失时补回并置顶,防止被误删/篡改后没有默认项。
  private static parseServers(raw: string): DohServer[] {
    if (raw.length === 0) {
      return [];
    }
    const result: DohServer[] = [];
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return DohManager.builtinServers();
      }
      const arr: object[] = parsed as object[];
      for (const item of arr) {
        const candidate: DohServer = item as DohServer;
        if (typeof candidate.id === 'string' && typeof candidate.name === 'string' &&
          typeof candidate.url === 'string' && typeof candidate.builtin === 'boolean') {
          result.push({
            id: candidate.id,
            name: candidate.name,
            url: candidate.url,
            builtin: candidate.builtin
          });
        }
      }
    } catch (err) {
      Log.e(`${LOG_TAG} parse servers failed: ${JSON.stringify(err)}`);
      return DohManager.builtinServers();
    }
    // 补回缺失的内置项:先补 arkdo 置顶,再补 edge 置顶,最终顺序 edge → arkdo → 其它。
    // 对旧安装(仅有 arkdo)升级后即出现 edge 预设;对新装二者都已在 seed 里,这里是无操作。
    const hasBuiltin: boolean = result.some((s: DohServer) => s.id === DOH_BUILTIN_ID);
    if (!hasBuiltin) {
      result.unshift(DohManager.builtinServer());
    }
    const hasEdge: boolean = result.some((s: DohServer) => s.id === DOH_EDGE_ID);
    if (!hasEdge) {
      result.unshift(DohManager.edgeServer());
    }
    return result;
  }

  private static putString(context: common.Context, key: string, value: string): void {
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      store.putSync(key, value);
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} persist ${key} failed: ${JSON.stringify(err)}`);
    }
  }

  private static putBool(context: common.Context, key: string, value: boolean): void {
    try {
      const store: preferences.Preferences = DohManager.getStore(context);
      store.putSync(key, value);
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} persist ${key} failed: ${JSON.stringify(err)}`);
    }
  }
}
