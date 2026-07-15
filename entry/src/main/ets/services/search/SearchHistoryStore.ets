import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][Search]';
// 与 FeedPrefs / DohManager 共用同一个 preferences 库,只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
// 单键存最近搜索词(JSON 字符串数组,最新在前)。
const PREF_KEY_HISTORY: string = 'search_history';
// 历史封顶条数:超出丢弃最旧的。
const MAX_HISTORY: number = 10;

/**
 * 本地搜索历史:preferences 持久化最近搜索词(去重、最新在前、封顶 10 条)。
 * 空态展示、点击回填搜索框用;纯本地,不涉网。
 */
export class SearchHistoryStore {
  private static getStore(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
  }

  /** 读取历史(最新在前);解析失败/无值返回空数组。 */
  static load(context: common.Context): string[] {
    try {
      const store: preferences.Preferences = SearchHistoryStore.getStore(context);
      const raw: string = store.getSync(PREF_KEY_HISTORY, '') as string;
      if (raw.length === 0) {
        return [];
      }
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const valid: string[] = [];
      for (let index: number = 0; index < parsed.length; index++) {
        const term: Object = parsed[index];
        if (typeof term === 'string' && term.length > 0 && valid.indexOf(term) < 0) {
          valid.push(term);
        }
      }
      return valid;
    } catch (err) {
      Log.e(`${LOG_TAG} read search history failed: ${JSON.stringify(err)}`);
      return [];
    }
  }

  /** 记一次搜索:去重后置顶、封顶 MAX_HISTORY,返回更新后的列表(供 UI 直接用)。 */
  static add(context: common.Context, term: string): string[] {
    const trimmed: string = term.trim();
    if (trimmed.length === 0) {
      return SearchHistoryStore.load(context);
    }
    const existing: string[] = SearchHistoryStore.load(context);
    const next: string[] = [trimmed];
    for (let index: number = 0; index < existing.length && next.length < MAX_HISTORY; index++) {
      if (existing[index] !== trimmed) {
        next.push(existing[index]);
      }
    }
    SearchHistoryStore.persist(context, next);
    return next;
  }

  /** 删一条历史,返回更新后的列表。 */
  static remove(context: common.Context, term: string): string[] {
    const existing: string[] = SearchHistoryStore.load(context);
    const next: string[] = [];
    for (let index: number = 0; index < existing.length; index++) {
      if (existing[index] !== term) {
        next.push(existing[index]);
      }
    }
    SearchHistoryStore.persist(context, next);
    return next;
  }

  /** 清空历史。 */
  static clear(context: common.Context): void {
    SearchHistoryStore.persist(context, []);
  }

  private static persist(context: common.Context, terms: string[]): void {
    try {
      const store: preferences.Preferences = SearchHistoryStore.getStore(context);
      store.putSync(PREF_KEY_HISTORY, JSON.stringify(terms));
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} write search history failed: ${JSON.stringify(err)}`);
    }
  }
}
