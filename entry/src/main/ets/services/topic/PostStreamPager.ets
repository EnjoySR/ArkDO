import { TopicPost } from '../../models/TopicDetail';

// 帖子流分页纯逻辑:基于详情接口返回的全量楼层 id 流(stream)与已加载楼层做差集分页。
// 全部为无状态静态函数;posts 数组本身保存在页面 @State 里,append 返回新数组由页面赋回以触发刷新。
export class PostStreamPager {
  // 下一页要加载的楼层 id:按 stream 顺序取尚未加载的前 pageSize 个。
  static collectNextIds(stream: number[], posts: TopicPost[], pageSize: number): number[] {
    const loadedIds: Set<number> = PostStreamPager.buildLoadedIdSet(posts);
    const nextIds: number[] = [];
    for (let index: number = 0; index < stream.length && nextIds.length < pageSize; index++) {
      if (!loadedIds.has(stream[index])) {
        nextIds.push(stream[index]);
      }
    }
    return nextIds;
  }

  // 合并新楼层(按 id 去重),返回新数组供页面赋回 @State。
  static append(posts: TopicPost[], newPosts: TopicPost[]): TopicPost[] {
    const loadedIds: Set<number> = PostStreamPager.buildLoadedIdSet(posts);
    const merged: TopicPost[] = posts.slice();
    for (let index: number = 0; index < newPosts.length; index++) {
      const post: TopicPost = newPosts[index];
      if (!loadedIds.has(post.id)) {
        loadedIds.add(post.id);
        merged.push(post);
      }
    }
    return merged;
  }

  // stream 中尚未加载的楼层数(决定"上拉加载更多/没有更多了")。
  static countUnloaded(stream: number[], posts: TopicPost[]): number {
    const loadedIds: Set<number> = PostStreamPager.buildLoadedIdSet(posts);
    let count: number = 0;
    for (let index: number = 0; index < stream.length; index++) {
      if (!loadedIds.has(stream[index])) {
        count++;
      }
    }
    return count;
  }

  static findById(posts: TopicPost[], postId: number): TopicPost | undefined {
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].id === postId) {
        return posts[index];
      }
    }
    return undefined;
  }

  private static buildLoadedIdSet(posts: TopicPost[]): Set<number> {
    const loadedIds: Set<number> = new Set();
    for (let index: number = 0; index < posts.length; index++) {
      loadedIds.add(posts[index].id);
    }
    return loadedIds;
  }
}
