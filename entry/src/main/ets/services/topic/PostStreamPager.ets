import { TopicPost } from '../../models/TopicDetail';

// 帖子流分页纯逻辑:基于详情接口返回的全量楼层 id 流(stream)与已加载楼层做方向化分页。
// 窗口式加载(从任意楼号进入)下,已加载楼层是 stream 中的一段连续区间,
// 向下取区间之后的 id、向上取区间之前的 id;从头进入时区间是前缀,向下语义与旧版一致。
// 全部为无状态静态函数;楼层数组由 PostDataSource 持有,增删经其通知接口(本类只读扫描)。
export class PostStreamPager {
  // 下一页(向下)要加载的楼层 id:已加载区间最大 stream 下标之后的前 pageSize 个。
  static collectNextIds(stream: number[], posts: TopicPost[], pageSize: number): number[] {
    const loadedIds: Set<number> = PostStreamPager.buildLoadedIdSet(posts);
    const range: number[] = PostStreamPager.loadedStreamRange(stream, loadedIds);
    const nextIds: number[] = [];
    for (let index: number = range[1] + 1; index < stream.length && nextIds.length < pageSize; index++) {
      if (!loadedIds.has(stream[index])) {
        nextIds.push(stream[index]);
      }
    }
    return nextIds;
  }

  // 上一页(向上)要加载的楼层 id:已加载区间最小 stream 下标之前、紧邻的 pageSize 个,保持 stream 升序。
  static collectPrevIds(stream: number[], posts: TopicPost[], pageSize: number): number[] {
    const loadedIds: Set<number> = PostStreamPager.buildLoadedIdSet(posts);
    const range: number[] = PostStreamPager.loadedStreamRange(stream, loadedIds);
    if (range[0] <= 0) {
      return [];
    }
    const fromIndex: number = Math.max(0, range[0] - pageSize);
    const prevIds: number[] = [];
    for (let index: number = fromIndex; index < range[0]; index++) {
      if (!loadedIds.has(stream[index])) {
        prevIds.push(stream[index]);
      }
    }
    return prevIds;
  }

  // 已加载区间之前还有几楼(驱动"加载更早"是否可用)。
  static countEarlier(stream: number[], posts: TopicPost[]): number {
    const loadedIds: Set<number> = PostStreamPager.buildLoadedIdSet(posts);
    const range: number[] = PostStreamPager.loadedStreamRange(stream, loadedIds);
    return Math.max(0, range[0]);
  }

  // 已加载区间之后还有几楼(驱动"上拉加载更多/没有更多了")。
  static countLater(stream: number[], posts: TopicPost[]): number {
    const loadedIds: Set<number> = PostStreamPager.buildLoadedIdSet(posts);
    const range: number[] = PostStreamPager.loadedStreamRange(stream, loadedIds);
    return Math.max(0, stream.length - 1 - range[1]);
  }

  static findById(posts: TopicPost[], postId: number): TopicPost | undefined {
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].id === postId) {
        return posts[index];
      }
    }
    return undefined;
  }

  // 精确按楼号找已加载楼层下标;未加载返回 -1。
  static findIndexByPostNumber(posts: TopicPost[], postNumber: number): number {
    for (let index: number = 0; index < posts.length; index++) {
      if (posts[index].postNumber === postNumber) {
        return index;
      }
    }
    return -1;
  }

  // 已加载楼层在 stream 中占据的下标区间 [minIndex, maxIndex]。
  // 无已加载楼层(或均不在 stream 中,如刚发表的新回复)时返回 [-1, -1]:
  // 此时"之后"从头取、"之前"为空,与从零加载的语义一致。
  private static loadedStreamRange(stream: number[], loadedIds: Set<number>): number[] {
    let minIndex: number = -1;
    let maxIndex: number = -1;
    for (let index: number = 0; index < stream.length; index++) {
      if (loadedIds.has(stream[index])) {
        if (minIndex < 0) {
          minIndex = index;
        }
        maxIndex = index;
      }
    }
    return [minIndex, maxIndex];
  }

  private static buildLoadedIdSet(posts: TopicPost[]): Set<number> {
    const loadedIds: Set<number> = new Set();
    for (let index: number = 0; index < posts.length; index++) {
      loadedIds.add(posts[index].id);
    }
    return loadedIds;
  }
}
