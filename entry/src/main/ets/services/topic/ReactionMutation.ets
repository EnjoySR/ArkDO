import { PostReaction, TopicPost } from '../../models/TopicDetail';

// 回滚快照:记录一次乐观更新前的回应状态。
export interface ReactionSnapshot {
  reactions: PostReaction[];
  reactionUsersCount?: number;
  currentUserReaction?: string;
}

// 表情回应的本地乐观更新逻辑(单用户单回应模型),独立成纯逻辑便于单测。
// 直接改 @Observed 的 TopicPost 字段 → 对应楼层 TopicPostItem 精准重渲染。
export class ReactionMutation {
  static snapshot(post: TopicPost): ReactionSnapshot {
    return {
      reactions: ReactionMutation.cloneReactions(post.reactions),
      reactionUsersCount: post.reactionUsersCount,
      currentUserReaction: post.currentUserReaction
    };
  }

  static restore(post: TopicPost, snap: ReactionSnapshot): void {
    post.reactions = ReactionMutation.cloneReactions(snap.reactions);
    post.reactionUsersCount = snap.reactionUsersCount;
    post.currentUserReaction = snap.currentUserReaction;
  }

  static applyToggle(post: TopicPost, reaction: string): void {
    const reactions: PostReaction[] = ReactionMutation.cloneReactions(post.reactions);
    const prev: string | undefined = post.currentUserReaction;
    let usersCount: number = post.reactionUsersCount ? post.reactionUsersCount : 0;

    if (prev === reaction) {
      // 再次点同一个 → 取消
      ReactionMutation.decrement(reactions, reaction);
      usersCount = Math.max(0, usersCount - 1);
      post.currentUserReaction = undefined;
    } else {
      if (prev !== undefined) {
        // 切换到别的表情 → 移除旧的(回应人数不变)
        ReactionMutation.decrement(reactions, prev);
      } else {
        // 原本没回应 → 新增一名回应者
        usersCount = usersCount + 1;
      }
      ReactionMutation.increment(reactions, reaction);
      post.currentUserReaction = reaction;
    }

    // 按数量降序,贴近官网展示顺序
    reactions.sort((a: PostReaction, b: PostReaction) => b.count - a.count);
    post.reactions = reactions;
    post.reactionUsersCount = usersCount;
  }

  private static cloneReactions(source?: PostReaction[]): PostReaction[] {
    const copy: PostReaction[] = [];
    if (!source) {
      return copy;
    }
    for (let index: number = 0; index < source.length; index++) {
      copy.push({ id: source[index].id, count: source[index].count });
    }
    return copy;
  }

  private static increment(reactions: PostReaction[], id: string): void {
    for (let index: number = 0; index < reactions.length; index++) {
      if (reactions[index].id === id) {
        reactions[index] = { id: id, count: reactions[index].count + 1 };
        return;
      }
    }
    reactions.push({ id: id, count: 1 });
  }

  private static decrement(reactions: PostReaction[], id: string): void {
    for (let index: number = 0; index < reactions.length; index++) {
      if (reactions[index].id === id) {
        const next: number = reactions[index].count - 1;
        if (next <= 0) {
          reactions.splice(index, 1);
        } else {
          reactions[index] = { id: id, count: next };
        }
        return;
      }
    }
  }
}
