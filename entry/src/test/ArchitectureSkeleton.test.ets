import { describe, it, expect } from '@ohos/hypium';
import { AppConstants } from '../main/ets/common/constants/AppConstants';
import { Topic } from '../main/ets/models/Topic';
import { User } from '../main/ets/models/User';
import { ChallengeState, NetworkErrorCode, NetworkResult } from '../main/ets/services/network/NetworkTypes';

export default function architectureSkeletonTest() {
  describe('architectureSkeletonTest', () => {
    it('definesStableAppConstants', 0, () => {
      expect(AppConstants.APP_NAME).assertEqual('ArkDO');
      expect(AppConstants.BASE_URL).assertEqual('https://linux.do');
      expect(AppConstants.CHALLENGE_URL).assertEqual('https://linux.do/challenge');
      expect(AppConstants.DEFAULT_TIMEOUT_MS).assertEqual(15000);
      expect(AppConstants.DEFAULT_USER_AGENT).assertContain('ArkDO');
    });

    it('allowsMinimalTopicAndUserShape', 0, () => {
      const user: User = {
        id: 1,
        username: 'linuxdo_user',
        displayName: 'Linux.do User',
        avatarTemplate: '/user_avatar/linux.do/linuxdo_user/{size}/1_2.png'
      };
      const topic: Topic = {
        id: 100,
        title: 'ArkDO phase one',
        slug: 'arkdo-phase-one',
        postsCount: 1,
        replyCount: 0,
        likeCount: 0,
        createdAt: '2026-07-03T00:00:00.000Z',
        lastPostedAt: '2026-07-03T00:00:00.000Z',
        author: user
      };

      expect(topic.id).assertEqual(100);
      expect(topic.author?.username).assertEqual('linuxdo_user');
    });

    it('definesNetworkResultShape', 0, () => {
      const result: NetworkResult<string> = {
        success: false,
        statusCode: 0,
        challengeState: ChallengeState.NONE,
        error: {
          code: NetworkErrorCode.NOT_IMPLEMENTED,
          message: 'Phase one network bridge is not implemented.',
          requiresChallenge: false
        }
      };

      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual(NetworkErrorCode.NOT_IMPLEMENTED);
      expect(result.challengeState).assertEqual(ChallengeState.NONE);
    });
  });
}
