import { Log } from '../logging/Log';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { Poll, PollVoteResult, SharedIssueResult, TopicPost } from '../../models/TopicDetail';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { PollMutation, PollSnapshot } from './PollMutation';
import { TopicService } from './TopicService';
import { LoginGate } from '../session/LoginGate';

const LOG_TAG: string = '[ArkDO][PostActions]';

export type ToastFn = (message: string, duration: number) => void;
export type TopicContextFn = () => number;
export type BridgeFn = () => JsonNetworkClient;

// 书签 toggle 结果:
// postBookmarked —— 该楼操作后的最终收藏态(失败=回滚后原态),子组件用它校正本地显示 @State。
// topicBookmarked —— 主题级最终态(详情页驱动标题书签图标);undefined 表示本次无法确定(失败/拿不到权威值),
//                    详情页遇 undefined 时不改动标题图标。
export interface BookmarkToggleResult {
  postBookmarked: boolean;
  topicBookmarked?: boolean;
}

// 楼层动作胶水:表情回应 / 投票 / 撤票 / 拷贝链接 / 书签,统一"发网络 + 失败回滚 + toast"闭环。
// 乐观更新直接写 @Observed 的 TopicPost/Poll,由 @ObjectLink 精准重渲染,不经页面 @State。
// 全部依赖(bridge/toast/主题 id/slug)都经闭包惰性读取:页面在字段初始化器里创建本类时,
// 父组件注入的 bridge prop 还没覆盖默认值,按值捕获会拿到未连接宿主的空壳(实测翻车)。
export class PostActions {
  private getBridge: BridgeFn;
  private toast: ToastFn;
  private getFallbackTopicId: TopicContextFn;
  private getSlug: () => string | undefined;

  constructor(getBridge: BridgeFn, toast: ToastFn,
    getFallbackTopicId: TopicContextFn, getSlug: () => string | undefined) {
    this.getBridge = getBridge;
    this.toast = toast;
    this.getFallbackTopicId = getFallbackTopicId;
    this.getSlug = getSlug;
  }

  // 切换某楼表情回应:请求先行(不乐观更新),返回成败;成功由组件侧应用状态变化并播动画。
  async toggleReaction(post: TopicPost, reaction: string): Promise<boolean> {
    // 未登录:拦截并弹登录页,不发请求(点赞/表情回应)。
    if (!LoginGate.ensureLoggedIn()) {
      return false;
    }
    const result: NetworkResult<string> =
      await new TopicService(this.getBridge()).toggleReaction(post.id, this.resolveTopicId(post), reaction);

    if (!result.success) {
      Log.i(`${LOG_TAG} toggle reaction failed postId=${post.id} reaction=${reaction} status=${result.statusCode}`);
      this.toast('回应失败，请稍后重试', 1500);
    }
    return result.success;
  }

  // 投票:先乐观更新模型,再发 PUT;成功用服务端真实值校正模型并回传给 PollView,失败回滚并回传 null。
  async vote(post: TopicPost, poll: Poll, optionIds: string[]): Promise<PollVoteResult | null> {
    // 未登录:拦截并弹登录页,不做乐观更新也不发请求(投票)。
    if (!LoginGate.ensureLoggedIn()) {
      return null;
    }
    const snapshot: PollSnapshot = PollMutation.snapshot(poll);
    PollMutation.applyVote(poll, optionIds);

    const result: NetworkResult<PollVoteResult> =
      await new TopicService(this.getBridge()).votePoll(post.id, this.resolveTopicId(post), poll.name, optionIds);

    if (result.success && result.data) {
      PollMutation.applyServerResult(poll, result.data);
      return result.data;
    }
    Log.i(`${LOG_TAG} vote failed postId=${post.id} poll=${poll.name} status=${result.statusCode}, rollback`);
    PollMutation.restore(poll, snapshot);
    this.toast('投票失败，请稍后重试', 1500);
    return null;
  }

  // 撤销投票:先乐观更新模型,再发 DELETE;成功用服务端真实值校正模型并回传,失败回滚并回传 null。
  async removeVote(post: TopicPost, poll: Poll): Promise<PollVoteResult | null> {
    // 未登录:拦截并弹登录页,不做乐观更新也不发请求(撤销投票)。
    if (!LoginGate.ensureLoggedIn()) {
      return null;
    }
    const snapshot: PollSnapshot = PollMutation.snapshot(poll);
    PollMutation.applyRemove(poll);

    const result: NetworkResult<PollVoteResult> =
      await new TopicService(this.getBridge()).removePollVote(post.id, this.resolveTopicId(post), poll.name);

    if (result.success && result.data) {
      PollMutation.applyServerResult(poll, result.data);
      return result.data;
    }
    Log.i(`${LOG_TAG} remove vote failed postId=${post.id} poll=${poll.name} status=${result.statusCode}, rollback`);
    PollMutation.restore(poll, snapshot);
    this.toast('撤销投票失败，请稍后重试', 1500);
    return null;
  }

  // linux.do shared issue（"俺也一样"）toggle。纯翻转端点,不需传目标态;返回服务端翻转后的权威新态
  // { created, count } 供按钮覆盖乐观值;失败返回 null 按钮回滚。未登录经 LoginGate 拦截弹登录页,不发请求。
  async toggleSharedIssue(topicId: number): Promise<SharedIssueResult | null> {
    if (!LoginGate.ensureLoggedIn()) {
      return null;
    }
    const result: NetworkResult<SharedIssueResult> =
      await new TopicService(this.getBridge()).toggleSharedIssue(topicId);
    if (result.success && result.data) {
      return result.data;
    }
    Log.i(`${LOG_TAG} shared issue toggle failed topicId=${topicId} status=${result.statusCode}`);
    this.toast('操作失败，请稍后重试', 1500);
    return null;
  }

  // 拷贝该楼永久链接到剪贴板:优先带 slug 的规范链接,缺 slug 时用 /t/topic/<id>/<楼号>(可正常跳转)。
  copyPostLink(post: TopicPost): void {
    const topicId: number = this.resolveTopicId(post);
    const slug: string | undefined = this.getSlug();
    const path: string = slug !== undefined && slug.length > 0
      ? `/t/${slug}/${topicId}/${post.postNumber}`
      : `/t/topic/${topicId}/${post.postNumber}`;
    const url: string = `${AppConstants.BASE_URL}${path}`;
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast('已复制链接', 1500);
    }).catch(() => {
    });
  }

  // 书签 toggle:post.bookmarked/bookmarkId 为网络侧真源,发网络+失败回滚;返回该楼与主题级最终态,
  // 交给子组件校正本地显示 @State、详情页联动标题书签图标。带 [ARKDO][Bookmark] 日志便于排查。
  async toggleBookmark(post: TopicPost): Promise<BookmarkToggleResult> {
    // 未登录:拦截并弹登录页,不做乐观更新也不发请求(收藏/书签)。
    if (!LoginGate.ensureLoggedIn()) {
      return { postBookmarked: post.bookmarked === true, topicBookmarked: undefined };
    }
    const topicId: number = this.resolveTopicId(post);
    const service: TopicService = new TopicService(this.getBridge());
    const wasBookmarked: boolean = post.bookmarked === true;
    const prevId: number | undefined = post.bookmarkId;
    Log.i(`[ARKDO][Bookmark] toggle start postId=${post.id} topicId=${topicId} wasBookmarked=${wasBookmarked} prevId=${prevId}`);

    if (wasBookmarked && prevId !== undefined) {
      post.bookmarked = false;
      post.bookmarkId = undefined;
      const result: NetworkResult<boolean> = await service.removeBookmark(prevId, topicId);
      Log.i(`[ARKDO][Bookmark] remove result postId=${post.id} success=${result.success} status=${result.statusCode} challenge=${result.challengeState} topicBookmarked=${result.data}`);
      if (result.success) {
        this.toast('已取消收藏', 1500);
        Log.i(`[ARKDO][Bookmark] toggle end postId=${post.id} finalBookmarked=${post.bookmarked} bookmarkId=${post.bookmarkId}`);
        // 主题级态优先用接口权威值;拿不到时退化为 false(视为取消了主题内唯一书签,刷新时以真源纠正)。
        return { postBookmarked: false, topicBookmarked: result.data !== undefined ? result.data : false };
      }
      post.bookmarked = true;
      post.bookmarkId = prevId;
      this.toast('取消收藏失败', 1500);
      Log.i(`[ARKDO][Bookmark] toggle end postId=${post.id} finalBookmarked=${post.bookmarked} bookmarkId=${post.bookmarkId}`);
      return { postBookmarked: true, topicBookmarked: undefined };
    }

    post.bookmarked = true;
    const result: NetworkResult<number> = await service.addBookmark(post.id, topicId);
    Log.i(`[ARKDO][Bookmark] add result postId=${post.id} success=${result.success} status=${result.statusCode} challenge=${result.challengeState} id=${result.data}`);
    if (result.success && result.data !== undefined) {
      post.bookmarkId = result.data;
      this.toast('已收藏', 1500);
      Log.i(`[ARKDO][Bookmark] toggle end postId=${post.id} finalBookmarked=${post.bookmarked} bookmarkId=${post.bookmarkId}`);
      // 新增任一楼层书签 → 主题必然有书签。
      return { postBookmarked: true, topicBookmarked: true };
    }
    post.bookmarked = false;
    post.bookmarkId = undefined;
    this.toast('收藏失败', 1500);
    Log.i(`[ARKDO][Bookmark] toggle end postId=${post.id} finalBookmarked=${post.bookmarked} bookmarkId=${post.bookmarkId}`);
    return { postBookmarked: false, topicBookmarked: undefined };
  }

  // 主题 id:优先楼层自带,缺失时用页面 detail 兜底。
  private resolveTopicId(post: TopicPost): number {
    return post.topicId !== undefined ? post.topicId : this.getFallbackTopicId();
  }
}
