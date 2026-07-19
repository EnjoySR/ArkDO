import { describe, it, expect } from '@ohos/hypium';
import { BookmarkPage } from '../main/ets/models/Bookmark';
import { BookmarkService } from '../main/ets/services/bookmark/BookmarkService';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../main/ets/services/network/NetworkTypes';

class FakeBridge implements JsonNetworkClient {
  private result: NetworkResult<string>;
  requestedPath: string = '';

  constructor(result: NetworkResult<string>) {
    this.result = result;
  }

  getJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  postForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  putJson(path: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  postJson(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  putForm(path: string, body: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }

  deleteForm(path: string, body: string): Promise<NetworkResult<string>> {
    this.requestedPath = path;
    return Promise.resolve(this.result);
  }

  // 接口占位:本套测试不触及图片上传,只为满足 JsonNetworkClient 而实现。
  uploadImage(base64: string, fileName: string, mimeType: string): Promise<NetworkResult<string>> {
    return Promise.resolve(this.result);
  }
}

function ok(payload: string): NetworkResult<string> {
  return { success: true, statusCode: 200, challengeState: ChallengeState.NONE, data: payload };
}

export default function bookmarkServiceTest() {
  describe('bookmarkServiceTest', () => {
    it('parsesBookmarkListWithExcerptAndMoreUrl', 0, async () => {
      const payload: string = '{"user_bookmark_list":{"more_bookmarks_url":"/u/joeyyin/bookmarks.json?page=1",' +
        '"bookmarks":[' +
        '{"id":2577994,"name":null,"pinned":null,"title":"标题一","fancy_title":"标题一",' +
        '"excerpt":"<a name=\\"p1\\" class=\\"anchor\\"></a>本帖使用社区&lt;开源&gt;推广  多空格\\n换行",' +
        '"bookmarkable_type":"Post","linked_post_number":1,"topic_id":2547629,"category_id":4,' +
        '"tags":[{"id":1451,"name":"软件开发","slug":"1451-tag"},{"id":2234,"name":"开源推广","slug":"2234-tag"}],' +
        '"highest_post_number":26,"created_at":"2026-07-08T13:38:21.685Z",' +
        '"user":{"id":163887,"username":"is_hp","name":"散装江苏","avatar_template":"/user_avatar/linux.do/is_hp/{size}/1.png"}},' +
        '{"id":2574642,"pinned":true,"fancy_title":"置顶帖","excerpt":"内容","linked_post_number":3,' +
        '"topic_id":2536516,"category_id":4,"tags":[],"highest_post_number":10,"created_at":"2026-07-08T01:35:31.575Z",' +
        '"user":{"id":1816,"username":"torvalds"}}]}}';
      const bridge: FakeBridge = new FakeBridge(ok(payload));
      const service: BookmarkService = new BookmarkService(bridge);

      const result: NetworkResult<BookmarkPage> = await service.getFirstPage('joeyyin');

      expect(bridge.requestedPath).assertEqual('/u/joeyyin/bookmarks.json');
      expect(result.success).assertTrue();
      expect(result.data?.bookmarks.length).assertEqual(2);
      expect(result.data?.moreUrl).assertEqual('/u/joeyyin/bookmarks.json?page=1');

      const first = result.data?.bookmarks[0];
      expect(first?.topicId).assertEqual(2547629);
      expect(first?.linkedPostNumber).assertEqual(1);
      // pinned:null → false
      expect(first?.pinned).assertFalse();
      expect(first?.tags.length).assertEqual(2);
      expect(first?.tags[0].name).assertEqual('软件开发');
      expect(first?.tags[1].slug).assertEqual('2234-tag');
      expect(first?.highestPostNumber).assertEqual(26);
      expect(first?.author?.username).assertEqual('is_hp');
      // excerpt:去标签 + 解实体(&lt;&gt;)+ 折叠空白
      expect(first?.excerpt).assertEqual('本帖使用社区<开源>推广 多空格 换行');

      const second = result.data?.bookmarks[1];
      expect(second?.pinned).assertTrue();
      expect(second?.linkedPostNumber).assertEqual(3);
    });

    it('getNextPageRequestsMoreUrlVerbatim', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(ok('{"user_bookmark_list":{"more_bookmarks_url":null,"bookmarks":[]}}'));
      const service: BookmarkService = new BookmarkService(bridge);

      const result: NetworkResult<BookmarkPage> = await service.getNextPage('/u/joeyyin/bookmarks.json?page=2');

      expect(bridge.requestedPath).assertEqual('/u/joeyyin/bookmarks.json?page=2');
      expect(result.success).assertTrue();
      expect(result.data?.bookmarks.length).assertEqual(0);
      // more_bookmarks_url = null → moreUrl 缺省(到底)
      expect(result.data?.moreUrl).assertUndefined();
    });

    it('stripsMentionImageAndNumericEntities', 0, () => {
      const html: string = '看 <a class="mention" href="/u/x">@x</a> 和 ' +
        '<a class="lightbox">[image]</a> &#65; &#x42; &amp;&hellip;';
      expect(BookmarkService.htmlToPlainText(html)).assertEqual('看 @x 和 [image] A B &…');
    });

    it('emptyExcerptStaysEmpty', 0, () => {
      expect(BookmarkService.htmlToPlainText(undefined)).assertEqual('');
      expect(BookmarkService.htmlToPlainText('')).assertEqual('');
    });

    it('deleteBookmarkHitsDeleteEndpoint', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(ok('{"success":"OK"}'));
      const service: BookmarkService = new BookmarkService(bridge);

      const result: NetworkResult<boolean> = await service.deleteBookmark(2577994);

      expect(bridge.requestedPath).assertEqual('/bookmarks/2577994');
      expect(result.success).assertTrue();
      expect(result.data).assertTrue();
    });

    it('togglePinHitsTogglePinEndpoint', 0, async () => {
      const bridge: FakeBridge = new FakeBridge(ok('{}'));
      const service: BookmarkService = new BookmarkService(bridge);

      const result: NetworkResult<boolean> = await service.togglePin(2577994);

      expect(bridge.requestedPath).assertEqual('/bookmarks/2577994/toggle_pin');
      expect(result.success).assertTrue();
    });
  });
}
