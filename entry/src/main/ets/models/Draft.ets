// 草稿列表项:来自 /drafts.json 的 drafts[]。
// Discourse 一条草稿的关键信息藏在 data 字段(一个内嵌 JSON 字符串),需二次解析取出
// 正文/标题/分类/标签;action 区分类型:createTopic(新主题)/reply(回帖)/privateMessage(私信)。
export interface Draft {
  // 草稿主键:new_topic_<ts> / topic_<id> / new_private_message_<ts>。删除/自动存都按它定位。
  draftKey: string;
  sequence: number;
  action: DraftAction;
  // 真实标题:新主题/私信取 data.title,回帖取顶层 title(所回主题的标题)。**可能为空**
  // (只写了正文没写标题的草稿)。续写回填必须用它,不能用 displayTitle——否则占位串会被
  // 当成真标题灌进标题输入框。
  title: string;
  // 列表展示用:title 为空时回退占位文案。仅用于渲染,不可回填。
  displayTitle: string;
  // 正文预览(已做轻度清洗:图片占位换成「[图片]」)。
  excerpt: string;
  createdAt: string;
  // 回帖草稿:所回主题 id(点击直接进该主题)。
  topicId?: number;
  // 新主题草稿续写用:分类 id、标签、正文原文。
  categoryId?: number;
  // 标签带 id:续写时要用 id 做联想 refine,回存草稿也要写回 {id,name}。
  tags: DraftTagRef[];
  reply: string;
}

// 草稿里的标签引用。放在模型层(而非服务层)供两边共用,避免 model↔service 循环引用。
export interface DraftTagRef {
  id: number;
  name: string;
}

export enum DraftAction {
  NEW_TOPIC = 'createTopic',
  REPLY = 'reply',
  PRIVATE_MESSAGE = 'privateMessage',
  OTHER = 'other'
}

// 一页草稿。/drafts.json 无分页游标,靠「本页条数 == 请求 limit」推断是否还有下一页。
export interface DraftPage {
  drafts: Draft[];
  hasMore: boolean;
}
