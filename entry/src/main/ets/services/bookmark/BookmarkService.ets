import { Bookmark, BookmarkPage } from '../../models/Bookmark';
import { TopicTag } from '../../models/Topic';
import { User } from '../../models/User';
import { HtmlText } from '../content/HtmlText';
import { ChallengeState, JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';
import { forwardFailure, unexpectedResponse } from '../network/NetworkResults';

interface DiscourseBookmarkListResponse {
  user_bookmark_list?: DiscourseBookmarkList;
}

interface DiscourseBookmarkList {
  more_bookmarks_url?: string | null;
  bookmarks?: DiscourseBookmark[];
}

interface DiscourseBookmark {
  id?: number;
  name?: string | null;
  pinned?: boolean | null;
  title?: string;
  fancy_title?: string;
  excerpt?: string;
  bookmarkable_type?: string;
  linked_post_number?: number | null;
  topic_id?: number;
  category_id?: number;
  // 书签接口的 tags 是对象数组 {id,name,slug}(不同于话题列表的字符串数组)。
  tags?: DiscourseBookmarkTag[];
  tags_descriptions?: object;
  highest_post_number?: number;
  created_at?: string;
  user?: DiscourseBookmarkUser;
}

interface DiscourseBookmarkTag {
  id?: number;
  name?: string;
  slug?: string;
}

interface DiscourseBookmarkUser {
  id?: number;
  username?: string;
  name?: string;
  avatar_template?: string;
  animated_avatar?: string | null;
}

// 书签数据服务:解析 /u/{username}/bookmarks.json,分页走响应里的 more_bookmarks_url。
// excerpt 字段是 HTML(含提及/图片/实体),转成纯文本供列表 2 行展示。
export class BookmarkService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  async getFirstPage(username: string): Promise<NetworkResult<BookmarkPage>> {
    return this.fetchPage(`/u/${encodeURIComponent(username)}/bookmarks.json`);
  }

  // moreUrl 直接来自上一页响应(形如 /u/{u}/bookmarks.json?page=1),原样请求即可。
  async getNextPage(moreUrl: string): Promise<NetworkResult<BookmarkPage>> {
    return this.fetchPage(moreUrl);
  }

  // 删除书签:DELETE /bookmarks/{id}(CSRF/Cookie 由 bridge 同源处理)。
  async deleteBookmark(id: number): Promise<NetworkResult<boolean>> {
    return this.toBooleanResult(await this.bridge.deleteForm(`/bookmarks/${id}`, ''));
  }

  // 置顶/取消置顶:PUT /bookmarks/{id}/toggle_pin(空 body,服务端翻转 pinned)。
  async togglePin(id: number): Promise<NetworkResult<boolean>> {
    return this.toBooleanResult(await this.bridge.putJson(`/bookmarks/${id}/toggle_pin`));
  }

  private toBooleanResult(response: NetworkResult<string>): NetworkResult<boolean> {
    if (!response.success) {
      return {
        success: false,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        error: response.error
      };
    }
    return {
      success: true,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      data: true
    };
  }

  private async fetchPage(path: string): Promise<NetworkResult<BookmarkPage>> {
    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 书签响应为空。');
    }

    try {
      const payload: DiscourseBookmarkListResponse = JSON.parse(response.data) as DiscourseBookmarkListResponse;
      const list: DiscourseBookmarkList | undefined = payload.user_bookmark_list;
      if (!list) {
        return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 书签响应缺少 user_bookmark_list。');
      }

      const sourceBookmarks: DiscourseBookmark[] = list.bookmarks ? list.bookmarks : [];
      const bookmarks: Bookmark[] = [];
      for (let index: number = 0; index < sourceBookmarks.length; index++) {
        const mapped: Bookmark | undefined = this.mapBookmark(sourceBookmarks[index]);
        if (mapped) {
          bookmarks.push(mapped);
        }
      }

      const page: BookmarkPage = { bookmarks: bookmarks };
      if (typeof list.more_bookmarks_url === 'string' && list.more_bookmarks_url.length > 0) {
        page.moreUrl = list.more_bookmarks_url;
      }
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: page
      };
    } catch (error) {
      return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 书签响应不是有效 JSON。');
    }
  }

  private mapBookmark(source: DiscourseBookmark): Bookmark | undefined {
    if (typeof source.topic_id !== 'number' ||
      (typeof source.title !== 'string' && typeof source.fancy_title !== 'string')) {
      return undefined;
    }

    const title: string = typeof source.fancy_title === 'string' && source.fancy_title.length > 0
      ? source.fancy_title
      : (source.title ? source.title : '');

    const bookmark: Bookmark = {
      id: typeof source.id === 'number' ? source.id : 0,
      topicId: source.topic_id,
      title: BookmarkService.decodeEntities(title),
      excerpt: BookmarkService.htmlToPlainText(source.excerpt),
      linkedPostNumber: typeof source.linked_post_number === 'number' && source.linked_post_number > 0
        ? source.linked_post_number
        : 1,
      pinned: source.pinned === true,
      tags: this.mapTags(source.tags)
    };
    if (typeof source.category_id === 'number') {
      bookmark.categoryId = source.category_id;
    }
    if (typeof source.highest_post_number === 'number') {
      bookmark.highestPostNumber = source.highest_post_number;
    }
    if (source.created_at && source.created_at.length > 0) {
      bookmark.createdAt = source.created_at;
    }
    const author: User | undefined = this.mapUser(source.user);
    if (author) {
      bookmark.author = author;
    }
    return bookmark;
  }

  private mapTags(tags?: DiscourseBookmarkTag[]): TopicTag[] {
    const result: TopicTag[] = [];
    if (!tags) {
      return result;
    }
    for (let index: number = 0; index < tags.length; index++) {
      const tag: DiscourseBookmarkTag = tags[index];
      if (!tag || typeof tag.name !== 'string' || tag.name.length === 0) {
        continue;
      }
      const mapped: TopicTag = { name: tag.name };
      if (typeof tag.id === 'number') {
        mapped.id = tag.id;
      }
      if (typeof tag.slug === 'string' && tag.slug.length > 0) {
        mapped.slug = tag.slug;
      }
      result.push(mapped);
    }
    return result;
  }

  private mapUser(source?: DiscourseBookmarkUser): User | undefined {
    if (!source || typeof source.id !== 'number' || typeof source.username !== 'string') {
      return undefined;
    }
    const user: User = {
      id: source.id,
      username: source.username
    };
    if (source.name && source.name.length > 0) {
      user.displayName = source.name;
    }
    if (source.avatar_template && source.avatar_template.length > 0) {
      user.avatarTemplate = source.avatar_template;
    }
    if (source.animated_avatar && source.animated_avatar.length > 0) {
      user.animatedAvatar = source.animated_avatar;
    }
    return user;
  }

  // 委托共享工具(与用户动态列表共用),保留静态入口方便单测直接调用。
  static htmlToPlainText(html?: string): string {
    return HtmlText.toPlainText(html);
  }

  static decodeEntities(input: string): string {
    return HtmlText.decodeEntities(input);
  }

  private forwardFailure(response: NetworkResult<string>): NetworkResult<BookmarkPage> {
    return forwardFailure<BookmarkPage>(response);
  }

  private unexpectedResponse(statusCode: number, challengeState: ChallengeState, message: string): NetworkResult<BookmarkPage> {
    return unexpectedResponse<BookmarkPage>(statusCode, challengeState, message);
  }
}
