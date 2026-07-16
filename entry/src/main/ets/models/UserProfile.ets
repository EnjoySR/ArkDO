// 个人中心数据模型:字段分别来自
// /u/{username}.json(资料)、/u/{username}/summary.json(统计+徽章)、/user_actions.json(最近活动)。
import { TopicTag } from './Topic';
import { User } from './User';

export interface UserProfileDetail {
  id: number;
  username: string;
  displayName?: string;
  // 用户头衔(Discourse user.title,如「活跃用户」),站点可自定义。
  title?: string;
  trustLevel?: number;
  createdAt?: string;
  lastPostedAt?: string;
  badgeCount?: number;
  profileViewCount?: number;
  // 头像与 flair:他人主页要自己渲染身份区,不像「我的」页能拿现成的 accountUser。
  // 字段语义同 models/User.ets,取自 /u/{username}.json 的 user 对象。
  avatarTemplate?: string;
  animatedAvatar?: string;
  flairUrl?: string;
  flairBgColor?: string;
  flairColor?: string;
  flairName?: string;
  // 个人简介纯文本(bio_excerpt);bio_cooked 是 HTML,身份区只要两行摘要故取前者。
  bioExcerpt?: string;
  // discourse-follow 插件(站点已启用)。canFollow 决定关注按钮显不显示——
  // 看自己、或对方 allow_people_to_follow_me=false 时服务端给 false。
  // isFollowed 是当前登录者是否已关注 TA,决定按钮文案与配色。
  canFollow?: boolean;
  isFollowed?: boolean;
  totalFollowers?: number;
  totalFollowing?: number;
  // discourse-category-experts 插件。字段在 payload 里存在(哪怕空数组)= 插件启用 = 显示「认可」按钮。
  // 值是当前登录者已认可 TA 的分类 id 列表,长度决定「在 N 个类别中得到认可」文案。
  endorsementAvailable?: boolean;
  endorsedCategoryIds?: number[];
  // 昵称后的状态表情短名(user.status.emoji,如 nerd_face),经 EmojiUrlRegistry 查 url,与帖子详情同源。
  // (昵称后的徽章图标不做:个人页接口只给精选徽章,与帖子头的 show_in_post_header 徽章是两套数据,凑不到一致。)
  statusEmoji?: string;
}

// 「认可」弹窗里可勾选的一个分类(discourse-category-experts 的 endorsable-categories)。
export interface EndorsableCategory {
  id: number;
  name: string;
  // 分类色点用,前面加个圆点与 App 其余分类展示一致。
  color?: string;
}

export interface EndorsableCategoriesResult {
  categories: EndorsableCategory[];
  // 「今天还剩 N 个认可」:服务端每日限额,0 时认可按钮置灰。
  remainingEndorsements: number;
}

// 他人主页身份区要把 UserProfileDetail 喂给 UserAvatar(它只吃 User)。
export function toAvatarUser(detail: UserProfileDetail): User {
  return {
    id: detail.id,
    username: detail.username,
    displayName: detail.displayName,
    avatarTemplate: detail.avatarTemplate,
    animatedAvatar: detail.animatedAvatar,
    flairUrl: detail.flairUrl,
    flairBgColor: detail.flairBgColor,
    flairColor: detail.flairColor,
    flairName: detail.flairName
  };
}

export interface UserSummaryStats {
  daysVisited: number;
  // 阅读时长,秒。
  timeReadSeconds: number;
  likesGiven: number;
  likesReceived: number;
  topicCount: number;
  postCount: number;
  topicsEntered: number;
  // solved 插件的被采纳数,站点未启用时为 undefined。
  solvedCount?: number;
}

// Discourse badge_type_id:1=金 2=银 3=铜。
// 图标二选一:imageUrl(站点上传的图片徽章,CDN 直链)优先,否则 icon(FontAwesome 名,
// 与 rawfile/fa_icons 的文件名一致,按徽章等级色染色)。
export interface UserBadgeItem {
  id: number;
  name: string;
  badgeTypeId: number;
  icon?: string;
  imageUrl?: string;
  // 本用户获得该徽章的次数(可重复获得的徽章 >1 时展示 ×N)。
  grantCount?: number;
  // 「全部徽章」页额外字段(summary 精简版不含):徽章说明与授予时间。
  description?: string;
  grantedAt?: string;
}

// 「全部徽章」页按等级(金/银/铜)分组。
export interface UserBadgeGroup {
  typeId: number;
  // 分组标题:优先服务端 badge_types.name,否则金牌/银牌/铜牌兜底。
  typeName: string;
  badges: UserBadgeItem[];
}

// summary.json 的 user_summary.topics:按获赞排序的热门话题。
export interface UserTopTopic {
  topicId: number;
  slug?: string;
  title: string;
  likeCount: number;
  createdAt?: string;
  categoryId?: number;
}

// user_summary.replies:按获赞排序的热门回复,指向具体楼层(postNumber)。
export interface UserTopReply {
  topicId: number;
  postNumber: number;
  topicTitle: string;
  slug?: string;
  likeCount: number;
  createdAt?: string;
  categoryId?: number;
}

// 互动圈一格:某人 + 互动次数。来自 most_replied_to_users / most_liked_users / most_liked_by_users。
export interface UserInteraction {
  user: User;
  count: number;
}

// 他人主页要的比「我的」页多:官网「热门回复/热门话题/最多回复至/被谁赞得最多/赞最多」
// 全部来自这一个 summary.json,此前只映射了 stats + badges,其余字段被丢弃。
export interface UserSummary {
  stats: UserSummaryStats;
  topBadges: UserBadgeItem[];
  topTopics: UserTopTopic[];
  topReplies: UserTopReply[];
  // 互动圈三行:他常回复谁 / 他赞过谁 / 谁赞他。
  mostRepliedToUsers: UserInteraction[];
  mostLikedUsers: UserInteraction[];
  mostLikedByUsers: UserInteraction[];
}

// /solution/by_user.json 一条:他被采纳为解决方案的回复。
// 是四个插件页里唯一保留的——被采纳的答案是能力硬证据,入口挂在统计格「解决方案」上。
export interface SolvedPostItem {
  postId: number;
  topicId: number;
  postNumber: number;
  topicTitle: string;
  slug?: string;
  // 他那条答案的正文摘要(纯文本)。
  excerpt: string;
  categoryId?: number;
  createdAt?: string;
}

export interface SolvedPostPage {
  items: SolvedPostItem[];
  hasMore: boolean;
}

// /user_actions.json 的 action_type:4=发布话题 5=回复。
export enum UserActionType {
  NEW_TOPIC = 4,
  REPLY = 5
}

export interface UserActivityItem {
  actionType: number;
  topicId: number;
  postNumber?: number;
  title: string;
  // 该动作对应楼层的正文摘要(纯文本);列表页用,个人中心预览不显示。
  excerpt: string;
  categoryId?: number;
  tags: TopicTag[];
  createdAt?: string;
  // 该动作对应楼层的作者(user_actions 的 avatar_template/username/name);列表左侧出头像。
  // 接口不返回 flair 字段,故头像无右下角标。
  author?: User;
}

// 一页用户动态 + 是否还有更多(user_actions 按 offset 翻页)。
export interface UserActivityPage {
  items: UserActivityItem[];
  hasMore: boolean;
}
