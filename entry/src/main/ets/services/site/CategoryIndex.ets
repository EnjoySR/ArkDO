import { TopicCategory } from '../../models/Topic';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { SiteMetadata, SiteService } from './SiteService';

// 站点分类索引:封装 /site.json 分类的按需加载与按 id 查找,供列表页/详情页共用。
// 分类数组本身仍保存在页面 @State 里(驱动重渲染):加载成功返回新数组,由页面赋回 @State;
// 查找是纯函数,静态调用,不在本类里保存状态。
export class CategoryIndex {
  private isLoading: boolean = false;

  // 按需加载分类:未就绪/正在加载/页面已有数据(alreadyLoaded)时返回 null 表示无需更新;
  // 失败也返回 null(不打断页面主流程,下次调用再试)。
  async loadIfNeeded(
    bridge: JsonNetworkClient,
    ready: boolean,
    alreadyLoaded: boolean,
    logTag: string
  ): Promise<TopicCategory[] | null> {
    if (!ready || this.isLoading || alreadyLoaded) {
      return null;
    }

    this.isLoading = true;
    const result: NetworkResult<SiteMetadata> = await new SiteService(bridge).getSiteMetadata();
    this.isLoading = false;

    if (result.success && result.data) {
      console.info(`${logTag} site metadata loaded categories=${result.data.categories.length}`);
      return result.data.categories;
    }
    console.info(`${logTag} site metadata skipped status=${result.statusCode}`);
    return null;
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
