import { describe, it, expect } from '@ohos/hypium';
import { PostReaction, TopicPost } from '../main/ets/models/TopicDetail';
import { ReactionMutation, ReactionSnapshot } from '../main/ets/services/topic/ReactionMutation';

function makePost(reactions: PostReaction[], usersCount: number | undefined, current: string | undefined): TopicPost {
  const post: TopicPost = new TopicPost();
  post.id = 1;
  post.postNumber = 1;
  post.reactions = reactions;
  post.reactionUsersCount = usersCount;
  post.currentUserReaction = current;
  return post;
}

function countOf(reactions: PostReaction[] | undefined, id: string): number {
  const list: PostReaction[] = reactions ? reactions : [];
  for (let index: number = 0; index < list.length; index++) {
    if (list[index].id === id) {
      return list[index].count;
    }
  }
  return 0;
}

export default function reactionMutationTest() {
  describe('reactionMutationTest', () => {
    it('addsHeartWhenNoPriorReaction', 0, () => {
      const post: TopicPost = makePost([], undefined, undefined);

      ReactionMutation.applyToggle(post, 'heart');

      expect(post.currentUserReaction).assertEqual('heart');
      expect(post.reactionUsersCount).assertEqual(1);
      expect(countOf(post.reactions, 'heart')).assertEqual(1);
    });

    it('removesHeartWhenTogglingSameReaction', 0, () => {
      const post: TopicPost = makePost([{ id: 'heart', count: 1 }], 1, 'heart');

      ReactionMutation.applyToggle(post, 'heart');

      expect(post.currentUserReaction).assertUndefined();
      expect(post.reactionUsersCount).assertEqual(0);
      // count 归零后该项被移除
      expect(post.reactions ? post.reactions.length : 0).assertEqual(0);
    });

    it('switchesReactionKeepingUsersCount', 0, () => {
      const post: TopicPost = makePost([{ id: '+1', count: 1 }], 1, '+1');

      ReactionMutation.applyToggle(post, 'heart');

      expect(post.currentUserReaction).assertEqual('heart');
      // 切换:人数不变
      expect(post.reactionUsersCount).assertEqual(1);
      expect(countOf(post.reactions, '+1')).assertEqual(0);
      expect(countOf(post.reactions, 'heart')).assertEqual(1);
    });

    it('addsHeartAmongOthersAndSortsByCountDesc', 0, () => {
      const post: TopicPost = makePost(
        [{ id: 'laughing', count: 4 }, { id: 'distorted_face', count: 2 }, { id: 'heart', count: 1 }],
        7,
        undefined
      );

      ReactionMutation.applyToggle(post, 'heart');

      expect(post.currentUserReaction).assertEqual('heart');
      expect(post.reactionUsersCount).assertEqual(8);
      expect(countOf(post.reactions, 'heart')).assertEqual(2);
      // 降序:数量最多的 laughing 排第一
      const reactions: PostReaction[] = post.reactions ? post.reactions : [];
      expect(reactions[0].id).assertEqual('laughing');
      expect(reactions[0].count).assertEqual(4);
    });

    it('restoreRevertsToSnapshotAndSnapshotIsDeepCopied', 0, () => {
      const post: TopicPost = makePost([{ id: 'heart', count: 3 }], 3, 'heart');
      const snap: ReactionSnapshot = ReactionMutation.snapshot(post);

      // 切换到别的表情
      ReactionMutation.applyToggle(post, 'laughing');
      expect(post.currentUserReaction).assertEqual('laughing');
      expect(countOf(post.reactions, 'heart')).assertEqual(2);
      // 快照是深拷贝,不受后续变更影响
      expect(snap.reactions[0].count).assertEqual(3);

      ReactionMutation.restore(post, snap);
      expect(post.currentUserReaction).assertEqual('heart');
      expect(post.reactionUsersCount).assertEqual(3);
      expect(countOf(post.reactions, 'heart')).assertEqual(3);
    });
  });
}
