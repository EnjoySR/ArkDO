const LOG_TAG: string = '[ArkDO][TopicReadState]';

// 从详情页回传给列表页的"已读状态"更新:离开详情页时结算一次,
// 让首页列表把对应主题的蓝点消掉、并把未读徽标更新成真实剩余未读数。
export interface TopicReadState {
  topicId: number;
  unseen: boolean;
  unreadPosts: number;
}

export type TopicReadStateListener = (state: TopicReadState) => void;

export class TopicReadStateEventBus {
  private static listeners: Map<number, TopicReadStateListener> = new Map();
  private static nextListenerId: number = 0;

  static subscribe(listener: TopicReadStateListener): () => void {
    const listenerId: number = TopicReadStateEventBus.nextListenerId;
    TopicReadStateEventBus.nextListenerId++;
    TopicReadStateEventBus.listeners.set(listenerId, listener);

    return () => {
      TopicReadStateEventBus.listeners.delete(listenerId);
    };
  }

  static publish(state: TopicReadState): void {
    const listeners: TopicReadStateListener[] = [];
    TopicReadStateEventBus.listeners.forEach((listener: TopicReadStateListener) => {
      listeners.push(listener);
    });

    console.info(`${LOG_TAG} publish topicId=${state.topicId} unseen=${state.unseen} unreadPosts=${state.unreadPosts} listeners=${listeners.length}`);
    for (let index: number = 0; index < listeners.length; index++) {
      try {
        listeners[index](state);
      } catch (error) {
        console.info(`${LOG_TAG} listener failed topicId=${state.topicId} error=${JSON.stringify(error)}`);
      }
    }
  }
}
