import { TopicPost } from '../../models/TopicDetail';
import { PostStreamPager } from './PostStreamPager';

// 楼层懒加载数据源:详情页 LazyForEach 的唯一真源。
// 所有增删必须经本类方法发精准通知(头插 ADD@0 / 尾插 ADD@末尾 / 整体 reload)——
// 这是 List.maintainVisibleContentPosition 头插不跳动的前提;换整数组引用不会被框架补偿。
// 楼层对象仍是 @Observed 的 TopicPost,字段级变更(read/reactions 等)走 @ObjectLink,不经本类。
export class PostDataSource implements IDataSource {
  private posts: TopicPost[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.posts.length;
  }

  getData(index: number): TopicPost {
    return this.posts[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // 内部数组引用(只读约定):供 ReadController / PostStreamPager 线性扫描,不得直接增删。
  getAll(): TopicPost[] {
    return this.posts;
  }

  // 整体替换(首屏加载/按楼号重开窗口),全量重建列表。
  reset(posts: TopicPost[]): void {
    this.posts = posts.slice();
    for (let index: number = 0; index < this.listeners.length; index++) {
      this.listeners[index].onDataReloaded();
    }
  }

  // 按 id 去重尾插(向下分页/发表新回复),返回实际新增条数。
  appendPosts(newPosts: TopicPost[]): number {
    const fresh: TopicPost[] = this.collectFresh(newPosts);
    if (fresh.length === 0) {
      return 0;
    }
    const insertAt: number = this.posts.length;
    this.posts = this.posts.concat(fresh);
    this.notifyAdd(insertAt, fresh.length);
    return fresh.length;
  }

  // 按 id 去重、按楼号升序头插(向上补更早楼层),返回实际新增条数。
  // posts.json 按请求 id 顺序返回,这里排序兜底,保证头部段仍按楼号递增。
  prependPosts(newPosts: TopicPost[]): number {
    const fresh: TopicPost[] = this.collectFresh(newPosts);
    if (fresh.length === 0) {
      return 0;
    }
    fresh.sort((a: TopicPost, b: TopicPost) => a.postNumber - b.postNumber);
    this.posts = fresh.concat(this.posts);
    this.notifyAdd(0, fresh.length);
    return fresh.length;
  }

  findIndexByPostNumber(postNumber: number): number {
    return PostStreamPager.findIndexByPostNumber(this.posts, postNumber);
  }

  // 首个楼号 >= 目标的下标(容忍目标楼被删形成的空洞);全部小于目标时返回 -1。
  findIndexAtOrAfterPostNumber(postNumber: number): number {
    for (let index: number = 0; index < this.posts.length; index++) {
      if (this.posts[index].postNumber >= postNumber) {
        return index;
      }
    }
    return -1;
  }

  private collectFresh(newPosts: TopicPost[]): TopicPost[] {
    const loadedIds: Set<number> = new Set();
    for (let index: number = 0; index < this.posts.length; index++) {
      loadedIds.add(this.posts[index].id);
    }
    const fresh: TopicPost[] = [];
    for (let index: number = 0; index < newPosts.length; index++) {
      const post: TopicPost = newPosts[index];
      if (!loadedIds.has(post.id)) {
        loadedIds.add(post.id);
        fresh.push(post);
      }
    }
    return fresh;
  }

  private notifyAdd(index: number, count: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDatasetChange([{ type: DataOperationType.ADD, index: index, count: count }]);
    }
  }
}
