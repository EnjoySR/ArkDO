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

  // ========== 版块可见性与树 ==========
  // 侧边栏(CategoryDrawer)与发帖分类选择器共用这套,保证两处看到的版块集合与父子层级完全一致。
  // 曾经各写一套(选择器自定义 readRestricted 粗筛 + 扁平列表),导致「未分类」及本是子版块的
  // 公告/悬赏/活动等在选择器里平铺冒出、跟侧边栏对不上——统一收口到这里根治。

  // Discourse 默认的「未分类」版块:不进任何版块列表。slug 与 name 任一命中即算
  // (linux.do 名为「未分类」,slug 可能为空或非标准)。
  static isUncategorized(category: TopicCategory): boolean {
    const slug: string = (category.slug ?? '').trim().toLowerCase();
    if (slug === 'uncategorized') {
      return true;
    }
    const name: string = category.name.trim();
    return name === '未分类' || name.toLowerCase() === 'uncategorized';
  }

  // 顶级版块:无父、且非「未分类」。受限版块不在此过滤(它只影响显示——加锁/半透),由调用方决定。
  static topLevelCategories(categories: TopicCategory[]): TopicCategory[] {
    const result: TopicCategory[] = [];
    for (let index: number = 0; index < categories.length; index++) {
      const category: TopicCategory = categories[index];
      if (category.parentCategoryId === undefined && !CategoryIndex.isUncategorized(category)) {
        result.push(category);
      }
    }
    return result;
  }

  // 某父版块下的全部子版块(子版块不再判「未分类」,与侧边栏 childrenOf 行为一致)。
  static childrenOf(categories: TopicCategory[], parentId: number): TopicCategory[] {
    const result: TopicCategory[] = [];
    for (let index: number = 0; index < categories.length; index++) {
      if (categories[index].parentCategoryId === parentId) {
        result.push(categories[index]);
      }
    }
    return result;
  }

  static hasChildren(categories: TopicCategory[], parentId: number): boolean {
    for (let index: number = 0; index < categories.length; index++) {
      if (categories[index].parentCategoryId === parentId) {
        return true;
      }
    }
    return false;
  }
}
