import { ChallengeState, JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';

interface LatestProbePayload {
  topic_list?: LatestProbeTopicList;
}

interface LatestProbeTopicList {
  topics?: Object[];
}

export class ChallengeResolutionProbe {
  private client: JsonNetworkClient;

  constructor(client: JsonNetworkClient) {
    this.client = client;
  }

  async canAccessLatestJson(): Promise<boolean> {
    const result: NetworkResult<string> = await this.client.getJson('/latest.json', { notifyChallenge: false });
    if (!result.success || result.statusCode !== 200 || result.challengeState !== ChallengeState.NONE || !result.data) {
      return false;
    }

    try {
      const payload: LatestProbePayload = JSON.parse(result.data) as LatestProbePayload;
      return !!payload.topic_list && !!payload.topic_list.topics;
    } catch (error) {
      return false;
    }
  }
}
