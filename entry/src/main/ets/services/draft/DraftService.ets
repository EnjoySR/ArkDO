import { Draft, DraftAction, DraftPage, DraftTagRef } from '../../models/Draft';
import { AppConstants } from '../../common/constants/AppConstants';
import { ChallengeState, JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';

// 保存新主题草稿的入参。tags 用 {id,name} 对象(与官方 composer 存的结构一致)。
export interface SaveTopicDraftInput {
  draftKey: string;
  sequence: number;
  title: string;
  categoryId: number;
  tags: DraftTagRef[];
  reply: string;
  composerTimeMs: number;
  typingTimeMs: number;
}

// 保存回帖草稿的入参。draftKey 形如 topic_<主题id>;categoryId 是主题所属分类。
export interface SaveReplyDraftInput {
  draftKey: string;
  sequence: number;
  categoryId: number;
  reply: string;
  composerTimeMs: number;
  typingTimeMs: number;
  // 定向回复某楼时带上楼号,回复整个话题为空。
  replyToPostNumber?: number;
}

// 回帖草稿的 data 内层结构:比新主题少 title/tags,多主题所属 categoryId(对齐官方抓包)。
interface ReplyDraftData {
  reply: string;
  action: string;
  categoryId: number | null;
  tags: string[];
  archetypeId: string;
  metaData: object | null;
  composerTime: number;
  typingTime: number;
  locale: string;
  reply_to_post_number: number | null;
  reply_to_user: object | null;
}

// data 字段内层结构(POST 时序列化成 JSON 串再 URL 编码)。
interface TopicDraftData {
  reply: string;
  action: string;
  title: string;
  categoryId: number | null;
  tags: DraftTagRef[];
  archetypeId: string;
  metaData: object | null;
  composerTime: number;
  typingTime: number;
  original_text: string;
  locale: string;
  reply_to_post_number: number | null;
  reply_to_user: object | null;
}

interface DiscourseDraftSaveResponse {
  success?: string;
  draft_sequence?: number;
}

// 一页拉多少条草稿。/drafts.json 支持 ?offset=&limit=,无游标,靠本页条数判是否到底。
const DRAFTS_PAGE_LIMIT: number = 30;

interface DiscourseDraftListResponse {
  drafts?: DiscourseDraft[];
}

interface DiscourseDraft {
  draft_key?: string;
  sequence?: number;
  excerpt?: string;
  created_at?: string;
  // 顶层 topic_id:回帖草稿指向所回主题;新主题/私信为 null。
  topic_id?: number | null;
  // 顶层 title:回帖草稿为所回主题的标题;新主题/私信为 null(真标题在 data.title)。
  title?: string | null;
  category_id?: number;
  // data 是内嵌 JSON 字符串,须二次 JSON.parse。
  data?: string;
}

// data 二次解析后的结构(只取展示/续写要用的字段)。
interface DiscourseDraftData {
  reply?: string;
  action?: string;
  title?: string;
  categoryId?: number | null;
  // 新主题草稿里 tags 是对象数组 {id,name};其余类型多为空数组。兼容字符串数组。
  tags?: (DiscourseDraftTag | string)[];
}

interface DiscourseDraftTag {
  id?: number;
  name?: string;
}

// 草稿数据服务:解析 /drafts.json。分页用 offset 累加(接口无 more_url)。
export class DraftService {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  async getPage(offset: number): Promise<NetworkResult<DraftPage>> {
    return this.fetchPage(`/drafts.json?offset=${offset}&limit=${DRAFTS_PAGE_LIMIT}`);
  }

  // 保存回帖草稿:draft_key 固定为 topic_<主题id>,故同一主题只会有一条草稿(不像新主题每开一次新建一条)。
  // data 比新主题少 title/tags(回帖没有这两样),多带主题所属 categoryId(对齐官方抓包)。
  async saveReplyDraft(input: SaveReplyDraftInput): Promise<NetworkResult<number>> {
    const data: ReplyDraftData = {
      reply: input.reply,
      action: 'reply',
      categoryId: input.categoryId >= 0 ? input.categoryId : null,
      tags: [],
      archetypeId: 'regular',
      metaData: null,
      composerTime: Math.max(0, Math.round(input.composerTimeMs)),
      typingTime: Math.max(0, Math.round(input.typingTimeMs)),
      locale: '',
      reply_to_post_number: input.replyToPostNumber !== undefined ? input.replyToPostNumber : null,
      reply_to_user: null
    };
    return this.postDraft(input.draftKey, input.sequence, JSON.stringify(data));
  }

  // 保存草稿:POST /drafts.json,**表单编码**(不是 JSON body)。
  // 字段对齐官方抓包:draft_key / sequence / data(URL 编码的 JSON 串) / owner / force_save。
  // 响应 {"success":"OK","draft_sequence":N},N 是下一次该带的序号,调用方需存回。
  async saveTopicDraft(input: SaveTopicDraftInput): Promise<NetworkResult<number>> {
    // data 内层 JSON 结构照官方 composer 原样构造(字段少一个都可能被服务端忽略)。
    const data: TopicDraftData = {
      reply: input.reply,
      action: 'createTopic',
      title: input.title,
      categoryId: input.categoryId >= 0 ? input.categoryId : null,
      tags: input.tags,
      archetypeId: 'regular',
      metaData: null,
      composerTime: Math.max(0, Math.round(input.composerTimeMs)),
      typingTime: Math.max(0, Math.round(input.typingTimeMs)),
      original_text: '',
      locale: '',
      reply_to_post_number: null,
      reply_to_user: null
    };
    return this.postDraft(input.draftKey, input.sequence, JSON.stringify(data));
  }

  // 保存草稿的公共出口:表单拼装 + 发送 + 取回新序号。新主题/回帖只是 data 内层不同。
  private async postDraft(draftKey: string, sequence: number, dataJson: string): Promise<NetworkResult<number>> {
    const body: string = `draft_key=${encodeURIComponent(draftKey)}` +
      `&sequence=${sequence}` +
      `&data=${encodeURIComponent(dataJson)}` +
      `&owner=${encodeURIComponent(DraftService.ownerId())}` +
      `&force_save=false`;

    const response: NetworkResult<string> = await this.bridge.postForm('/drafts.json', body, {
      notifyChallenge: false,
      referrer: `${AppConstants.BASE_URL}/`
    });
    if (!response.success) {
      return {
        success: false,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        error: response.error
      };
    }
    // 取响应里的新序号;缺省沿用旧序号(不阻塞保存流程)。
    let nextSequence: number = sequence;
    if (response.data !== undefined) {
      try {
        const payload: DiscourseDraftSaveResponse = JSON.parse(response.data) as DiscourseDraftSaveResponse;
        if (typeof payload.draft_sequence === 'number') {
          nextSequence = payload.draft_sequence;
        }
      } catch (error) {
        // 响应不是 JSON 不影响「已保存」判定,沿用旧序号。
      }
    }
    return {
      success: true,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      data: nextSequence
    };
  }

  // 删除草稿:DELETE /drafts/<draft_key>.json,**sequence 在表单 body 里**(不是 query)。
  // 发帖成功后清理、或用户手动删都走它。
  async deleteDraft(draftKey: string, sequence: number): Promise<NetworkResult<boolean>> {
    const path: string = `/drafts/${encodeURIComponent(draftKey)}.json`;
    const body: string = `draft_key=${encodeURIComponent(draftKey)}&sequence=${sequence}`;
    const response: NetworkResult<string> = await this.bridge.deleteForm(path, body);
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

  // owner:官方 composer 传的客户端标识(32 位十六进制),服务端据此判断「是不是同一端在改」。
  // 全 App 一个即可,进程内生成一次复用。
  private static owner: string = '';

  private static ownerId(): string {
    if (DraftService.owner.length === 0) {
      let hex: string = '';
      while (hex.length < 32) {
        hex += Math.floor(Math.random() * 16).toString(16);
      }
      DraftService.owner = hex;
    }
    return DraftService.owner;
  }

  private async fetchPage(path: string): Promise<NetworkResult<DraftPage>> {
    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return this.forwardFailure(response);
    }
    if (response.data === undefined) {
      return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 草稿响应为空。');
    }

    try {
      const payload: DiscourseDraftListResponse = JSON.parse(response.data) as DiscourseDraftListResponse;
      const source: DiscourseDraft[] = payload.drafts ? payload.drafts : [];
      const drafts: Draft[] = [];
      for (let index: number = 0; index < source.length; index++) {
        const mapped: Draft | undefined = this.mapDraft(source[index]);
        if (mapped) {
          drafts.push(mapped);
        }
      }
      const page: DraftPage = {
        drafts: drafts,
        // 本页拿满 limit 才可能还有下一页。
        hasMore: source.length >= DRAFTS_PAGE_LIMIT
      };
      return {
        success: true,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        data: page
      };
    } catch (error) {
      return this.unexpectedResponse(response.statusCode, response.challengeState, 'Linux.do 草稿响应不是有效 JSON。');
    }
  }

  private mapDraft(source: DiscourseDraft): Draft | undefined {
    if (typeof source.draft_key !== 'string' || source.draft_key.length === 0) {
      return undefined;
    }
    const data: DiscourseDraftData = this.parseData(source.data);
    const action: DraftAction = this.toAction(data.action);

    // 标题:新主题/私信取 data.title;回帖取顶层 title(所回主题标题)。都空则占位。
    const dataTitle: string = typeof data.title === 'string' ? data.title.trim() : '';
    const topTitle: string = typeof source.title === 'string' ? source.title.trim() : '';
    const title: string = dataTitle.length > 0 ? dataTitle : (topTitle.length > 0 ? topTitle : '(无标题草稿)');

    const draft: Draft = {
      draftKey: source.draft_key,
      sequence: typeof source.sequence === 'number' ? source.sequence : 0,
      action: action,
      title: title,
      excerpt: DraftService.cleanExcerpt(source.excerpt, data.reply),
      createdAt: typeof source.created_at === 'string' ? source.created_at : '',
      tags: this.mapTags(data.tags),
      reply: typeof data.reply === 'string' ? data.reply : ''
    };
    if (typeof source.topic_id === 'number') {
      draft.topicId = source.topic_id;
    }
    // 分类:优先 data.categoryId(续写要用),回退顶层 category_id。
    if (typeof data.categoryId === 'number') {
      draft.categoryId = data.categoryId;
    } else if (typeof source.category_id === 'number') {
      draft.categoryId = source.category_id;
    }
    return draft;
  }

  private parseData(raw?: string): DiscourseDraftData {
    if (typeof raw !== 'string' || raw.length === 0) {
      return {};
    }
    try {
      return JSON.parse(raw) as DiscourseDraftData;
    } catch (error) {
      return {};
    }
  }

  private toAction(action?: string): DraftAction {
    if (action === DraftAction.NEW_TOPIC) {
      return DraftAction.NEW_TOPIC;
    }
    if (action === DraftAction.REPLY) {
      return DraftAction.REPLY;
    }
    if (action === DraftAction.PRIVATE_MESSAGE) {
      return DraftAction.PRIVATE_MESSAGE;
    }
    return DraftAction.OTHER;
  }

  // 草稿里的 tags 通常是 {id,name} 对象;老数据可能是纯字符串,此时 id 记 0(续写仍能按名提交)。
  private mapTags(tags?: (DiscourseDraftTag | string)[]): DraftTagRef[] {
    const result: DraftTagRef[] = [];
    if (!tags) {
      return result;
    }
    for (let index: number = 0; index < tags.length; index++) {
      const tag: DiscourseDraftTag | string = tags[index];
      if (typeof tag === 'string') {
        if (tag.length > 0) {
          result.push({ id: 0, name: tag });
        }
      } else if (tag && typeof tag.name === 'string' && tag.name.length > 0) {
        result.push({ id: typeof tag.id === 'number' ? tag.id : 0, name: tag.name });
      }
    }
    return result;
  }

  // 正文预览清洗:草稿正文是 Markdown/BBCode,列表里只做两行预览,把图片占位与引用块噪音收干净。
  static cleanExcerpt(excerpt?: string, reply?: string): string {
    let text: string = typeof excerpt === 'string' && excerpt.length > 0
      ? excerpt
      : (typeof reply === 'string' ? reply : '');
    // ![alt](upload://xxx) / ![alt](http...) 图片 → [图片]
    text = text.replace(/!\[[^\]]*\]\([^)]*\)/g, '[图片]');
    // [quote=...] ... [/quote] 引用块整段去掉(跨行)
    text = text.replace(/\[quote=[^\]]*\][\s\S]*?\[\/quote\]/g, '');
    // 折叠多余空行/空白
    text = text.replace(/\s+/g, ' ').trim();
    return text;
  }

  private forwardFailure(response: NetworkResult<string>): NetworkResult<DraftPage> {
    return {
      success: false,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      error: response.error
    };
  }

  private unexpectedResponse(statusCode: number, challengeState: ChallengeState, message: string): NetworkResult<DraftPage> {
    return {
      success: false,
      statusCode: statusCode,
      challengeState: challengeState,
      error: {
        code: NetworkErrorCode.UNEXPECTED_RESPONSE,
        message: message,
        requiresChallenge: challengeState !== ChallengeState.NONE
      }
    };
  }
}
