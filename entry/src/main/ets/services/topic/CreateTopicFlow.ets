import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { CreateTopicOutcome, TopicService } from './TopicService';
import { ToastFn } from './PostActions';

// 发新主题的完整闭环:POST /posts → 按结果提示 → 直接发布时回调跳转。
// 首页与草稿页原先各写一份逐字相同的实现(连三档 toast 时长 2000/1500/2500 都一样),
// 差异只在「跳转怎么跳」,故把跳转抽成 onPublished 回调,其余全部共用。
//
// toast 经参数注入而非在此直接调 UI:service 层不持有 UIContext,
// 沿用 PostActions 的 ToastFn 约定,保持这一层对 UI 无依赖。
export async function submitNewTopic(
  bridge: JsonNetworkClient,
  toast: ToastFn,
  title: string,
  categoryId: number,
  raw: string,
  tags: string[],
  typingMs: number,
  composerMs: number,
  onPublished: (topicId: number) => void
): Promise<boolean> {
  const result: NetworkResult<CreateTopicOutcome> = await new TopicService(bridge)
    .createTopic(title, categoryId, raw, tags, typingMs, composerMs);

  if (result.success && result.data) {
    const outcome: CreateTopicOutcome = result.data;
    if (outcome.pending) {
      // 进审核队列:只提示,不跳转(帖子还不可见)。
      toast('帖子已提交，等待审核', 2000);
    } else if (typeof outcome.topicId === 'number') {
      // 直接发布:提示后跳进新帖。浮层由调用方在收到 true 后自行关闭,跳转排在其后。
      toast('帖子已发布', 1500);
      onPublished(outcome.topicId);
    }
    return true;
  }

  const reason: string = result.error ? result.error.message : '发布失败，请稍后重试。';
  toast(reason, 2500);
  return false;
}
