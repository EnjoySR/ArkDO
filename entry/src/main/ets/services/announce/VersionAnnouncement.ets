import { Log } from '../logging/Log';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';

// 诊断关键字:hilog / DevEco Log 里搜 ANNOUNCE_DIAG 即可看到公告全链路日志。
const LOG_TAG: string = '[ArkDO][ANNOUNCE_DIAG]';

// 版本公告帖:你能一直回复的那个帖。每个版本在此帖发一条回复,开头写 [v<versionCode>],
// 应用启动时用当前 versionCode 匹配对应那条弹出。换帖只改这里。
const ANNOUNCE_TOPIC_ID: number = 2590051;
// 只取你本人的回复(帖子里别人插楼不干扰),对应 URL 的 username_filters。
const ANNOUNCE_USERNAME: string = 'joeyyin';
// 从帖尾往前最多「补拉」多少条未加载的楼找匹配。首屏已返回的楼(前 20,多为较旧的版本公告)
// 会先被免费扫一遍;这个上限只约束帖尾那些要单独补拉的新楼,避免帖子很大时发太多请求。
const MAX_TAIL_FETCH: number = 15;

// —— Discourse 原始响应里我们用到的字段(其余忽略)——
interface RawPost {
  id: number;
  cooked?: string;
  post_number?: number;
}

interface RawPostStream {
  posts?: RawPost[];
  // 该帖(经 username_filters 过滤后)全部楼层 id 的完整有序列表,不分页——
  // 这是"从后往匹配"的依据:posts 默认只含前 20 楼,最新的公告要靠 stream 末尾的 id 单独补拉。
  stream?: number[];
}

interface RawTopic {
  post_stream?: RawPostStream;
}

export interface VersionAnnouncement {
  postNumber: number;
  // 已剥掉 [vXXXX] 标记的正文 HTML,直接喂 PostRichContent。
  cookedHtml: string;
}

// 拉取「与当前 versionCode 匹配的版本公告」。任何失败/找不到都返回 null(即不弹窗),不抛错。
export class VersionAnnouncementService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  async fetchForVersion(versionCode: number): Promise<VersionAnnouncement | null> {
    try {
      const path: string = `/t/${ANNOUNCE_TOPIC_ID}.json?username_filters=${ANNOUNCE_USERNAME}`;
      Log.i(`${LOG_TAG} 开始拉公告 versionCode=${versionCode} 目标标记=[v${versionCode}] path=${path}`);
      const res: NetworkResult<string> = await this.bridge.getJson(path);
      Log.i(`${LOG_TAG} 响应 success=${res.success} status=${res.statusCode} challenge=${res.challengeState} 体长度=${res.data ? res.data.length : 0}`);
      if (!res.success || res.data === undefined) {
        Log.w(`${LOG_TAG} 拉公告帖失败 status=${res.statusCode}`);
        return null;
      }

      const topic: RawTopic = JSON.parse(res.data) as RawTopic;
      const stream: number[] = topic.post_stream?.stream ?? [];
      const loaded: RawPost[] = topic.post_stream?.posts ?? [];
      Log.i(`${LOG_TAG} stream 楼层数=${stream.length} 首屏已加载楼=${loaded.length} stream=${JSON.stringify(stream)}`);
      if (stream.length === 0) {
        Log.w(`${LOG_TAG} stream 为空——可能 username_filters 没匹配到你的回复,或响应结构异常`);
        return null;
      }

      // 第 1 遍:扫首屏已返回的楼(免费,通常含较旧的版本公告),从新到旧。
      const loadedIds: Set<number> = new Set();
      for (let i: number = loaded.length - 1; i >= 0; i--) {
        const post: RawPost = loaded[i];
        loadedIds.add(post.id);
        const found: VersionAnnouncement | null = this.tryMatch(post, versionCode, '首屏');
        if (found) {
          return found;
        }
      }

      // 第 2 遍:从 stream 末尾往前,补拉「不在首屏」的新楼(含最新的版本公告),补拉次数封顶。
      let fetched: number = 0;
      for (let i: number = stream.length - 1; i >= 0 && fetched < MAX_TAIL_FETCH; i--) {
        const id: number = stream[i];
        if (loadedIds.has(id)) {
          continue;
        }
        fetched++;
        const post: RawPost | undefined = await this.fetchPostById(id);
        if (!post) {
          continue;
        }
        const found: VersionAnnouncement | null = this.tryMatch(post, versionCode, '补拉');
        if (found) {
          return found;
        }
      }

      Log.w(`${LOG_TAG} 未找到 [v${versionCode}] 对应的公告(扫首屏 ${loaded.length} 楼 + 补拉 ${fetched} 楼)`);
      return null;
    } catch (error) {
      Log.e(`${LOG_TAG} 拉公告异常: ${JSON.stringify(error)}`);
      return null;
    }
  }

  // 按单个 id 补拉一楼(stream 末尾那条通常不在首页返回的前 20 楼里)。
  private async fetchPostById(id: number): Promise<RawPost | undefined> {
    const path: string = `/t/${ANNOUNCE_TOPIC_ID}/posts.json?post_ids%5B%5D=${id}&include_suggested=false`;
    const res: NetworkResult<string> = await this.bridge.getJson(path);
    if (!res.success || res.data === undefined) {
      return undefined;
    }
    const parsed: RawTopic = JSON.parse(res.data) as RawTopic;
    const posts: RawPost[] = parsed.post_stream?.posts ?? [];
    return posts.length > 0 ? posts[0] : undefined;
  }

  // 单楼匹配:命中当前版本标记则剥离标记返回可展示正文,否则返回 null。source 仅用于日志。
  private tryMatch(post: RawPost, versionCode: number, source: string): VersionAnnouncement | null {
    // 主帖(楼层1)是总更新日志,含各版本号纯文本,不作为版本公告来源,直接跳过。
    if (post.post_number === 1) {
      return null;
    }
    const cooked: string = post.cooked ?? '';
    const hit: boolean = this.matchesMarker(cooked, versionCode);
    Log.i(`${LOG_TAG} 扫 id=${post.id} 楼号=${post.post_number ?? -1} 来源=${source} 命中[v${versionCode}]=${hit} cooked前120=${cooked.substring(0, 120)}`);
    if (!hit) {
      return null;
    }
    // 保留完整正文(含 [vXXXX] 标记)直接展示,不剥离——版本号就当作内容里的一部分给用户看。
    if (cooked.trim().length === 0) {
      return null;
    }
    Log.i(`${LOG_TAG} 命中并返回:楼号=${post.post_number ?? 0} 正文长度=${cooked.length}`);
    return { postNumber: post.post_number ?? 0, cookedHtml: cooked };
  }

  private matchesMarker(cooked: string, versionCode: number): boolean {
    // [vXXXX] 在 Discourse markdown 里无匹配引用,会原样保留在 cooked 中;哪怕被 **加粗**
    // 包成 <strong>[vXXXX]</strong>,子串里仍含 [vXXXX],所以加不加粗都能直接命中。
    return cooked.indexOf(`[v${versionCode}]`) >= 0;
  }
}
