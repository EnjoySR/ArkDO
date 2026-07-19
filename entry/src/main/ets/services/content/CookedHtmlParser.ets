import { AppConstants } from '../../common/constants/AppConstants';
import { TopicCategory } from '../../models/Topic';

// 行内小图(emoji/小图标)的尺寸上限,与渲染层 PostRichContent.SMALL_IMAGE_MAX 对齐:
// 宽或高超过它的独立 <img>(或动图)视为整幅内容图,提升为 IMAGE 块,不再压成 18px 行内图。
const INLINE_IMAGE_MAX: number = 48;

// 站内 emoji 图片的相对路径前缀,resolveUrl 据此把它们挂 CDN 而非主站。
const EMOJI_PATH_PREFIX: string = '/images/emoji/';

export enum RichBlockType {
  PARAGRAPH = 'paragraph',
  HEADING = 'heading',
  QUOTE = 'quote',
  // Discourse 话题/帖子引用(<aside class="quote" data-topic data-post>,带 quote-title__text-content 头部):
  // 头部含头像 + 话题标题链接 + 分类徽章,正文是被引用楼的截断预览。渲染成带头部的引用卡,右上角可展开拉全文。
  TOPIC_QUOTE = 'topic_quote',
  // Obsidian/Discourse callout(discourse-quote-callouts 主题组件):首段以 [!type]± 开头的
  // blockquote → 彩色可折叠提示框。type 决定图标/主色,+ 默认展开、- 默认折叠、无后缀不可折叠。
  CALLOUT = 'callout',
  CODE = 'code',
  IMAGE = 'image',
  LIST = 'list',
  DISCLOSURE = 'disclosure',
  // discourse-spoiler-alert 块级剧透:<div class="spoiler">…</div>,揭示前整块遮蔽。
  SPOILER = 'spoiler',
  DIVIDER = 'divider',
  POLL = 'poll',
  ONEBOX = 'onebox',
  // <audio>/<video>:原生播放器就地播放。src 为解析后的媒体 URL(和图片同源 /uploads/),
  // 直接喂给 AVPlayer / Video 组件流式播放。
  AUDIO = 'audio',
  VIDEO = 'video',
  // discourse-math 块级公式(<div class="math">):text 存裸 LaTeX(displayMode=true),
  // 渲染层交离屏 KaTeX 引擎出图后居中显示。
  MATH = 'math',
  // Markdown 表格(<table>,Discourse 常裹一层 <div class="md-table">):抽成行/单元格结构,
  // 渲染层用等宽列对齐 + 横向 Scroll,过宽时左右滑动而不撑破栏宽。
  TABLE = 'table',
  UNSUPPORTED = 'unsupported'
}

export enum RichInlineType {
  TEXT = 'text',
  LINK = 'link',
  CODE = 'code',
  IMAGE = 'image',
  // discourse-math 行内公式(<span class="math">):text 存裸 LaTeX(displayMode=false),
  // 渲染层出图后以 ImageSpan 基线内联,保证周围文字仍走原生 Text、字体字号与全帖一致。
  MATH = 'math',
  LINE_BREAK = 'line_break'
}

export interface RichInlineNode {
  type: RichInlineType;
  text: string;
  href?: string;
  src?: string;
  alt?: string;
  bold?: boolean;
  italic?: boolean;
  code?: boolean;
  // 附件下载链接(Discourse <a class="attachment"> 或指向 /uploads/ 的链接):渲染时前置下载图标,点击触发原生下载。
  attachment?: boolean;
  // 行内剧透(<span class="spoiler">):揭示前渲染为涂抹条,点击后显示。
  spoiler?: boolean;
  // 段落分隔用的换行(仅 LINE_BREAK):由 mergeAdjacentParagraphs 在合并的相邻段落之间插入,
  // 渲染成双换行空行营造段距。与 <br> 普通换行区分,后者仍是单换行。
  paragraphBreak?: boolean;
}

export interface RichListItem {
  inlines: RichInlineNode[];
  // 列表项内含块级图(lightbox/大图)时改用 blocks:文字成段落、图片各自成块级 IMAGE,
  // 避免大图退化成 18px 行内小图。纯文字项仍只用 inlines(blocks 缺省)。
  blocks?: RichBlock[];
}

// TABLE 单元格:行内节点序列 + 是否表头(<th> 或位于 <thead> 内)。
export interface RichTableCell {
  inlines: RichInlineNode[];
  header?: boolean;
}

export interface RichTableRow {
  cells: RichTableCell[];
  // 整行是否表头行(全部单元格来自 thead / 全为 th)。渲染表头行加底色与粗体。
  header?: boolean;
}

export interface RichBlock {
  type: RichBlockType;
  inlines?: RichInlineNode[];
  blocks?: RichBlock[];
  items?: RichListItem[];
  // TABLE 块:按出现顺序的行,每行含若干单元格。
  tableRows?: RichTableRow[];
  text?: string;
  title?: string;
  unsupportedKind?: string;
  language?: string;
  src?: string;
  alt?: string;
  width?: number;
  height?: number;
  href?: string;
  // AUDIO/VIDEO 块:媒体 MIME(如 audio/mp4、video/mp4),来自 <source type>,供播放器与降级判断参考。
  mediaType?: string;
  ordered?: boolean;
  level?: number;
  // POLL 块:data-poll-name,用于在正文正确位置占位、并按名字关联 TopicPost.polls 的动态数据。
  pollName?: string;
  // ONEBOX(链接预览卡片)字段:域名/站点图标/描述/缩略图;title 复用上面的 title,跳转 URL 复用 href。
  domain?: string;
  faviconUrl?: string;
  description?: string;
  thumbnailUrl?: string;
  // CALLOUT 块字段:calloutKind 归一后的类型(用于无标题时回退成类型名);calloutColor 主色(标题+图标);
  // calloutIcon FontAwesome 图标 id(对应 rawfile/fa_icons);collapsible 是否可折叠;
  // defaultExpanded 折叠态默认(+→true、-→false);titleInlines 标题段行内节点(可含粗体/链接);blocks 为正文子块。
  calloutKind?: string;
  calloutColor?: string;
  calloutIcon?: string;
  collapsible?: boolean;
  defaultExpanded?: boolean;
  titleInlines?: RichInlineNode[];
  // TOPIC_QUOTE 头部数据:头像 URL / 作者用户名 / 话题标题 / 目标 topic 与楼号(供展开按 by_number 拉全文)/
  // 分类徽章。折叠预览的 cooked 复用 text,话题链接复用 href。
  quoteAvatarUrl?: string;
  quoteAuthor?: string;
  quoteTitle?: string;
  quoteTopicId?: number;
  quotePostNumber?: number;
  quoteCategory?: TopicCategory;
  // 同帖回复引用(title 只有「显示名:」无话题链接):跳转是在本帖内往上定位到那一楼 → 用 arrow-up;
  // 跨帖引用(有话题链接)则是打开另一个帖子 → 用 chevron-right。
  quoteIsReply?: boolean;
}

// callout 类型别名 → 归一类型(与 discourse-quote-callouts settings.yml 的 alias 一致)。
const CALLOUT_ALIASES: Map<string, string> = ((): Map<string, string> => {
  const m: Map<string, string> = new Map();
  m.set('summary', 'abstract');
  m.set('tldr', 'abstract');
  m.set('hint', 'tip');
  m.set('important', 'tip');
  m.set('check', 'success');
  m.set('done', 'success');
  m.set('help', 'question');
  m.set('faq', 'question');
  m.set('caution', 'warning');
  m.set('attention', 'warning');
  m.set('fail', 'failure');
  m.set('missing', 'failure');
  m.set('error', 'danger');
  m.set('cite', 'quote');
  return m;
})();

interface CalloutStyleDef {
  color: string;
  icon: string;
}

// 归一类型 → 主色 + 图标 id。取值为 discourse-quote-callouts 上游默认(settings.yml)。
const CALLOUT_STYLES: Map<string, CalloutStyleDef> = ((): Map<string, CalloutStyleDef> => {
  const m: Map<string, CalloutStyleDef> = new Map();
  m.set('note', { color: '#086ddd', icon: 'far-pen-to-square' });
  m.set('abstract', { color: '#00bfbc', icon: 'far-clipboard' });
  m.set('info', { color: '#027aff', icon: 'far-lightbulb' });
  m.set('todo', { color: '#027aff', icon: 'far-circle-check' });
  m.set('tip', { color: '#00bfbc', icon: 'fire-flame-curved' });
  m.set('success', { color: '#44cf6e', icon: 'check' });
  m.set('question', { color: '#ec7500', icon: 'far-circle-question' });
  m.set('warning', { color: '#ec7500', icon: 'triangle-exclamation' });
  m.set('failure', { color: '#e93147', icon: 'xmark' });
  m.set('danger', { color: '#e93147', icon: 'bolt' });
  m.set('bug', { color: '#e93147', icon: 'bug' });
  m.set('example', { color: '#7852ee', icon: 'list' });
  m.set('quote', { color: '#9e9e9e', icon: 'quote-left' });
  return m;
})();

// 无法识别的类型:回退主色/图标(settings.yml 的 callout_fallback_*),行为按 note 处理。
const CALLOUT_FALLBACK: CalloutStyleDef = { color: '#027aff', icon: 'far-pen-to-square' };

interface CalloutStyle {
  kind: string;
  color: string;
  icon: string;
}

// blockquote 首段命中 [!type]± 才是 callout。type 仅取 ASCII 字母(与上游一致),
// 非字母(如 [!名称])不识别,原样退回普通引用。可选 +/- 折叠标记,后随可选一个空格。
const CALLOUT_MARKER: RegExp = /^\s*\[!([a-zA-Z]+)\]([+-]?)\s?/;

class InlineState {
  bold: number = 0;
  italic: number = 0;
  code: number = 0;
  hrefStack: string[] = [];
  // 与 hrefStack 同步入栈:当前链接是否为附件下载链接。
  attachmentStack: boolean[] = [];
  // 每遇到一个 <span> 就入栈(是否带 spoiler class);</span> 出栈。
  // 闭合标签不带 class,只能整体跟踪 span 嵌套才能正确配对。
  spanSpoilerStack: boolean[] = [];

  clone(): InlineState {
    const state: InlineState = new InlineState();
    state.bold = this.bold;
    state.italic = this.italic;
    state.code = this.code;
    state.hrefStack = this.hrefStack.slice();
    state.attachmentStack = this.attachmentStack.slice();
    state.spanSpoilerStack = this.spanSpoilerStack.slice();
    return state;
  }

  currentHref(): string {
    if (this.hrefStack.length === 0) {
      return '';
    }
    return this.hrefStack[this.hrefStack.length - 1];
  }

  currentAttachment(): boolean {
    if (this.attachmentStack.length === 0) {
      return false;
    }
    return this.attachmentStack[this.attachmentStack.length - 1];
  }

  currentSpoiler(): boolean {
    for (let index: number = 0; index < this.spanSpoilerStack.length; index++) {
      if (this.spanSpoilerStack[index]) {
        return true;
      }
    }
    return false;
  }
}

interface SummaryInfo {
  title: string;
  contentHtml: string;
}

interface LightboxUnit {
  before: string;
  html: string;
  after: string;
}

export class CookedHtmlParser {
  static parse(html: string): RichBlock[] {
    const source: string = html ? html : '';
    const blocks: RichBlock[] = CookedHtmlParser.parseBlocks(source);
    const visible: RichBlock[] = blocks.filter((block: RichBlock) => CookedHtmlParser.hasBlockContent(block));
    return CookedHtmlParser.mergeAdjacentParagraphs(visible);
  }

  // 把相邻的纯文本段落(PARAGRAPH)合并进同一段,块之间插入 paragraphBreak 换行。原因:每个 PARAGRAPH
  // 渲染成一个独立 Text,而 ArkUI 的 Text 选区是组件私有的,跨 Text 无法连续选中/复制。合并后连续
  // 正文段落进同一个 Text,长按可一路选到底(参考帖 2.x 用 <br> 同段能连选、3.x 另起 <p> 就断)。
  // 只合并相邻 PARAGRAPH;标题/图片/引用/列表/代码/onebox 等非文本块天然隔断,跨它们仍不可连选。
  private static mergeAdjacentParagraphs(blocks: RichBlock[]): RichBlock[] {
    const out: RichBlock[] = [];
    for (let i: number = 0; i < blocks.length; i++) {
      const block: RichBlock = blocks[i];
      const prev: RichBlock | undefined = out.length > 0 ? out[out.length - 1] : undefined;
      if (block.type === RichBlockType.PARAGRAPH && block.inlines &&
        prev && prev.type === RichBlockType.PARAGRAPH && prev.inlines) {
        const separator: RichInlineNode = { type: RichInlineType.LINE_BREAK, text: '\n', paragraphBreak: true };
        const merged: RichInlineNode[] = prev.inlines.concat([separator], block.inlines);
        out[out.length - 1] = { type: RichBlockType.PARAGRAPH, inlines: merged };
      } else {
        out.push(block);
      }
    }
    return out;
  }

  static toPlainText(html: string): string {
    return CookedHtmlParser.normalizeText(CookedHtmlParser.stripTagsKeepingLines(html));
  }

  // 把一段(通常是单段落的)HTML 解析为行内节点(文字 + 行内 emoji 图片等),
  // 供 boost 气泡这类需要「文字与 emoji 混排」的短内容行内渲染。外层 <p>/<div> 会被忽略。
  static toInlineNodes(html: string): RichInlineNode[] {
    return CookedHtmlParser.parseInlines(html ? html : '');
  }

  private static parseBlocks(html: string): RichBlock[] {
    const blocks: RichBlock[] = [];
    let index: number = 0;
    let pendingInlineHtml: string = '';

    const flushPendingInline = (): void => {
      const inlines: RichInlineNode[] = CookedHtmlParser.parseInlines(pendingInlineHtml);
      pendingInlineHtml = '';
      if (CookedHtmlParser.hasVisibleInlines(inlines)) {
        blocks.push({
          type: RichBlockType.PARAGRAPH,
          inlines
        });
      }
    };

    while (index < html.length) {
      const nextTagStart: number = html.indexOf('<', index);
      if (nextTagStart < 0) {
        pendingInlineHtml = `${pendingInlineHtml}${html.substring(index)}`;
        break;
      }

      if (nextTagStart > index) {
        pendingInlineHtml = `${pendingInlineHtml}${html.substring(index, nextTagStart)}`;
      }

      const tagEnd: number = CookedHtmlParser.findTagEnd(html, nextTagStart);
      if (tagEnd < 0) {
        pendingInlineHtml = `${pendingInlineHtml}${html.substring(nextTagStart)}`;
        break;
      }

      const openTag: string = html.substring(nextTagStart, tagEnd + 1);
      if (CookedHtmlParser.isClosingTag(openTag)) {
        // 行内元素的闭标签(</a></span></strong>…)属于当前 pending 行内内容,必须保留;
        // 否则未包 <p> 的裸文本(如引用预览、blockquote 直排文本)里 <a>…</a> 会失衡,
        // 闭标签被丢弃后其后文本被误当作未闭合链接的一部分整段染蓝可点。仅块级闭标签可安全跳过。
        if (!CookedHtmlParser.isBlockTag(CookedHtmlParser.getTagName(openTag))) {
          pendingInlineHtml = `${pendingInlineHtml}${openTag}`;
        }
        index = tagEnd + 1;
        continue;
      }

      const tagName: string = CookedHtmlParser.getTagName(openTag);
      if (tagName.length === 0) {
        pendingInlineHtml = `${pendingInlineHtml}${openTag}`;
        index = tagEnd + 1;
        continue;
      }

      if (!CookedHtmlParser.isBlockTag(tagName)) {
        pendingInlineHtml = `${pendingInlineHtml}${openTag}`;
        index = tagEnd + 1;
        continue;
      }

      flushPendingInline();

      if (tagName === 'hr') {
        blocks.push({ type: RichBlockType.DIVIDER });
        index = tagEnd + 1;
        continue;
      }

      if (tagName === 'img') {
        const imageBlock: RichBlock | undefined = CookedHtmlParser.imageBlockFromTag(openTag, '');
        if (imageBlock) {
          blocks.push(imageBlock);
        }
        index = tagEnd + 1;
        continue;
      }

      const closeStart: number = CookedHtmlParser.findClosingTag(html, tagEnd + 1, tagName);
      if (closeStart < 0) {
        pendingInlineHtml = `${pendingInlineHtml}${openTag}`;
        index = tagEnd + 1;
        continue;
      }

      const closeEnd: number = CookedHtmlParser.findTagEnd(html, closeStart);
      if (closeEnd < 0) {
        index = html.length;
        continue;
      }

      const innerHtml: string = html.substring(tagEnd + 1, closeStart);
      blocks.push(...CookedHtmlParser.blockFromElement(tagName, openTag, innerHtml));
      index = closeEnd + 1;
    }

    flushPendingInline();
    return blocks;
  }

  private static blockFromElement(tagName: string, openTag: string, innerHtml: string): RichBlock[] {
    if (tagName === 'p') {
      const imageBlock: RichBlock | undefined = CookedHtmlParser.singleImageParagraph(innerHtml);
      if (imageBlock) {
        return [imageBlock];
      }
      const imageBlocks: RichBlock[] = CookedHtmlParser.imageContainerBlocks(innerHtml);
      if (imageBlocks.length > 0) {
        return imageBlocks;
      }
      // Discourse 会把 <audio>/<video> 裹进 <p>(内部还带一个降级 <a> 链接)。这里先把内嵌媒体
      // 提升为播放块,否则会落到 mixedBlocks/行内解析,只剩那条降级链接被当正文渲染成裸链接。
      const mediaBlocks: RichBlock[] | undefined = CookedHtmlParser.mediaParagraphBlocks(innerHtml);
      if (mediaBlocks) {
        return mediaBlocks;
      }
      return CookedHtmlParser.mixedBlocks(innerHtml);
    }

    if (CookedHtmlParser.isHeadingTag(tagName)) {
      return [{
        type: RichBlockType.HEADING,
        level: Number(tagName.substring(1)),
        inlines: CookedHtmlParser.parseInlines(innerHtml)
      }];
    }

    if (tagName === 'aside' && CookedHtmlParser.hasClass(openTag, 'quote')) {
      // Discourse 话题/帖子引用:头部(头像+标题链接+分类徽章)抽成结构化数据,正文取截断预览,
      // 渲染成带头部的引用卡。兼容新式 quote-title__text-content 与老式 <div class="title"> 两种标记。
      // 判据是标题里有没有指向话题的 <a> 链接:有=跨帖引用→卡片;无(同帖内引用楼层,只显示「用户名:」)
      // 或缺 data-topic → 返回 undefined,落到下方回退成普通引用。
      const topicQuote: RichBlock | undefined = CookedHtmlParser.topicQuoteFromAside(openTag, innerHtml);
      if (topicQuote) {
        return [topicQuote];
      }
    }

    if (tagName === 'blockquote' || (tagName === 'aside' && CookedHtmlParser.hasClass(openTag, 'quote'))) {
      let quoteBlocks: RichBlock[] = CookedHtmlParser.parseBlocks(innerHtml);
      if (tagName === 'aside') {
        // Discourse 引用：<aside class="quote"> 内的 <blockquote> 才是引用正文，
        // 展开它，避免正文再被包成一层带竖线的嵌套引用。
        quoteBlocks = CookedHtmlParser.unwrapNestedQuotes(quoteBlocks);
      } else {
        // 纯 <blockquote>(非 aside 用户引用):首段 [!type]± 命中则升级为 callout 提示框。
        const callout: RichBlock | undefined = CookedHtmlParser.calloutFromQuote(quoteBlocks);
        if (callout) {
          return [callout];
        }
      }
      return [{
        type: RichBlockType.QUOTE,
        blocks: quoteBlocks.length > 0 ? quoteBlocks : CookedHtmlParser.paragraphBlocks(innerHtml)
      }];
    }

    // Discourse 链接预览：<aside class="onebox ...">，或个别站点用 <div class="onebox">。
    // 抽出 header.source(favicon+域名) 与 article.onebox-body(标题/描述/缩略图)渲染成卡片。
    if ((tagName === 'aside' || tagName === 'div') && CookedHtmlParser.hasClassContaining(openTag, 'onebox')) {
      return [CookedHtmlParser.oneboxBlock(innerHtml)];
    }

    if (tagName === 'details') {
      return [CookedHtmlParser.disclosureBlockFromDetails(innerHtml)];
    }

    if (tagName === 'pre') {
      return [CookedHtmlParser.codeBlockFromPre(innerHtml)];
    }

    if (tagName === 'ul' || tagName === 'ol') {
      return [CookedHtmlParser.listBlockFromHtml(innerHtml, tagName === 'ol')];
    }

    // discourse-poll:<div class="poll" data-poll-name="...">。产出轻量 POLL 占位块(只带 name),
    // 保持它在正文流的正确位置;真正的票数/选项/交互由渲染层按 name 关联 TopicPost.polls 的动态数据。
    if (CookedHtmlParser.hasClassContaining(openTag, 'poll') ||
      CookedHtmlParser.extractAttr(openTag, 'data-poll-name').length > 0) {
      const pollName: string = CookedHtmlParser.extractAttr(openTag, 'data-poll-name');
      return [{
        type: RichBlockType.POLL,
        pollName: pollName.length > 0 ? pollName : 'poll'
      }];
    }

    // discourse-spoiler-alert 块级剧透:<div class="spoiler">(web 端揭示后变 spoiled)。
    // 内部照常递归解析,遮蔽交给渲染层,避免旧「待实现」占位把明文泄出来。
    if (CookedHtmlParser.hasClassContaining(openTag, 'spoiler') ||
      CookedHtmlParser.hasClassContaining(openTag, 'spoiled')) {
      const spoilerBlocks: RichBlock[] = CookedHtmlParser.parseBlocks(innerHtml);
      return [{
        type: RichBlockType.SPOILER,
        blocks: spoilerBlocks
      }];
    }

    if (tagName === 'audio' || tagName === 'video') {
      const mediaBlock: RichBlock | undefined = CookedHtmlParser.mediaBlockFromElement(tagName, openTag, innerHtml);
      if (mediaBlock) {
        return [mediaBlock];
      }
    }

    // discourse-math 块级公式:<div class="math">裸 LaTeX</div>。API 只给源码,排版交渲染层的
    // 离屏引擎;这里只抽出 LaTeX 存进 MATH 块的 text。须在 detectUnsupportedKind 之前拦截。
    if (CookedHtmlParser.hasClass(openTag, 'math')) {
      const latex: string = CookedHtmlParser.toPlainText(innerHtml);
      return latex.length > 0 ? [{ type: RichBlockType.MATH, text: latex }] : [];
    }

    // Markdown 表格:<table> 直挂或裹在 <div class="md-table"> 里都在此拦截,抽成结构化块。
    // 须在 detectUnsupportedKind 之前(否则会落回「待实现:表格」占位)。解析失败(无有效行)返回
    // undefined,自然退回下方占位兜底。
    const tableBlock: RichBlock | undefined = CookedHtmlParser.tableBlockFrom(tagName, innerHtml);
    if (tableBlock) {
      return [tableBlock];
    }

    const unsupportedKind: string = CookedHtmlParser.detectUnsupportedKind(tagName, openTag, innerHtml);
    if (unsupportedKind.length > 0) {
      return [CookedHtmlParser.unsupportedBlock(unsupportedKind, innerHtml)];
    }

    if (tagName === 'figure' || tagName === 'div') {
      const imageBlocks: RichBlock[] = CookedHtmlParser.imageContainerBlocks(innerHtml);
      if (imageBlocks.length > 0) {
        return imageBlocks;
      }
      const text: string = CookedHtmlParser.toPlainText(innerHtml);
      if (text.length > 0) {
        return CookedHtmlParser.mixedBlocks(innerHtml);
      }
    }

    const fallbackText: string = CookedHtmlParser.toPlainText(innerHtml);
    if (fallbackText.length === 0) {
      return [];
    }
    return [{
      type: RichBlockType.UNSUPPORTED,
      text: fallbackText
    }];
  }

  private static paragraphBlocks(html: string): RichBlock[] {
    const inlines: RichInlineNode[] = CookedHtmlParser.parseInlines(html);
    if (!CookedHtmlParser.hasVisibleInlines(inlines)) {
      return [];
    }
    return [{
      type: RichBlockType.PARAGRAPH,
      inlines
    }];
  }

  private static hasVisibleInlines(inlines: RichInlineNode[]): boolean {
    for (let index: number = 0; index < inlines.length; index++) {
      const token: RichInlineNode = inlines[index];
      if (token.type === RichInlineType.IMAGE || token.type === RichInlineType.LINK) {
        return true;
      }
      if (token.type === RichInlineType.LINE_BREAK) {
        continue;
      }
      if (token.text.trim().length > 0) {
        return true;
      }
    }
    return false;
  }

  // 解析 Discourse 话题引用 <aside class="quote" data-topic data-post> 的头部与预览。
  // 缺少目标 topic 时返回 undefined,让调用方回退成普通引用。
  private static topicQuoteFromAside(openTag: string, innerHtml: string): RichBlock | undefined {
    const topicId: number = CookedHtmlParser.parsePositiveNumber(CookedHtmlParser.extractAttr(openTag, 'data-topic'));
    if (topicId <= 0) {
      return undefined;
    }
    const postNumber: number = CookedHtmlParser.parsePositiveNumber(CookedHtmlParser.extractAttr(openTag, 'data-post'));

    // 头像:title 区里 class 含 avatar 的 <img>。
    const avatarTag: string = CookedHtmlParser.firstImgWithClass(innerHtml, 'avatar');
    const avatarUrl: string = avatarTag.length > 0
      ? CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(avatarTag, 'src')) : '';

    // 标题 + 链接:优先取新式 quote-title__text-content;取不到再退回老式 <div class="title"> 的内部。
    let titleContent: string = CookedHtmlParser.firstElementInnerByClass(innerHtml, 'quote-title__text-content');
    if (titleContent.length === 0) {
      titleContent = CookedHtmlParser.firstElementInnerByClass(innerHtml, 'title');
    }
    // 用户名(头像身份,兼作缺显示名时的兜底标题)。
    const username: string = CookedHtmlParser.decodeHtmlEntities(CookedHtmlParser.extractAttr(openTag, 'data-username'));

    // 标题文字取第一个 <a>(话题链接,class 无 badge)的内部;href 取该开标签的 href 属性。
    const titleAnchor: string = CookedHtmlParser.firstTopicTitleAnchor(titleContent);
    let title: string;
    let href: string;
    let category: TopicCategory | undefined;
    let isReply: boolean = false;
    if (titleAnchor.length > 0) {
      // 跨话题引用:title 里带话题链接 → 标题取链接文字、href 取链接、分类取徽章。
      title = CookedHtmlParser.decodeHtmlEntities(
        CookedHtmlParser.toPlainText(CookedHtmlParser.firstElementInner(titleContent, 'a')));
      href = CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(titleAnchor, 'href'));
      // 分类徽章:badge-category span 上带 data-category-id + --category-badge-* 变量 + 名字 + 图标 svg。
      category = CookedHtmlParser.categoryFromBadge(titleContent);
    } else {
      isReply = true;
      // 同帖回复引用:title 只有「显示名:」无链接 → 用 aside 属性组卡。
      // 标题取 data-display-name(缺则退 data-username);跳转按 data-topic/data-post 自拼站内帖链接。
      let displayName: string = CookedHtmlParser.decodeHtmlEntities(CookedHtmlParser.extractAttr(openTag, 'data-display-name'));
      if (displayName.length === 0) {
        displayName = username;
      }
      title = displayName;
      href = CookedHtmlParser.resolveUrl(`/t/topic/${topicId}/${postNumber > 0 ? postNumber : 1}`);
      category = undefined;
    }

    // 正文预览:第一个 <blockquote> 的内部 HTML(截断预览),交渲染层内嵌解析。
    const preview: string = CookedHtmlParser.firstElementInner(innerHtml, 'blockquote');

    const block: RichBlock = {
      type: RichBlockType.TOPIC_QUOTE,
      text: preview,
      quoteTopicId: topicId,
      // 缺 data-post(如 [quote="user, topic:123"] 只带话题不带楼层)保持 0,不兜底成 1:
      // 否则展开 chevron 仍显示,一点会拉到该话题主楼(1楼)当"被引用全文",与卡片预览的引用片段不符。
      // 0 会让渲染层(quotePostNumber > 0)不显示展开箭头,只保留跳转,从根上避免拉错楼。
      quotePostNumber: postNumber
    };
    if (avatarUrl.length > 0) {
      block.quoteAvatarUrl = avatarUrl;
    }
    if (username.length > 0) {
      block.quoteAuthor = username;
    }
    if (title.length > 0) {
      block.quoteTitle = title;
    }
    if (href.length > 0) {
      block.href = href;
    }
    if (category) {
      block.quoteCategory = category;
    }
    if (isReply) {
      block.quoteIsReply = true;
    }
    return block;
  }

  // 从 title 区取第一个指向话题的 <a>(class 不含 badge-category)的完整开标签。
  private static firstTopicTitleAnchor(titleContent: string): string {
    const lower: string = titleContent.toLowerCase();
    let cursor: number = 0;
    while (cursor < titleContent.length) {
      const start: number = lower.indexOf('<a', cursor);
      if (start < 0) {
        return '';
      }
      const end: number = CookedHtmlParser.findTagEnd(titleContent, start);
      if (end < 0) {
        return '';
      }
      const tag: string = titleContent.substring(start, end + 1);
      if (!CookedHtmlParser.hasClassContaining(tag, 'badge-category')) {
        return tag;
      }
      cursor = end + 1;
    }
    return '';
  }

  // 从 badge-category__wrapper 里的 <span class="badge-category" ...> 抽出分类。缺 id/名字则返回 undefined。
  private static categoryFromBadge(titleContent: string): TopicCategory | undefined {
    const badgeInner: string = CookedHtmlParser.firstElementInnerByClass(titleContent, 'badge-category__wrapper');
    if (badgeInner.length === 0) {
      return undefined;
    }
    const spanOpen: string = CookedHtmlParser.firstOpenTagByClass(badgeInner, 'badge-category');
    const idText: string = CookedHtmlParser.extractAttr(spanOpen, 'data-category-id');
    const id: number = CookedHtmlParser.parsePositiveNumber(idText);
    const name: string = CookedHtmlParser.decodeHtmlEntities(
      CookedHtmlParser.toPlainText(CookedHtmlParser.firstElementInnerByClass(badgeInner, 'badge-category__name')));
    if (name.length === 0) {
      return undefined;
    }
    const style: string = CookedHtmlParser.extractAttr(spanOpen, 'style');
    const color: string = CookedHtmlParser.cssVar(style, '--category-badge-color');
    const textColor: string = CookedHtmlParser.cssVar(style, '--category-badge-text-color');
    // 图标:徽章内最内层 <svg id="xxx">(外层是 fa 包装 svg)。取 id 作图标名交 getCategoryIcon 归一。
    const iconId: string = CookedHtmlParser.extractAttr(CookedHtmlParser.lastSvgWithId(badgeInner), 'id');

    const category: TopicCategory = {
      id: id > 0 ? id : 0,
      name,
      color: color.length > 0 ? color.replace('#', '') : '6B7280',
      textColor: textColor.length > 0 ? textColor.replace('#', '') : 'FFFFFF'
    };
    if (iconId.length > 0) {
      category.icon = iconId;
    }
    return category;
  }

  // 取 style 里某个 CSS 变量的值(如 --category-badge-color: #9cb6c4)。
  private static cssVar(style: string, name: string): string {
    const pattern: RegExp = new RegExp(`${name}\\s*:\\s*([^;]+)`, 'i');
    const match: RegExpMatchArray | null = style.match(pattern);
    return match ? match[1].trim() : '';
  }

  // 第一个 class 含指定关键字的 <img> 的完整标签。
  private static firstImgWithClass(html: string, keyword: string): string {
    const lower: string = html.toLowerCase();
    let cursor: number = 0;
    while (cursor < html.length) {
      const start: number = lower.indexOf('<img', cursor);
      if (start < 0) {
        return '';
      }
      const end: number = CookedHtmlParser.findTagEnd(html, start);
      if (end < 0) {
        return '';
      }
      const tag: string = html.substring(start, end + 1);
      if (CookedHtmlParser.hasClassContaining(tag, keyword)) {
        return tag;
      }
      cursor = end + 1;
    }
    return '';
  }

  // 最靠后的带 id 的 <svg>(话题分类徽章图标外层是 fa 包装 svg,真正图标是内层 svg[id])。
  private static lastSvgWithId(html: string): string {
    const lower: string = html.toLowerCase();
    let cursor: number = 0;
    let found: string = '';
    while (cursor < html.length) {
      const start: number = lower.indexOf('<svg', cursor);
      if (start < 0) {
        break;
      }
      const end: number = CookedHtmlParser.findTagEnd(html, start);
      if (end < 0) {
        break;
      }
      const tag: string = html.substring(start, end + 1);
      if (CookedHtmlParser.extractAttr(tag, 'id').length > 0) {
        found = tag;
      }
      cursor = end + 1;
    }
    return found;
  }

  // 第一个 class 含 keyword 的元素的开标签(用于取其属性,如 badge-category span 的 style/data-*)。
  private static firstOpenTagByClass(html: string, keyword: string): string {
    const lower: string = html.toLowerCase();
    let cursor: number = 0;
    while (cursor < html.length) {
      const start: number = lower.indexOf('<', cursor);
      if (start < 0) {
        return '';
      }
      const end: number = CookedHtmlParser.findTagEnd(html, start);
      if (end < 0) {
        return '';
      }
      const tag: string = html.substring(start, end + 1);
      if (!CookedHtmlParser.isClosingTag(tag) && CookedHtmlParser.hasClassContaining(tag, keyword)) {
        return tag;
      }
      cursor = end + 1;
    }
    return '';
  }

  // 第一个 class 含 keyword 的元素的内部 HTML。
  private static firstElementInnerByClass(html: string, keyword: string): string {
    const lower: string = html.toLowerCase();
    let cursor: number = 0;
    while (cursor < html.length) {
      const start: number = lower.indexOf('<', cursor);
      if (start < 0) {
        return '';
      }
      const end: number = CookedHtmlParser.findTagEnd(html, start);
      if (end < 0) {
        return '';
      }
      const tag: string = html.substring(start, end + 1);
      if (!CookedHtmlParser.isClosingTag(tag) && CookedHtmlParser.hasClassContaining(tag, keyword)) {
        const name: string = CookedHtmlParser.getTagName(tag);
        const closeStart: number = CookedHtmlParser.findClosingTag(html, end + 1, name);
        if (closeStart < 0) {
          return '';
        }
        return html.substring(end + 1, closeStart);
      }
      cursor = end + 1;
    }
    return '';
  }

  // 第一个指定标签名元素的内部 HTML。
  private static firstElementInner(html: string, tagName: string): string {
    const lower: string = html.toLowerCase();
    const open: number = lower.indexOf(`<${tagName}`);
    if (open < 0) {
      return '';
    }
    const openEnd: number = CookedHtmlParser.findTagEnd(html, open);
    if (openEnd < 0) {
      return '';
    }
    const closeStart: number = CookedHtmlParser.findClosingTag(html, openEnd + 1, tagName);
    if (closeStart < 0) {
      return '';
    }
    return html.substring(openEnd + 1, closeStart);
  }

  private static unwrapNestedQuotes(blocks: RichBlock[]): RichBlock[] {
    const out: RichBlock[] = [];
    for (let index: number = 0; index < blocks.length; index++) {
      const block: RichBlock = blocks[index];
      if (block.type === RichBlockType.QUOTE && block.blocks && block.blocks.length > 0) {
        for (let inner: number = 0; inner < block.blocks.length; inner++) {
          out.push(block.blocks[inner]);
        }
      } else {
        out.push(block);
      }
    }
    return out;
  }

  // 把已解析好的引用子块尝试识别为 callout。首段(段落)首个文本节点以 [!type]± 开头才算命中,
  // 否则返回 undefined 让调用方回退成普通引用。命中后:剥掉标记,首行(遇 <br> 截断)作标题,
  // 换行后的残余与其余子块作正文。
  private static calloutFromQuote(quoteBlocks: RichBlock[]): RichBlock | undefined {
    if (quoteBlocks.length === 0) {
      return undefined;
    }
    const first: RichBlock = quoteBlocks[0];
    if (first.type !== RichBlockType.PARAGRAPH || !first.inlines || first.inlines.length === 0) {
      return undefined;
    }
    const head: RichInlineNode = first.inlines[0];
    if (head.type !== RichInlineType.TEXT) {
      return undefined;
    }
    const match: RegExpMatchArray | null = head.text.match(CALLOUT_MARKER);
    if (!match) {
      return undefined;
    }

    const rawType: string = match[1].toLowerCase();
    const fold: string = match[2] ? match[2] : '';
    const style: CalloutStyle = CookedHtmlParser.resolveCalloutStyle(rawType);

    // 去掉首文本节点里的 [!type]± 标记(其余标题文本/样式保留)。
    head.text = head.text.replace(CALLOUT_MARKER, '');

    // 标题段可能内含 <br>:换行前为标题,换行后回落成正文首段。
    const firstLineInlines: RichInlineNode[] = [];
    const overflowInlines: RichInlineNode[] = [];
    let hitBreak: boolean = false;
    for (let i: number = 0; i < first.inlines.length; i++) {
      const node: RichInlineNode = first.inlines[i];
      if (!hitBreak && node.type === RichInlineType.LINE_BREAK) {
        hitBreak = true;
        continue;
      }
      if (hitBreak) {
        overflowInlines.push(node);
      } else {
        firstLineInlines.push(node);
      }
    }

    const titleInlines: RichInlineNode[] = CookedHtmlParser.trimLeadingEmptyText(firstLineInlines);

    const contentBlocks: RichBlock[] = [];
    if (overflowInlines.length > 0 && CookedHtmlParser.hasVisibleInlines(overflowInlines)) {
      contentBlocks.push({
        type: RichBlockType.PARAGRAPH,
        inlines: overflowInlines
      });
    }
    for (let i: number = 1; i < quoteBlocks.length; i++) {
      contentBlocks.push(quoteBlocks[i]);
    }

    return {
      type: RichBlockType.CALLOUT,
      calloutKind: style.kind,
      calloutColor: style.color,
      calloutIcon: style.icon,
      collapsible: fold.length > 0,
      defaultExpanded: fold !== '-',
      titleInlines,
      blocks: contentBlocks
    };
  }

  // 类型 → 主色/图标。先按别名归一,再查样式表;未命中用 fallback 色/图标,kind 保留原始串。
  private static resolveCalloutStyle(rawType: string): CalloutStyle {
    const alias: string | undefined = CALLOUT_ALIASES.get(rawType);
    const canonical: string = alias ? alias : rawType;
    const def: CalloutStyleDef | undefined = CALLOUT_STYLES.get(canonical);
    if (def) {
      return { kind: canonical, color: def.color, icon: def.icon };
    }
    return { kind: rawType, color: CALLOUT_FALLBACK.color, icon: CALLOUT_FALLBACK.icon };
  }

  // 丢掉标题前导的空白文本节点(标记剥离后可能残留 "" 或空格),并去掉首个文本节点的左侧空格。
  private static trimLeadingEmptyText(inlines: RichInlineNode[]): RichInlineNode[] {
    const out: RichInlineNode[] = inlines.slice();
    while (out.length > 0 && out[0].type === RichInlineType.TEXT && out[0].text.trim().length === 0) {
      out.shift();
    }
    if (out.length > 0 && out[0].type === RichInlineType.TEXT) {
      out[0].text = out[0].text.replace(/^\s+/, '');
    }
    return out;
  }

  private static parseInlines(html: string): RichInlineNode[] {
    const out: RichInlineNode[] = [];
    const state: InlineState = new InlineState();
    let buffer: string = '';
    let index: number = 0;

    const appendText = (raw: string): void => {
      let text: string = CookedHtmlParser.decodeHtmlEntities(raw);
      if (text.length === 0) {
        return;
      }
      // HTML 语义:源码里的换行/缩进/连续空格是不可见排版空白,浏览器折叠成单个空格。此前解析器
      // 原样保留,导致 <br> 后紧跟的源码换行(<br>\n2.1)多出一个真换行,<br> 行距凭空翻倍。
      // 折叠这类空白(nbsp   不在其列,予以保留)。
      text = text.replace(/[ \t\r\n\f]+/g, ' ');
      // 段首及 <br>/段落换行之后的行首空白不可见,去掉,避免每行多一个前导空格。
      const prevNode: RichInlineNode | undefined = out.length > 0 ? out[out.length - 1] : undefined;
      if (!prevNode || prevNode.type === RichInlineType.LINE_BREAK) {
        text = text.replace(/^ /, '');
      }
      if (text.length === 0) {
        return;
      }

      const href: string = state.currentHref();
      const type: RichInlineType = state.code > 0 ? RichInlineType.CODE : (href.length > 0 ? RichInlineType.LINK : RichInlineType.TEXT);
      const attachment: boolean = type === RichInlineType.LINK && state.currentAttachment();
      const spoiler: boolean = state.currentSpoiler();
      const last: RichInlineNode | undefined = out.length > 0 ? out[out.length - 1] : undefined;
      if (last &&
        last.type === type &&
        (last.href ? last.href : '') === href &&
        !!last.attachment === attachment &&
        !!last.spoiler === spoiler &&
        !!last.bold === state.bold > 0 &&
        !!last.italic === state.italic > 0 &&
        !!last.code === state.code > 0) {
        last.text = `${last.text}${text}`;
        return;
      }

      const token: RichInlineNode = {
        type,
        text,
        bold: state.bold > 0,
        italic: state.italic > 0,
        code: state.code > 0
      };
      if (href.length > 0) {
        token.href = href;
      }
      if (attachment) {
        token.attachment = true;
      }
      if (spoiler) {
        token.spoiler = true;
      }
      out.push(token);
    };

    const flush = (): void => {
      if (buffer.length === 0) {
        return;
      }
      appendText(buffer);
      buffer = '';
    };

    while (index < html.length) {
      const tagStart: number = html.indexOf('<', index);
      if (tagStart < 0) {
        buffer = `${buffer}${html.substring(index)}`;
        break;
      }

      if (tagStart > index) {
        buffer = `${buffer}${html.substring(index, tagStart)}`;
      }

      const tagEnd: number = CookedHtmlParser.findTagEnd(html, tagStart);
      if (tagEnd < 0) {
        buffer = `${buffer}${html.substring(tagStart)}`;
        break;
      }

      const tag: string = html.substring(tagStart, tagEnd + 1);
      const tagName: string = CookedHtmlParser.getTagName(tag);
      const closing: boolean = CookedHtmlParser.isClosingTag(tag);
      const selfClosing: boolean = CookedHtmlParser.isSelfClosingTag(tag);

      if (tagName === 'br') {
        flush();
        out.push({ type: RichInlineType.LINE_BREAK, text: '\n' });
      } else if (tagName === 'strong' || tagName === 'b') {
        flush();
        state.bold = Math.max(0, state.bold + (closing ? -1 : 1));
      } else if (tagName === 'em' || tagName === 'i') {
        flush();
        state.italic = Math.max(0, state.italic + (closing ? -1 : 1));
      } else if (tagName === 'code') {
        flush();
        state.code = Math.max(0, state.code + (closing ? -1 : 1));
      } else if (tagName === 'span') {
        // discourse-math 行内公式:<span class="math">裸 LaTeX</span>。整体抽成一个 MATH token,
        // 里面的 LaTeX 不再当纯文本泄进正文流(否则会显示 \frac{...} 之类源码)。
        if (!closing && !selfClosing && CookedHtmlParser.hasClass(tag, 'math')) {
          flush();
          const mathClose: number = CookedHtmlParser.findClosingTag(html, tagEnd + 1, 'span');
          if (mathClose > tagEnd) {
            const latex: string = CookedHtmlParser.toPlainText(html.substring(tagEnd + 1, mathClose));
            if (latex.length > 0) {
              out.push({ type: RichInlineType.MATH, text: latex });
            }
            const mathCloseEnd: number = CookedHtmlParser.findTagEnd(html, mathClose);
            index = mathCloseEnd >= 0 ? mathCloseEnd + 1 : mathClose;
            continue;
          }
        }
        flush();
        if (closing) {
          state.spanSpoilerStack.pop();
        } else if (!selfClosing) {
          state.spanSpoilerStack.push(CookedHtmlParser.hasClassContaining(tag, 'spoiler'));
        }
      } else if (tagName === 'a') {
        flush();
        if (closing) {
          state.hrefStack.pop();
          state.attachmentStack.pop();
        } else {
          const resolvedHref: string = CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(tag, 'href'));
          state.hrefStack.push(resolvedHref);
          // 附件下载链接:显式 class="attachment",或指向 /uploads/ 的站内链接。
          const isAttachment: boolean = CookedHtmlParser.hasClass(tag, 'attachment') ||
            /^https?:\/\/[^\/]*linux\.do\/uploads\//i.test(resolvedHref) ||
            resolvedHref.indexOf('/uploads/') === 0;
          state.attachmentStack.push(isAttachment);
        }
      } else if (tagName === 'img' && !closing) {
        flush();
        const src: string = CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(tag, 'src'));
        const alt: string = CookedHtmlParser.decodeHtmlEntities(CookedHtmlParser.extractAttr(tag, 'alt'));
        if (src.length > 0) {
          const imageToken: RichInlineNode = {
            type: RichInlineType.IMAGE,
            text: alt.length > 0 ? alt : ' ',
            src,
            alt,
            href: state.currentHref()
          };
          if (state.currentSpoiler()) {
            imageToken.spoiler = true;
          }
          out.push(imageToken);
        } else if (alt.length > 0) {
          appendText(alt);
        }
      } else if (!selfClosing && !closing && CookedHtmlParser.shouldReadChildrenAsPlainText(tagName)) {
        const closeStart: number = CookedHtmlParser.findClosingTag(html, tagEnd + 1, tagName);
        if (closeStart > tagEnd) {
          const inner: string = html.substring(tagEnd + 1, closeStart);
          appendText(CookedHtmlParser.toPlainText(inner));
          const closeEnd: number = CookedHtmlParser.findTagEnd(html, closeStart);
          index = closeEnd >= 0 ? closeEnd + 1 : closeStart;
          continue;
        }
      }

      index = tagEnd + 1;
    }

    flush();
    return CookedHtmlParser.compactInlines(out);
  }

  private static compactInlines(inlines: RichInlineNode[]): RichInlineNode[] {
    const compacted: RichInlineNode[] = [];
    for (let index: number = 0; index < inlines.length; index++) {
      const token: RichInlineNode = inlines[index];
      if (token.type !== RichInlineType.LINE_BREAK) {
        compacted.push(token);
        continue;
      }

      const last: RichInlineNode | undefined = compacted.length > 0 ? compacted[compacted.length - 1] : undefined;
      if (last && last.type === RichInlineType.LINE_BREAK) {
        continue;
      }
      compacted.push(token);
    }
    const filtered: RichInlineNode[] =
      compacted.filter((token: RichInlineNode) => token.type !== RichInlineType.TEXT || token.text.length > 0);
    return CookedHtmlParser.trimInlineEdges(filtered);
  }

  private static trimInlineEdges(inlines: RichInlineNode[]): RichInlineNode[] {
    let start: number = 0;
    let end: number = inlines.length;
    while (start < end && CookedHtmlParser.isBlankInline(inlines[start])) {
      start++;
    }
    while (end > start && CookedHtmlParser.isBlankInline(inlines[end - 1])) {
      end--;
    }
    const trimmed: RichInlineNode[] = (start === 0 && end === inlines.length) ? inlines : inlines.slice(start, end);
    if (trimmed.length === 0) {
      return trimmed;
    }
    // 去掉首个文本的前导空白、末个文本的尾随空白（标签间换行/缩进噪声，
    // 例如图片块之后紧跟的正文常带一个前导 '\n'）。
    const first: RichInlineNode = trimmed[0];
    if (first.type === RichInlineType.TEXT) {
      first.text = first.text.replace(/^\s+/, '');
    }
    const last: RichInlineNode = trimmed[trimmed.length - 1];
    if (last.type === RichInlineType.TEXT) {
      last.text = last.text.replace(/\s+$/, '');
    }
    return trimmed;
  }

  private static isBlankInline(token: RichInlineNode): boolean {
    if (token.type === RichInlineType.LINE_BREAK) {
      return true;
    }
    return token.type === RichInlineType.TEXT && token.text.trim().length === 0;
  }

  private static codeBlockFromPre(innerHtml: string): RichBlock {
    const codeOpenMatch: RegExpMatchArray | null = innerHtml.match(/<code\b[^>]*>/i);
    const codeOpenTag: string = codeOpenMatch ? codeOpenMatch[0] : '';
    let codeHtml: string = innerHtml;
    if (codeOpenMatch) {
      const openEnd: number = innerHtml.indexOf(codeOpenTag) + codeOpenTag.length;
      const closeStart: number = innerHtml.toLowerCase().lastIndexOf('</code>');
      if (closeStart >= openEnd) {
        codeHtml = innerHtml.substring(openEnd, closeStart);
      }
    }

    return {
      type: RichBlockType.CODE,
      text: CookedHtmlParser.decodeHtmlEntities(CookedHtmlParser.stripTagsKeepingLines(codeHtml)).trim(),
      language: CookedHtmlParser.extractCodeLanguage(codeOpenTag)
    };
  }

  private static listBlockFromHtml(innerHtml: string, ordered: boolean): RichBlock {
    const items: RichListItem[] = [];
    let index: number = 0;
    const lower: string = innerHtml.toLowerCase();
    while (index < innerHtml.length) {
      const openStart: number = lower.indexOf('<li', index);
      if (openStart < 0) {
        break;
      }
      const openEnd: number = CookedHtmlParser.findTagEnd(innerHtml, openStart);
      if (openEnd < 0) {
        break;
      }
      const closeStart: number = CookedHtmlParser.findClosingTag(innerHtml, openEnd + 1, 'li');
      if (closeStart < 0) {
        break;
      }
      const closeEnd: number = CookedHtmlParser.findTagEnd(innerHtml, closeStart);
      const itemHtml: string = innerHtml.substring(openEnd + 1, closeStart);
      // 列表项里裹了块级图(lightbox/大图)时,走 mixedBlocks 把文字与图片拆成块级序列;
      // 纯文字/行内(含 emoji)项保持原有的行内快路径。findImageUnit 只认块级图,emoji 不触发。
      if (CookedHtmlParser.findImageUnit(itemHtml) !== undefined) {
        items.push({
          inlines: [],
          blocks: CookedHtmlParser.mixedBlocks(itemHtml)
        });
      } else {
        items.push({
          inlines: CookedHtmlParser.parseInlines(itemHtml)
        });
      }
      index = closeEnd >= 0 ? closeEnd + 1 : closeStart + 5;
    }

    return {
      type: RichBlockType.LIST,
      ordered,
      items
    };
  }

  // 从 <table>(或含 <table> 的包裹元素,如 <div class="md-table">)抽出结构化表格块。
  // 无有效行时返回 undefined,交由调用方回退到占位。
  private static tableBlockFrom(tagName: string, innerHtml: string): RichBlock | undefined {
    let tableInner: string = '';
    if (tagName === 'table') {
      tableInner = innerHtml;
    } else if (innerHtml.toLowerCase().indexOf('<table') >= 0) {
      tableInner = CookedHtmlParser.extractElementInner(innerHtml, 'table');
    }
    if (tableInner.length === 0) {
      return undefined;
    }

    const rows: RichTableRow[] = CookedHtmlParser.tableRowsFromHtml(tableInner);
    if (rows.length === 0) {
      return undefined;
    }
    return {
      type: RichBlockType.TABLE,
      tableRows: rows
    };
  }

  private static tableRowsFromHtml(tableHtml: string): RichTableRow[] {
    const rows: RichTableRow[] = [];
    let search: number = 0;
    while (search < tableHtml.length) {
      const trStart: number = CookedHtmlParser.findOpenTag(tableHtml, 'tr', search);
      if (trStart < 0) {
        break;
      }
      const trOpenEnd: number = CookedHtmlParser.findTagEnd(tableHtml, trStart);
      if (trOpenEnd < 0) {
        break;
      }
      const trClose: number = CookedHtmlParser.findClosingTag(tableHtml, trOpenEnd + 1, 'tr');
      if (trClose < 0) {
        break;
      }
      const rowHtml: string = tableHtml.substring(trOpenEnd + 1, trClose);
      const cells: RichTableCell[] = CookedHtmlParser.tableCellsFromRow(rowHtml);
      if (cells.length > 0) {
        const allHeader: boolean = cells.every((cell: RichTableCell) => cell.header === true);
        rows.push({ cells, header: allHeader });
      }
      const trCloseEnd: number = CookedHtmlParser.findTagEnd(tableHtml, trClose);
      search = trCloseEnd >= 0 ? trCloseEnd + 1 : trClose + 1;
    }
    return rows;
  }

  private static tableCellsFromRow(rowHtml: string): RichTableCell[] {
    const cells: RichTableCell[] = [];
    let index: number = 0;
    while (index < rowHtml.length) {
      const thStart: number = CookedHtmlParser.findOpenTag(rowHtml, 'th', index);
      const tdStart: number = CookedHtmlParser.findOpenTag(rowHtml, 'td', index);
      if (thStart < 0 && tdStart < 0) {
        break;
      }
      const isHeader: boolean = thStart >= 0 && (tdStart < 0 || thStart < tdStart);
      const cellStart: number = isHeader ? thStart : tdStart;
      const cellTag: string = isHeader ? 'th' : 'td';
      const openEnd: number = CookedHtmlParser.findTagEnd(rowHtml, cellStart);
      if (openEnd < 0) {
        break;
      }
      const closeStart: number = CookedHtmlParser.findClosingTag(rowHtml, openEnd + 1, cellTag);
      if (closeStart < 0) {
        break;
      }
      const cellHtml: string = rowHtml.substring(openEnd + 1, closeStart);
      cells.push({
        inlines: CookedHtmlParser.parseInlines(cellHtml),
        header: isHeader
      });
      const closeEnd: number = CookedHtmlParser.findTagEnd(rowHtml, closeStart);
      index = closeEnd >= 0 ? closeEnd + 1 : closeStart + 1;
    }
    return cells;
  }

  private static unsupportedBlock(kind: string, innerHtml: string): RichBlock {
    const text: string = CookedHtmlParser.toPlainText(innerHtml);
    return {
      type: RichBlockType.UNSUPPORTED,
      unsupportedKind: kind,
      text: text.length > 0 ? text : `${kind}待实现`
    };
  }

  private static disclosureBlockFromDetails(innerHtml: string): RichBlock {
    const summaryInfo: SummaryInfo = CookedHtmlParser.extractSummary(innerHtml);
    const contentBlocks: RichBlock[] = CookedHtmlParser.parseBlocks(summaryInfo.contentHtml);
    return {
      type: RichBlockType.DISCLOSURE,
      title: summaryInfo.title.length > 0 ? summaryInfo.title : '详情',
      blocks: contentBlocks.length > 0 ? contentBlocks : CookedHtmlParser.paragraphBlocks(summaryInfo.contentHtml)
    };
  }

  private static oneboxBlock(innerHtml: string): RichBlock {
    const block: RichBlock = { type: RichBlockType.ONEBOX };

    // 头部 <header class="source">:站点图标 + 域名文字。缺失时退回整段查找。
    const headerInner: string = CookedHtmlParser.extractElementInner(innerHtml, 'header');
    const headerHtml: string = headerInner.length > 0 ? headerInner : innerHtml;
    const faviconTag: string = CookedHtmlParser.firstTagMatch(headerHtml, /<img\b[^>]*>/i);
    if (faviconTag.length > 0) {
      const favSrc: string = CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(faviconTag, 'src'));
      if (favSrc.length > 0) {
        block.faviconUrl = favSrc;
      }
    }
    const domainText: string = CookedHtmlParser.firstAnchorText(headerHtml);
    const sourceHref: string = CookedHtmlParser.firstAnchorHref(headerHtml);

    // 正文 <article class="onebox-body">:标题(h3/h4)、描述(首个 p)、缩略图。
    const bodyInner: string = CookedHtmlParser.extractElementInner(innerHtml, 'article');
    const bodyHtml: string = bodyInner.length > 0 ? bodyInner : innerHtml;

    let titleHtml: string = CookedHtmlParser.extractElementInner(bodyHtml, 'h3');
    if (titleHtml.length === 0) {
      titleHtml = CookedHtmlParser.extractElementInner(bodyHtml, 'h4');
    }
    const title: string = CookedHtmlParser.toPlainText(titleHtml);
    const titleHref: string = CookedHtmlParser.firstAnchorHref(titleHtml);

    const description: string = CookedHtmlParser.toPlainText(CookedHtmlParser.extractElementInner(bodyHtml, 'p'));

    const thumbTag: string = CookedHtmlParser.firstTagMatch(bodyHtml, /<img\b[^>]*>/i);
    if (thumbTag.length > 0) {
      const thumbSrc: string = CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(thumbTag, 'src'));
      if (thumbSrc.length > 0) {
        block.thumbnailUrl = thumbSrc;
      }
    }

    const href: string = titleHref.length > 0 ? titleHref : sourceHref;
    if (href.length > 0) {
      block.href = href;
    }
    const domain: string = domainText.length > 0 ? domainText : CookedHtmlParser.hostFromUrl(href);
    if (domain.length > 0) {
      block.domain = domain;
    }
    if (title.length > 0) {
      block.title = title;
    }
    if (description.length > 0) {
      block.description = description;
    }
    return block;
  }

  // 取 html 中首个 <tagName ...>...</tagName> 的内层 HTML(标签名需按词边界匹配,避免 p 命中 picture)。
  private static extractElementInner(html: string, tagName: string): string {
    const openStart: number = CookedHtmlParser.findOpenTag(html, tagName, 0);
    if (openStart < 0) {
      return '';
    }
    const openEnd: number = CookedHtmlParser.findTagEnd(html, openStart);
    if (openEnd < 0) {
      return '';
    }
    const closeStart: number = CookedHtmlParser.findClosingTag(html, openEnd + 1, tagName);
    if (closeStart < 0) {
      return '';
    }
    return html.substring(openEnd + 1, closeStart);
  }

  private static findOpenTag(html: string, tagName: string, fromIndex: number): number {
    const lower: string = html.toLowerCase();
    const needle: string = `<${tagName.toLowerCase()}`;
    let index: number = lower.indexOf(needle, fromIndex);
    while (index >= 0) {
      const after: string = lower.charAt(index + needle.length);
      if (after === '' || after === '>' || after === '/' || after === ' ' || after === '\t' || after === '\n' || after === '\r') {
        return index;
      }
      index = lower.indexOf(needle, index + needle.length);
    }
    return -1;
  }

  private static firstTagMatch(html: string, pattern: RegExp): string {
    const match: RegExpMatchArray | null = html.match(pattern);
    return match ? match[0] : '';
  }

  private static firstAnchorHref(html: string): string {
    const openTag: string = CookedHtmlParser.firstTagMatch(html, /<a\b[^>]*>/i);
    if (openTag.length === 0) {
      return '';
    }
    return CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(openTag, 'href'));
  }

  private static firstAnchorText(html: string): string {
    const openTag: string = CookedHtmlParser.firstTagMatch(html, /<a\b[^>]*>/i);
    if (openTag.length === 0) {
      return '';
    }
    const start: number = html.indexOf(openTag) + openTag.length;
    const closeStart: number = html.toLowerCase().indexOf('</a>', start);
    if (closeStart < 0) {
      return '';
    }
    return CookedHtmlParser.toPlainText(html.substring(start, closeStart));
  }

  private static hostFromUrl(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/]+)/i);
    return match ? match[1] : '';
  }

  private static extractSummary(innerHtml: string): SummaryInfo {
    const openMatch: RegExpMatchArray | null = innerHtml.match(/<summary\b[^>]*>/i);
    if (!openMatch) {
      return {
        title: '详情',
        contentHtml: innerHtml
      };
    }

    const openStart: number = innerHtml.indexOf(openMatch[0]);
    const openEnd: number = openStart + openMatch[0].length;
    const closeStart: number = innerHtml.toLowerCase().indexOf('</summary>', openEnd);
    if (closeStart < 0) {
      return {
        title: '详情',
        contentHtml: innerHtml
      };
    }

    const closeEnd: number = closeStart + '</summary>'.length;
    const summaryHtml: string = innerHtml.substring(openEnd, closeStart);
    return {
      title: CookedHtmlParser.toPlainText(summaryHtml),
      contentHtml: `${innerHtml.substring(0, openStart)}${innerHtml.substring(closeEnd)}`
    };
  }

  private static detectUnsupportedKind(tagName: string, openTag: string, innerHtml: string): string {
    const combined: string = `${openTag}\n${innerHtml}`.toLowerCase();
    if (CookedHtmlParser.hasClassContaining(openTag, 'poll') ||
      CookedHtmlParser.extractAttr(openTag, 'data-poll-name').length > 0 ||
      combined.indexOf('data-poll-name') >= 0) {
      return '投票';
    }

    if (tagName === 'table' || combined.indexOf('<table') >= 0) {
      return '表格';
    }

    // <video>/<audio> 已由 mediaBlockFromElement 提升为播放块,这里只兜住 iframe 类嵌入(YouTube/B 站等)。
    if (tagName === 'iframe' || combined.indexOf('<iframe') >= 0) {
      return '视频/嵌入内容';
    }

    if (CookedHtmlParser.hasClassContaining(openTag, 'onebox')) {
      return '链接预览';
    }

    if (CookedHtmlParser.hasClassContaining(openTag, 'math') ||
      combined.indexOf('math-container') >= 0 ||
      combined.indexOf('<math') >= 0) {
      return '数学公式';
    }

    return '';
  }

  private static singleImageParagraph(innerHtml: string): RichBlock | undefined {
    const withoutBreaks: string = innerHtml.replace(/<br\s*\/?>/gi, '').trim();
    const imageMatch: RegExpMatchArray | null = withoutBreaks.match(/^<img\b[^>]*>$/i);
    if (imageMatch) {
      return CookedHtmlParser.imageBlockFromTag(imageMatch[0], '');
    }

    const linkedImageMatch: RegExpMatchArray | null = withoutBreaks.match(/^<a\b[^>]*>(<img\b[^>]*>)<\/a>$/i);
    if (linkedImageMatch) {
      const linkMatch: RegExpMatchArray | null = withoutBreaks.match(/^<a\b[^>]*>/i);
      return CookedHtmlParser.imageBlockFromTag(linkedImageMatch[1], linkMatch ? CookedHtmlParser.extractAttr(linkMatch[0], 'href') : '');
    }

    const uploadPreviewMatch: RegExpMatchArray | null =
      withoutBreaks.match(/^<a\b[^>]*>(<img\b[^>]*>)<\/a>\s*<a\b[^>]*>[^<]*<\/a>$/i);
    if (uploadPreviewMatch) {
      const linkMatch: RegExpMatchArray | null = withoutBreaks.match(/^<a\b[^>]*>/i);
      return CookedHtmlParser.imageBlockFromTag(uploadPreviewMatch[1], linkMatch ? CookedHtmlParser.extractAttr(linkMatch[0], 'href') : '');
    }
    return undefined;
  }

  private static imageContainerBlocks(innerHtml: string): RichBlock[] {
    // Discourse 上传图片会包成 <div class="lightbox-wrapper"><a class="lightbox" href="原图">
    // <img src="优化图"><div class="meta">文件名/尺寸/大小</div></a></div>。
    // 去掉 meta 元信息与图标后若无实质文字，则视为纯图片容器，逐张渲染为图片块，
    // 忽略文件名与尺寸文字（否则会退化成一个 18px 小图标 + 蓝色链接）。
    const withoutMeta: string = innerHtml
      .replace(/<div\b[^>]*class\s*=\s*["'][^"']*meta[^"']*["'][^>]*>[\s\S]*?<\/div>/gi, '')
      .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, '');
    const residualText: string = CookedHtmlParser.toPlainText(withoutMeta.replace(/<img\b[^>]*>/gi, ''));
    if (residualText.length > 0) {
      return [];
    }
    return CookedHtmlParser.collectImageBlocks(innerHtml);
  }

  private static collectImageBlocks(html: string): RichBlock[] {
    const blocks: RichBlock[] = [];
    let index: number = 0;
    let pendingHref: string = '';

    while (index < html.length) {
      const nextTag: number = html.indexOf('<', index);
      if (nextTag < 0) {
        break;
      }
      const tagEnd: number = CookedHtmlParser.findTagEnd(html, nextTag);
      if (tagEnd < 0) {
        break;
      }

      const tag: string = html.substring(nextTag, tagEnd + 1);
      const name: string = CookedHtmlParser.getTagName(tag);
      if (name === 'a') {
        pendingHref = CookedHtmlParser.isClosingTag(tag) ? '' : CookedHtmlParser.extractAttr(tag, 'href');
      } else if (name === 'img' && !CookedHtmlParser.isClosingTag(tag)) {
        const block: RichBlock | undefined = CookedHtmlParser.imageBlockFromTag(tag, pendingHref);
        if (block) {
          blocks.push(block);
        }
      }

      index = tagEnd + 1;
    }

    return blocks;
  }

  private static mixedBlocks(innerHtml: string): RichBlock[] {
    // 处理"图 + 文字混排"容器：Discourse 会把图片和正文塞进同一个 <p>，例如
    // <p><div class="lightbox-wrapper">图</div><br>文字</p>，或未套 lightbox 的独立大图/动图
    // <p>文字<br><img class="animated" width="690"></p>。按"图片单元"切分：图片各自成 IMAGE 块、
    // 文字成段落，避免大图退化成一个 18px 行内小图。
    const result: RichBlock[] = [];
    let rest: string = innerHtml;
    let guard: number = 0;
    while (rest.length > 0 && guard < 200) {
      guard++;
      const unit: LightboxUnit | undefined = CookedHtmlParser.findImageUnit(rest);
      if (!unit) {
        result.push(...CookedHtmlParser.paragraphBlocks(rest));
        break;
      }
      if (CookedHtmlParser.toPlainText(unit.before).length > 0) {
        result.push(...CookedHtmlParser.paragraphBlocks(unit.before));
      }
      result.push(...CookedHtmlParser.collectImageBlocks(unit.html));
      rest = unit.after;
    }
    return result;
  }

  // 从混排 HTML 中切出下一个"图片单元"：优先匹配 lightbox 容器(div/a),其次匹配未被 lightbox
  // 包裹的独立大图/动图 <img>(见 isBlockLevelImageTag)。lightbox 容器的开标签总在其内部 <img>
  // 之前出现,故会先命中容器、整段切出,不会把容器内的图当独立图误切。
  private static findImageUnit(html: string): LightboxUnit | undefined {
    const lower: string = html.toLowerCase();
    let cursor: number = 0;
    while (cursor < html.length) {
      const tagStart: number = lower.indexOf('<', cursor);
      if (tagStart < 0) {
        return undefined;
      }
      const tagEnd: number = CookedHtmlParser.findTagEnd(html, tagStart);
      if (tagEnd < 0) {
        return undefined;
      }
      const tag: string = html.substring(tagStart, tagEnd + 1);
      const name: string = CookedHtmlParser.getTagName(tag);
      if ((name === 'div' || name === 'a') && !CookedHtmlParser.isClosingTag(tag) &&
        CookedHtmlParser.hasClassContaining(tag, 'lightbox')) {
        const closeStart: number = CookedHtmlParser.findClosingTag(html, tagEnd + 1, name);
        if (closeStart < 0) {
          return undefined;
        }
        const closeEnd: number = CookedHtmlParser.findTagEnd(html, closeStart);
        const unitEnd: number = closeEnd >= 0 ? closeEnd + 1 : closeStart;
        const unit: LightboxUnit = {
          before: html.substring(0, tagStart),
          html: html.substring(tagStart, unitEnd),
          after: html.substring(unitEnd)
        };
        return unit;
      }
      if (name === 'img' && !CookedHtmlParser.isClosingTag(tag) &&
        CookedHtmlParser.isBlockLevelImageTag(tag)) {
        const unit: LightboxUnit = {
          before: html.substring(0, tagStart),
          html: tag,
          after: html.substring(tagEnd + 1)
        };
        return unit;
      }
      cursor = tagEnd + 1;
    }
    return undefined;
  }

  // 判断一个独立 <img> 是否应按整幅图片块渲染:emoji 永远行内;动图(class="animated")或标注了
  // 大尺寸(宽或高 > INLINE_IMAGE_MAX)的图提升为块级。无尺寸又非动图的裸图保持行内(安全默认)。
  private static isBlockLevelImageTag(tag: string): boolean {
    if (CookedHtmlParser.hasClassContaining(tag, 'emoji')) {
      return false;
    }
    if (CookedHtmlParser.hasClassContaining(tag, 'animated')) {
      return true;
    }
    const width: number = CookedHtmlParser.parsePositiveNumber(CookedHtmlParser.extractAttr(tag, 'width'));
    const height: number = CookedHtmlParser.parsePositiveNumber(CookedHtmlParser.extractAttr(tag, 'height'));
    return width > INLINE_IMAGE_MAX || height > INLINE_IMAGE_MAX;
  }

  private static imageBlockFromTag(tag: string, href: string): RichBlock | undefined {
    // 优先取 srcset 里倍率最高的那档(通常 2x),而不是 src。
    // Discourse 的 src 是按 CSS 像素切的最小档(如 253×375),手机普遍 3x DPI,直接渲染必糊;
    // srcset 一般给到 2x(506×750),清晰度够且远小于原图(href,如 940×1388/132KB)——
    // 正文图最宽也就铺满屏宽,上原图纯属浪费流量与解码内存。
    const src: string = CookedHtmlParser.resolveUrl(
      CookedHtmlParser.bestSrcFromTag(tag));
    if (src.length === 0) {
      return undefined;
    }

    const block: RichBlock = {
      type: RichBlockType.IMAGE,
      src,
      alt: CookedHtmlParser.decodeHtmlEntities(CookedHtmlParser.extractAttr(tag, 'alt')),
      width: CookedHtmlParser.parsePositiveNumber(CookedHtmlParser.extractAttr(tag, 'width')),
      height: CookedHtmlParser.parsePositiveNumber(CookedHtmlParser.extractAttr(tag, 'height'))
    };

    const resolvedHref: string = CookedHtmlParser.resolveUrl(href);
    if (resolvedHref.length > 0) {
      block.href = resolvedHref;
    }
    return block;
  }

  // 从段落 HTML 中切出内嵌的 <audio>/<video>,提升为媒体块;媒体前后残留的文字各自成段。媒体元素
  // 内部的 <source> 与降级 <a> 链接连同整个媒体标签一并被切走,不会再作为正文链接重复渲染。
  // 未命中任何媒体则返回 undefined,交回上层走 mixedBlocks。
  private static mediaParagraphBlocks(innerHtml: string): RichBlock[] | undefined {
    const result: RichBlock[] = [];
    let rest: string = innerHtml;
    let found: boolean = false;
    let guard: number = 0;
    while (guard < 50) {
      guard++;
      const lower: string = rest.toLowerCase();
      const audioAt: number = lower.indexOf('<audio');
      const videoAt: number = lower.indexOf('<video');
      let tagStart: number = -1;
      let mediaTag: string = '';
      if (audioAt >= 0 && (videoAt < 0 || audioAt < videoAt)) {
        tagStart = audioAt;
        mediaTag = 'audio';
      } else if (videoAt >= 0) {
        tagStart = videoAt;
        mediaTag = 'video';
      }
      if (tagStart < 0) {
        break;
      }
      const tagEnd: number = CookedHtmlParser.findTagEnd(rest, tagStart);
      if (tagEnd < 0) {
        break;
      }
      const openTag: string = rest.substring(tagStart, tagEnd + 1);
      const closeStart: number = CookedHtmlParser.findClosingTag(rest, tagEnd + 1, mediaTag);
      if (closeStart < 0) {
        break;
      }
      const closeEnd: number = CookedHtmlParser.findTagEnd(rest, closeStart);
      const mediaInner: string = rest.substring(tagEnd + 1, closeStart);
      const mediaBlock: RichBlock | undefined = CookedHtmlParser.mediaBlockFromElement(mediaTag, openTag, mediaInner);
      if (!mediaBlock) {
        break;
      }
      const before: string = rest.substring(0, tagStart);
      if (CookedHtmlParser.toPlainText(before).length > 0) {
        result.push(...CookedHtmlParser.paragraphBlocks(before));
      }
      result.push(mediaBlock);
      found = true;
      rest = closeEnd >= 0 ? rest.substring(closeEnd + 1) : '';
    }
    if (!found) {
      return undefined;
    }
    if (CookedHtmlParser.toPlainText(rest).length > 0) {
      result.push(...CookedHtmlParser.paragraphBlocks(rest));
    }
    return result;
  }

  // <audio>/<video> → 媒体块。源优先取内部首个 <source src>(其 type 作 MIME),缺失时回退标签自身 src。
  // <video> 额外带 width/height 供渲染定尺寸。无有效 src 则返回 undefined,交回上层走「不支持」降级。
  private static mediaBlockFromElement(tagName: string, openTag: string, innerHtml: string): RichBlock | undefined {
    let src: string = '';
    let mediaType: string = '';
    const sourceMatch: RegExpMatchArray | null = innerHtml.match(/<source\b[^>]*>/i);
    if (sourceMatch) {
      src = CookedHtmlParser.extractAttr(sourceMatch[0], 'src');
      mediaType = CookedHtmlParser.extractAttr(sourceMatch[0], 'type');
    }
    if (src.length === 0) {
      src = CookedHtmlParser.extractAttr(openTag, 'src');
    }
    const resolvedSrc: string = CookedHtmlParser.resolveUrl(src);
    if (resolvedSrc.length === 0) {
      return undefined;
    }

    const block: RichBlock = {
      type: tagName === 'video' ? RichBlockType.VIDEO : RichBlockType.AUDIO,
      src: resolvedSrc
    };
    if (mediaType.length > 0) {
      block.mediaType = mediaType;
    }
    if (tagName === 'video') {
      block.width = CookedHtmlParser.parsePositiveNumber(CookedHtmlParser.extractAttr(openTag, 'width'));
      block.height = CookedHtmlParser.parsePositiveNumber(CookedHtmlParser.extractAttr(openTag, 'height'));
    }
    return block;
  }

  private static extractCodeLanguage(codeOpenTag: string): string {
    const className: string = CookedHtmlParser.extractAttr(codeOpenTag, 'class');
    const languageMatch: RegExpMatchArray | null = className.match(/(?:lang|language)-([a-zA-Z0-9_+-]+)/);
    if (!languageMatch) {
      return '';
    }
    return languageMatch[1];
  }

  private static stripTagsKeepingLines(html: string): string {
    let text: string = html ? html : '';
    text = text.replace(/<br\s*\/?>/gi, '\n');
    text = text.replace(/<\/p>/gi, '\n');
    text = text.replace(/<\/div>/gi, '\n');
    text = text.replace(/<\/li>/gi, '\n');
    text = text.replace(/<li\b[^>]*>/gi, '- ');
    text = text.replace(/<[^>]+>/g, '');
    return CookedHtmlParser.decodeHtmlEntities(text);
  }

  private static normalizeText(text: string): string {
    return text
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n[ \t]+/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private static decodeHtmlEntities(text: string): string {
    return (text ? text : '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&#x([0-9a-fA-F]+);/g, (_match: string, hex: string): string => {
        const code: number = parseInt(hex, 16);
        return isNaN(code) ? '' : String.fromCharCode(code);
      })
      .replace(/&#([0-9]+);/g, (_match: string, dec: string): string => {
        const code: number = parseInt(dec, 10);
        return isNaN(code) ? '' : String.fromCharCode(code);
      });
  }

  private static resolveUrl(rawUrl: string): string {
    const url: string = CookedHtmlParser.decodeHtmlEntities(rawUrl).trim();
    if (url.length === 0 || url.startsWith('upload://')) {
      return url;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return `https:${url}`;
    }
    if (url.startsWith(EMOJI_PATH_PREFIX)) {
      // 正文 cooked 里的 emoji 服务端已改写成 CDN 绝对地址,但 discourse-boosts 的 cooked 不走那套改写,
      // 吐的是站内相对路径。拼 BASE_URL 会得到必然加载不出的主站直链,故这里挂 CDN(同一份文件)。
      return `${AppConstants.STATIC_CDN_BASE}${url}`;
    }
    if (url.startsWith('/')) {
      return `${AppConstants.BASE_URL}${url}`;
    }
    return url;
  }

  // 从 <img> 选出最清晰的可用地址:srcset 里倍率最大的一档,没有 srcset 则回退 src。
  // srcset 形如 "url1, url2 1.5x, url3 2x"(首项无描述符即 1x)。逗号也可能出现在 URL 里,
  // 故按「逗号 + 空白」切分而非裸逗号。宽度描述符(w)本项目未见,一并兼容:按数值取最大。
  private static bestSrcFromTag(tag: string): string {
    const src: string = CookedHtmlParser.extractAttr(tag, 'src');
    const srcset: string = CookedHtmlParser.extractAttr(tag, 'srcset');
    if (srcset.length === 0) {
      return src;
    }

    const candidates: string[] = srcset.split(/,\s+/);
    let bestUrl: string = '';
    let bestScale: number = 0;
    for (let index: number = 0; index < candidates.length; index++) {
      const entry: string = candidates[index].trim();
      if (entry.length === 0) {
        continue;
      }
      const parts: string[] = entry.split(/\s+/);
      const url: string = parts[0];
      if (url.length === 0) {
        continue;
      }
      // 无描述符 = 1x;有则去掉尾部 x/w 取数值。解析不出就按 1 算,不至于丢掉这一档。
      let scale: number = 1;
      if (parts.length > 1) {
        const parsed: number = Number.parseFloat(parts[1].replace(/[xw]$/i, ''));
        if (!Number.isNaN(parsed) && parsed > 0) {
          scale = parsed;
        }
      }
      if (scale > bestScale) {
        bestScale = scale;
        bestUrl = url;
      }
    }
    return bestUrl.length > 0 ? bestUrl : src;
  }

  private static extractAttr(tag: string, attrName: string): string {
    const pattern: RegExp = new RegExp(`${attrName}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i');
    const match: RegExpMatchArray | null = tag.match(pattern);
    if (!match) {
      return '';
    }
    return match[2] ? match[2] : (match[3] ? match[3] : (match[4] ? match[4] : ''));
  }

  private static hasClass(tag: string, className: string): boolean {
    const classes: string = CookedHtmlParser.extractAttr(tag, 'class').toLowerCase();
    return classes.split(/\s+/).indexOf(className.toLowerCase()) >= 0;
  }

  private static hasClassContaining(tag: string, keyword: string): boolean {
    const classes: string[] = CookedHtmlParser.extractAttr(tag, 'class').toLowerCase().split(/\s+/);
    const lowerKeyword: string = keyword.toLowerCase();
    for (let index: number = 0; index < classes.length; index++) {
      if (classes[index].indexOf(lowerKeyword) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static parsePositiveNumber(raw: string): number {
    const value: number = parseInt(raw, 10);
    if (isNaN(value) || value <= 0) {
      return 0;
    }
    return value;
  }

  private static findTagEnd(html: string, tagStart: number): number {
    let quote: string = '';
    for (let index: number = tagStart; index < html.length; index++) {
      const ch: string = html.charAt(index);
      if ((ch === '"' || ch === "'") && quote.length === 0) {
        quote = ch;
      } else if (ch === quote) {
        quote = '';
      } else if (ch === '>' && quote.length === 0) {
        return index;
      }
    }
    return -1;
  }

  private static findClosingTag(html: string, fromIndex: number, tagName: string): number {
    const lower: string = html.toLowerCase();
    const lowerTag: string = tagName.toLowerCase();
    let depth: number = 1;
    let index: number = fromIndex;

    while (index < lower.length) {
      const nextOpen: number = lower.indexOf(`<${lowerTag}`, index);
      const nextClose: number = lower.indexOf(`</${lowerTag}`, index);
      if (nextClose < 0) {
        return -1;
      }

      if (nextOpen >= 0 && nextOpen < nextClose) {
        const openEnd: number = CookedHtmlParser.findTagEnd(html, nextOpen);
        if (openEnd < 0) {
          return -1;
        }
        const openTag: string = html.substring(nextOpen, openEnd + 1);
        if (!CookedHtmlParser.isSelfClosingTag(openTag)) {
          depth++;
        }
        index = openEnd + 1;
        continue;
      }

      depth--;
      if (depth === 0) {
        return nextClose;
      }
      const closeEnd: number = CookedHtmlParser.findTagEnd(html, nextClose);
      index = closeEnd >= 0 ? closeEnd + 1 : nextClose + lowerTag.length + 3;
    }

    return -1;
  }

  private static getTagName(tag: string): string {
    const match: RegExpMatchArray | null = tag.match(/^<\/?\s*([a-zA-Z0-9]+)/);
    return match ? match[1].toLowerCase() : '';
  }

  private static isClosingTag(tag: string): boolean {
    return /^<\//.test(tag);
  }

  private static isSelfClosingTag(tag: string): boolean {
    const tagName: string = CookedHtmlParser.getTagName(tag);
    return /\/\s*>$/.test(tag) || tagName === 'br' || tagName === 'img' || tagName === 'hr';
  }

  private static isHeadingTag(tagName: string): boolean {
    return /^h[1-6]$/.test(tagName);
  }

  private static isBlockTag(tagName: string): boolean {
    return tagName === 'p' ||
      tagName === 'blockquote' ||
      tagName === 'aside' ||
      tagName === 'pre' ||
      tagName === 'ul' ||
      tagName === 'ol' ||
      tagName === 'hr' ||
      tagName === 'img' ||
      tagName === 'div' ||
      tagName === 'figure' ||
      tagName === 'table' ||
      tagName === 'details' ||
      tagName === 'audio' ||
      tagName === 'video' ||
      tagName === 'iframe' ||
      CookedHtmlParser.isHeadingTag(tagName);
  }

  private static shouldReadChildrenAsPlainText(tagName: string): boolean {
    return tagName === 'script' || tagName === 'style';
  }

  private static hasBlockContent(block: RichBlock): boolean {
    if (block.type === RichBlockType.PARAGRAPH || block.type === RichBlockType.HEADING) {
      return !!block.inlines && block.inlines.length > 0;
    }
    if (block.type === RichBlockType.QUOTE) {
      return !!block.blocks && block.blocks.length > 0;
    }
    if (block.type === RichBlockType.CODE || block.type === RichBlockType.MATH) {
      return !!block.text && block.text.length > 0;
    }
    if (block.type === RichBlockType.UNSUPPORTED) {
      return (!!block.text && block.text.length > 0) || (!!block.unsupportedKind && block.unsupportedKind.length > 0);
    }
    if (block.type === RichBlockType.IMAGE ||
      block.type === RichBlockType.AUDIO ||
      block.type === RichBlockType.VIDEO) {
      return !!block.src && block.src.length > 0;
    }
    if (block.type === RichBlockType.LIST) {
      return !!block.items && block.items.length > 0;
    }
    if (block.type === RichBlockType.TABLE) {
      return !!block.tableRows && block.tableRows.length > 0;
    }
    if (block.type === RichBlockType.DISCLOSURE) {
      return (!!block.title && block.title.length > 0) || (!!block.blocks && block.blocks.length > 0);
    }
    if (block.type === RichBlockType.SPOILER) {
      return !!block.blocks && block.blocks.length > 0;
    }
    if (block.type === RichBlockType.CALLOUT) {
      // 有标题或有正文即保留;二者皆空的极端情形也留着(至少能显示类型名标题)。
      return true;
    }
    if (block.type === RichBlockType.POLL) {
      // POLL 块无 inlines/blocks,仅靠 pollName 占位,别被内容过滤器丢掉。
      return true;
    }
    if (block.type === RichBlockType.ONEBOX) {
      return (!!block.href && block.href.length > 0) ||
        (!!block.title && block.title.length > 0) ||
        (!!block.domain && block.domain.length > 0);
    }
    return true;
  }
}
