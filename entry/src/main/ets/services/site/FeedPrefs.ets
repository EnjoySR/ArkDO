import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const LOG_TAG: string = '[ArkDO][Feed]';
// 与 DohManager 共用同一个 preferences 库,只是键不同。
const PREF_STORE_NAME: string = 'app_settings';
// 单键存启用且有序的可选入口 key 列表(不含 latest);在数组里=启用,数组顺序=展示顺序。
const PREF_KEY_ENABLED_ORDER: string = 'feed_enabled_order';

/** 内容入口标识:与 Discourse feed 接口一一对应。 */
export enum FeedKey {
  LATEST = 'latest',
  TOP = 'top',
  UNREAD = 'unread',
  NEW = 'new'
}

/** 一个内容入口的展示元数据。requiresLogin 的入口未登录时在抽屉里隐藏。 */
export interface FeedDef {
  key: string;
  label: string;
  requiresLogin: boolean;
}

// 「最新」恒在抽屉首位,常开、不可关不可拖,不入库。
const LATEST_FEED: FeedDef = { key: FeedKey.LATEST, label: '最新', requiresLogin: false };

// 可在设置页勾选启用/排序的内置入口(顺序即设置页未启用区的默认排列)。
const OPTIONAL_FEEDS: FeedDef[] = [
  { key: FeedKey.TOP, label: '热门', requiresLogin: false },
  { key: FeedKey.UNREAD, label: '未读', requiresLogin: true },
  { key: FeedKey.NEW, label: '新主题', requiresLogin: true }
];

/**
 * 集中管理「首页内容入口」配置:preferences 持久化用户在设置页勾选启用的可选入口及其排序。
 * 抽屉顶部按「最新 + 启用入口(有序)」渲染;设置页读写启用列表。
 */
export class FeedPrefs {
  /** 「最新」入口(恒在首位)。 */
  static latestFeed(): FeedDef {
    return LATEST_FEED;
  }

  /** 全部可选入口(未过滤启用状态,供设置页列出)。 */
  static optionalFeeds(): FeedDef[] {
    return OPTIONAL_FEEDS.slice();
  }

  /** 按 key 找入口元数据(含 latest)。 */
  static feedDef(key: string): FeedDef | undefined {
    if (key === FeedKey.LATEST) {
      return LATEST_FEED;
    }
    for (let index: number = 0; index < OPTIONAL_FEEDS.length; index++) {
      if (OPTIONAL_FEEDS[index].key === key) {
        return OPTIONAL_FEEDS[index];
      }
    }
    return undefined;
  }

  private static getStore(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
  }

  /** 读取启用且有序的可选入口 key 列表(不含 latest;非法/未知 key 被剔除)。 */
  static getEnabledKeys(context: common.Context): string[] {
    try {
      const store: preferences.Preferences = FeedPrefs.getStore(context);
      const raw: string = store.getSync(PREF_KEY_ENABLED_ORDER, '') as string;
      if (raw.length === 0) {
        return [];
      }
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const valid: string[] = [];
      for (let index: number = 0; index < parsed.length; index++) {
        const key: Object = parsed[index];
        if (typeof key === 'string' && key !== FeedKey.LATEST && FeedPrefs.feedDef(key) !== undefined &&
          valid.indexOf(key) < 0) {
          valid.push(key);
        }
      }
      return valid;
    } catch (err) {
      Log.e(`${LOG_TAG} read enabled feeds failed: ${JSON.stringify(err)}`);
      return [];
    }
  }

  /** 写入启用且有序的可选入口 key 列表。 */
  static setEnabledKeys(context: common.Context, keys: string[]): void {
    try {
      const store: preferences.Preferences = FeedPrefs.getStore(context);
      store.putSync(PREF_KEY_ENABLED_ORDER, JSON.stringify(keys));
      store.flush();
    } catch (err) {
      Log.e(`${LOG_TAG} write enabled feeds failed: ${JSON.stringify(err)}`);
    }
  }
}
