import { AppConstants } from '../../common/constants/AppConstants';
import { NotificationItem, RawNotification, RawNotificationData, RawNotificationsResponse } from '../../models/Notification';
import { JsonNetworkClient, NetworkErrorCode, NetworkResult } from '../network/NetworkTypes';

const LOG_TAG: string = '[ArkDO][NotificationApi]';
const MARK_READ_PATH: string = '/notifications/mark-read';

// Discourse notification_type 枚举(核心稳定值)。
const T_MENTIONED: number = 1;
const T_REPLIED: number = 2;
const T_QUOTED: number = 3;
const T_EDITED: number = 4;
const T_LIKED: number = 5;
const T_PRIVATE_MESSAGE: number = 6;
const T_INVITED_TO_PM: number = 7;
const T_INVITEE_ACCEPTED: number = 8;
const T_POSTED: number = 9;
const T_LINKED: number = 11;
const T_GRANTED_BADGE: number = 12;
const T_GROUP_MENTIONED: number = 15;
const T_GROUP_MESSAGE_SUMMARY: number = 16;
const T_WATCHING_FIRST_POST: number = 17;
const T_LIKED_CONSOLIDATED: number = 19;
const T_CUSTOM: number = 14;
const T_POST_APPROVED: number = 20;
const T_BOOKMARK_REMINDER: number = 24;
const T_REACTION: number = 25;
const T_BOOST: number = 43;        // linux.do 的 Boost 助力
const T_FOLLOWING: number = 801;   // linux.do 自定义:关注的用户有新动态

// 角标配色(对齐设计稿)。
const C_REPLY: string = '#3B82F6';
const C_LIKE: string = '#F5455C';
const C_MENTION: string = '#6366F1';
const C_PM: string = '#8B5CF6';
const C_BADGE: string = '#E0A100';
const C_BOOK: string = '#FB923C';
const C_QUOTE: string = '#64748B';
const C_WATCH: string = '#F5A623';
const C_GRAY: string = '#9CA3AF';
const C_APPROVED: string = '#22C55E';

interface NotificationVisual {
  iconId: string;
  iconColor: string;
  actionText: string;
  hasActor: boolean; // false=系统类(无发起人),用系统图标圈代替头像
}

export class NotificationApi {
  private bridge: JsonNetworkClient;

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  // 拉取通知列表。首次进页用 recent=true(服务端顺带 bump seen 清红点);
  // 加载更多用 offset 且不带 recent(避免重复 bump)。
  async load(limit: number, offset: number, recent: boolean): Promise<NetworkResult<NotificationItem[]>> {
    let path: string = `/notifications.json?limit=${limit}&offset=${offset}`;
    if (recent) {
      path += '&recent=true&bump_last_seen_reviewable=true';
    }

    const response: NetworkResult<string> = await this.bridge.getJson(path);
    if (!response.success) {
      return {
        success: false,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        error: response.error
      };
    }

    const items: NotificationItem[] = [];
    try {
      const payload: RawNotificationsResponse = JSON.parse(response.data ? response.data : '{}') as RawNotificationsResponse;
      const list: RawNotification[] = payload.notifications ? payload.notifications : [];
      for (let index: number = 0; index < list.length; index++) {
        const parsed: NotificationItem | undefined = this.parseOne(list[index]);
        if (parsed) {
          items.push(parsed);
        }
      }
    } catch (error) {
      return {
        success: false,
        statusCode: response.statusCode,
        challengeState: response.challengeState,
        error: {
          code: NetworkErrorCode.UNEXPECTED_RESPONSE,
          message: '通知数据解析失败。',
          requiresChallenge: false
        }
      };
    }

    console.info(`${LOG_TAG} loaded count=${items.length} recent=${recent} offset=${offset}`);
    return {
      success: true,
      statusCode: response.statusCode,
      challengeState: response.challengeState,
      data: items
    };
  }

  // 标记单条已读。
  async markRead(id: number): Promise<boolean> {
    const response: NetworkResult<string> = await this.bridge.putForm(MARK_READ_PATH, `id=${id}`, {
      referrer: `${AppConstants.BASE_URL}/`,
      notifyChallenge: false
    });
    console.info(`${LOG_TAG} markRead id=${id} success=${response.success}`);
    return response.success;
  }

  // 全部标记已读(不带 id)。
  async markAllRead(): Promise<boolean> {
    const response: NetworkResult<string> = await this.bridge.putForm(MARK_READ_PATH, '', {
      referrer: `${AppConstants.BASE_URL}/`,
      notifyChallenge: false
    });
    console.info(`${LOG_TAG} markAllRead success=${response.success}`);
    return response.success;
  }

  private parseOne(raw: RawNotification): NotificationItem | undefined {
    if (typeof raw.id !== 'number' || typeof raw.notification_type !== 'number') {
      return undefined;
    }
    const data: RawNotificationData = raw.data ? raw.data : {};
    const actor: string = this.resolveActor(raw, data);
    const visual: NotificationVisual = this.describe(raw.notification_type, data, raw.post_number, actor.length > 0);
    const actorName: string = visual.hasActor ? actor : '';
    const title: string = this.resolveTitle(raw, data);
    // 头像只看模板是否存在,不受类型映射(hasActor)限制:未映射类型只要有头像就照样显示。
    const avatarTemplate: string | undefined =
      raw.acting_user_avatar_template && raw.acting_user_avatar_template.length > 0
        ? raw.acting_user_avatar_template
        : undefined;

    return {
      id: raw.id,
      type: raw.notification_type,
      read: raw.read === true,
      createdAt: raw.created_at ? raw.created_at : '',
      actorName: actorName,
      actorUsername: actor,
      avatarTemplate: avatarTemplate,
      actionText: visual.actionText,
      title: title,
      topicId: typeof raw.topic_id === 'number' ? raw.topic_id : undefined,
      postNumber: typeof raw.post_number === 'number' ? raw.post_number : undefined,
      slug: raw.slug,
      iconId: visual.iconId,
      iconColor: visual.iconColor
    };
  }

  private resolveActor(raw: RawNotification, data: RawNotificationData): string {
    if (raw.acting_user_name && raw.acting_user_name.length > 0) {
      return raw.acting_user_name;
    }
    if (data.display_username && data.display_username.length > 0) {
      return data.display_username;
    }
    if (data.original_username && data.original_username.length > 0) {
      return data.original_username;
    }
    if (data.username && data.username.length > 0) {
      return data.username;
    }
    return '';
  }

  private resolveTitle(raw: RawNotification, data: RawNotificationData): string {
    if (raw.notification_type === T_GRANTED_BADGE && data.badge_name) {
      return data.badge_name;
    }
    if (raw.fancy_title && raw.fancy_title.length > 0) {
      return raw.fancy_title;
    }
    if (data.topic_title && data.topic_title.length > 0) {
      return data.topic_title;
    }
    if (data.badge_name && data.badge_name.length > 0) {
      return data.badge_name;
    }
    return '';
  }

  // post_number>1 视为对已有主题的回复,否则视为新主题。用于"关注动态"等无固定动词的类型。
  private postVerb(postNumber?: number): string {
    return postNumber !== undefined && postNumber > 1 ? '回复了主题' : '发布了主题';
  }

  // 类型 → 图标/颜色/文案。未覆盖但有发起人的类型走"智能兜底"(头像+comment+按楼号推动词),
  // 纯系统类才落到铃铛。hasActorHint=是否解析到发起人名。
  private describe(type: number, data: RawNotificationData, postNumber: number | undefined, hasActorHint: boolean): NotificationVisual {
    if (type === T_FOLLOWING) {
      return { iconId: 'user-plus', iconColor: C_REPLY, actionText: this.postVerb(postNumber), hasActor: true };
    }
    if (type === T_CUSTOM) {
      return { iconId: 'comment', iconColor: C_QUOTE, actionText: this.postVerb(postNumber), hasActor: true };
    }
    if (type === T_BOOST) {
      return { iconId: 'rocket', iconColor: C_WATCH, actionText: '为你的帖子助力', hasActor: true };
    }
    if (type === T_POST_APPROVED) {
      return { iconId: 'circle-check', iconColor: C_APPROVED, actionText: '你的帖子已通过审核', hasActor: false };
    }
    if (type === T_REPLIED || type === T_POSTED) {
      return { iconId: 'reply', iconColor: C_REPLY, actionText: type === T_POSTED ? '回复了主题' : '回复了你', hasActor: true };
    }
    if (type === T_MENTIONED) {
      return { iconId: 'at', iconColor: C_MENTION, actionText: '提到了你', hasActor: true };
    }
    if (type === T_GROUP_MENTIONED) {
      const group: string = data.group_name ? `@${data.group_name}` : '群组';
      return { iconId: 'at', iconColor: C_MENTION, actionText: `在 ${group} 提到了你`, hasActor: true };
    }
    if (type === T_LIKED || type === T_LIKED_CONSOLIDATED || type === T_REACTION) {
      return { iconId: 'heart', iconColor: C_LIKE, actionText: type === T_REACTION ? '点了表情回应' : '赞了你的帖子', hasActor: true };
    }
    if (type === T_QUOTED) {
      return { iconId: 'quote-right', iconColor: C_QUOTE, actionText: '引用了你', hasActor: true };
    }
    if (type === T_LINKED) {
      return { iconId: 'link', iconColor: C_QUOTE, actionText: '引用了你的帖子', hasActor: true };
    }
    if (type === T_PRIVATE_MESSAGE || type === T_INVITED_TO_PM || type === T_GROUP_MESSAGE_SUMMARY) {
      return { iconId: 'envelope', iconColor: C_PM, actionText: type === T_INVITED_TO_PM ? '邀请你参与私信' : '给你发了私信', hasActor: true };
    }
    if (type === T_INVITEE_ACCEPTED) {
      return { iconId: 'envelope', iconColor: C_PM, actionText: '接受了你的邀请', hasActor: true };
    }
    if (type === T_EDITED) {
      return { iconId: 'reply', iconColor: C_GRAY, actionText: '编辑了你的帖子', hasActor: true };
    }
    if (type === T_GRANTED_BADGE) {
      return { iconId: 'certificate', iconColor: C_BADGE, actionText: '你获得了徽章', hasActor: false };
    }
    if (type === T_BOOKMARK_REMINDER) {
      return { iconId: 'bookmark', iconColor: C_BOOK, actionText: '书签提醒', hasActor: false };
    }
    if (type === T_WATCHING_FIRST_POST) {
      return { iconId: 'bell', iconColor: C_WATCH, actionText: '发布了新主题', hasActor: true };
    }
    // 智能兜底:未知类型但有发起人 → 当作帖子动态(头像 + comment 角标 + 按楼号推动词);
    // 无发起人才落到系统铃铛。避免"有头像却显示灰铃铛"。
    if (hasActorHint) {
      return { iconId: 'comment', iconColor: C_QUOTE, actionText: this.postVerb(postNumber), hasActor: true };
    }
    return { iconId: 'bell', iconColor: C_GRAY, actionText: '有一条新通知', hasActor: false };
  }
}
