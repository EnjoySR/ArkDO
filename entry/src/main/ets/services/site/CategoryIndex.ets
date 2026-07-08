import { Log } from '../logging/Log';
import { TopicCategory } from '../../models/Topic';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { SiteMetadata, SiteService } from './SiteService';

// 站点分类索引:封装 /site.json 分类的按需加载与按 id 查找,供列表页/详情页/个人中心共用。
// 分类数组本身仍保存在页面 @State 里(驱动重渲染):加载成功返回新数组,由页面赋回 @State;
// 查找是纯函数,静态调用,不在实例里保存状态。
//
// 分类全站通用且几乎不变,因此结果缓存在应用级静态字段里:全 App 生命周期只请求一次
// /site.json(该响应体积不小),后续页面进入直接命中缓存;并发首载共享同一个 in-flight
// Promise,避免冷启动时首页/个人中心同时各拉一份。
export class CategoryIndex {
  private static cachedCategories: TopicCategory[] | null = null;
  private static inflight: Promise<TopicCategory[] | null> | null = null;

  // 按需加载分类:未就绪/页面已有数据(alreadyLoaded)时返回 null 表示无需更新;
  // 失败也返回 null(不打断页面主流程,下次调用再试)。
  async loadIfNeeded(
    bridge: JsonNetworkClient,
    ready: boolean,
    alreadyLoaded: boolean,
    logTag: string
  ): Promise<TopicCategory[] | null> {
    if (!ready || alreadyLoaded) {
      return null;
    }

    if (CategoryIndex.cachedCategories) {
      return CategoryIndex.cachedCategories;
    }

    if (!CategoryIndex.inflight) {
      CategoryIndex.inflight = CategoryIndex.fetchCategories(bridge, logTag);
    }
    const loaded: TopicCategory[] | null = await CategoryIndex.inflight;
    CategoryIndex.inflight = null;
    return loaded;
  }

  private static async fetchCategories(bridge: JsonNetworkClient, logTag: string): Promise<TopicCategory[] | null> {
    const result: NetworkResult<SiteMetadata> = await new SiteService(bridge).getSiteMetadata();
    if (result.success && result.data) {
      CategoryIndex.cachedCategories = result.data.categories;
      Log.i(`${logTag} site metadata loaded categories=${result.data.categories.length}`);
      return CategoryIndex.cachedCategories;
    }
    Log.i(`${logTag} site metadata skipped status=${result.statusCode}`);
    return null;
  }

  // 仅供单测复位静态缓存。
  static resetForTest(): void {
    CategoryIndex.cachedCategories = null;
    CategoryIndex.inflight = null;
  }

  static find(categories: TopicCategory[], categoryId?: number): TopicCategory | undefined {
    if (!categoryId || categories.length === 0) {
      return undefined;
    }
    for (let index: number = 0; index < categories.length; index++) {
      if (categories[index].id === categoryId) {
        return categories[index];
      }
    }
    return undefined;
  }

  static findParent(categories: TopicCategory[], categoryId?: number): TopicCategory | undefined {
    const category: TopicCategory | undefined = CategoryIndex.find(categories, categoryId);
    if (!category || !category.parentCategoryId) {
      return undefined;
    }
    return CategoryIndex.find(categories, category.parentCategoryId);
  }
}
