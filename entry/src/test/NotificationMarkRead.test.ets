import { describe, it, expect } from '@ohos/hypium';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../main/ets/services/network/NetworkTypes';
import { MarkReadByTopicResult, NotificationApi } from '../main/ets/services/notification/NotificationApi';
import { NotificationEventBus, NotificationSnapshot } from '../main/ets/services/notification/NotificationEventBus';

// 只关心 getJson(拉通知列表)与 putForm(mark-read)。用可编排的假桥返回不同响应。
class FakeBridge implements JsonNetworkClient {
  getJsonResult: NetworkResult<string>;
  putFormResult: NetworkResult<string>;
  getJsonPath: string = '';
  putFormBody: string = '';
  putFormCalled: boolean = false;

  constructor(getJsonResult: NetworkResult<string>, putFormResult: NetworkResult<string>) {
    this.getJsonResult = getJsonResult;
    this.putFormResult = putFormResult;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.getJsonPath = path;
    return Promise.resolve(this.getJsonResult);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.putFormResult);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.putFormResult);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.putFormResult);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.putFormCalled = true;
    this.putFormBody = body;
    return Promise.resolve(this.putFormResult);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.putFormResult);
  }

  uploadImage(base64: string, fileName: string, mimeType: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.putFormResult);
  }
}

function ok(data: string): NetworkResult<string> {
  return { success: true, statusCode: 200, challengeState: ChallengeState.NONE, data: data };
}

function fail(status: number): NetworkResult<string> {
  return { success: false, statusCode: status, challengeState: ChallengeState.NONE };
}

// 构造一条 /notifications.json 的原始通知。read 默认为 false(未读)。
function rawNotification(id: number, type: number, topicId: number, postNumber: number, read: boolean): string {
  return `{"id":${id},"notification_type":${type},"read":${read},"topic_id":${topicId},"post_number":${postNumber},"data":{}}`;
}

function notificationsResponse(items: string[]): string {
  return `{"notifications":[${items.join(',')}]}`;
}

export default function notificationMarkReadTest() {
  describe('notificationMarkReadTest', () => {
    // ---- markReadByTopic:反查匹配 ----

    it('marksExactPostNumberMatch', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(
        ok(notificationsResponse([
          rawNotification(11, 2, 100, 5, false),
          rawNotification(12, 2, 100, 8, false)
        ])),
        ok('{"success":"OK"}')
      );
      const api: NotificationApi = new NotificationApi(bridge);

      const result: MarkReadByTopicResult = await api.markReadByTopic(100, 8);

      expect(result.marked).assertTrue();
      expect(result.notificationType).assertEqual(2);
      // 标的是楼层 8 那条(id=12),不是同帖的 id=11。
      expect(bridge.putFormBody).assertEqual('id=12');
    });

    it('fallsBackToFirstUnreadOfTopicWhenNoPostNumber', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(
        ok(notificationsResponse([
          rawNotification(21, 6, 200, 1, false)
        ])),
        ok('{"success":"OK"}')
      );
      const api: NotificationApi = new NotificationApi(bridge);

      // 不传 postNumber:退化为按 topicId 匹配首条未读。
      const result: MarkReadByTopicResult = await api.markReadByTopic(200);

      expect(result.marked).assertTrue();
      expect(result.notificationType).assertEqual(6);
      expect(bridge.putFormBody).assertEqual('id=21');
    });

    it('doesNotMarkWhenPostNumberGivenButNoExactMatch', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(
        ok(notificationsResponse([
          rawNotification(31, 2, 300, 5, false)   // 帖对但楼层不对
        ])),
        ok('{"success":"OK"}')
      );
      const api: NotificationApi = new NotificationApi(bridge);

      // 指定了楼层 9 却无精确命中:不硬套同帖别的未读,避免误标。
      const result: MarkReadByTopicResult = await api.markReadByTopic(300, 9);

      expect(result.marked).assertFalse();
      expect(bridge.putFormCalled).assertFalse();
    });

    it('ignoresAlreadyReadNotifications', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(
        ok(notificationsResponse([
          rawNotification(41, 2, 400, 3, true)    // 已读,不该被再标
        ])),
        ok('{"success":"OK"}')
      );
      const api: NotificationApi = new NotificationApi(bridge);

      const result: MarkReadByTopicResult = await api.markReadByTopic(400, 3);

      expect(result.marked).assertFalse();
      expect(bridge.putFormCalled).assertFalse();
    });

    it('returnsNotMarkedWhenListLoadFails', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(fail(429), ok('{"success":"OK"}'));
      const api: NotificationApi = new NotificationApi(bridge);

      const result: MarkReadByTopicResult = await api.markReadByTopic(500, 1);

      expect(result.marked).assertFalse();
      expect(bridge.putFormCalled).assertFalse();
    });

    it('usesNonRecentListToAvoidBumpingSeen', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(
        ok(notificationsResponse([rawNotification(61, 2, 600, 2, false)])),
        ok('{"success":"OK"}')
      );
      const api: NotificationApi = new NotificationApi(bridge);

      await api.markReadByTopic(600, 2);

      // recent=false:不能带 recent=true,否则会顺带 bump seen 把整个红点清掉。
      expect(bridge.getJsonPath.indexOf('recent=true') < 0).assertTrue();
    });

    // ---- decrementUnread:未读数乐观递减 + 0/空窗保护 ----

    it('decrementsUnreadByOneWhenPositive', 0, () => {
      NotificationEventBus.publish({ unread: 3, highPriority: 0 });
      NotificationEventBus.decrementUnread(false);

      const snap: NotificationSnapshot = NotificationEventBus.current();
      expect(snap.unread).assertEqual(2);
      expect(snap.highPriority).assertEqual(0);
    });

    it('doesNothingWhenUnreadIsZero', 0, () => {
      // 铃铛为 0(或轮询空窗期还没拿到真实值):绝不擅自减成负数。
      NotificationEventBus.publish({ unread: 0, highPriority: 0 });
      NotificationEventBus.decrementUnread(false);

      expect(NotificationEventBus.current().unread).assertEqual(0);
    });

    it('decrementsHighPriorityOnlyForHighPriorityType', 0, () => {
      NotificationEventBus.publish({ unread: 2, highPriority: 1 });
      NotificationEventBus.decrementUnread(true);

      const snap: NotificationSnapshot = NotificationEventBus.current();
      expect(snap.unread).assertEqual(1);
      expect(snap.highPriority).assertEqual(0);
    });

    it('keepsHighPriorityWhenTypeIsNotHighPriority', 0, () => {
      NotificationEventBus.publish({ unread: 2, highPriority: 1 });
      NotificationEventBus.decrementUnread(false);

      const snap: NotificationSnapshot = NotificationEventBus.current();
      expect(snap.unread).assertEqual(1);
      // 普通类型只减 unread,不动 highPriority。
      expect(snap.highPriority).assertEqual(1);
    });

    it('doesNotDecrementHighPriorityBelowZero', 0, () => {
      NotificationEventBus.publish({ unread: 3, highPriority: 0 });
      NotificationEventBus.decrementUnread(true);

      const snap: NotificationSnapshot = NotificationEventBus.current();
      expect(snap.unread).assertEqual(2);
      expect(snap.highPriority).assertEqual(0);
    });
  });
}
