import { AppConstants } from '../../common/constants/AppConstants';

// 行内小图(emoji/小图标)的尺寸上限,与渲染层 PostRichContent.SMALL_IMAGE_MAX 对齐:
// 宽或高超过它的独立 <img>(或动图)视为整幅内容图,提升为 IMAGE 块,不再压成 18px 行内图。
const INLINE_IMAGE_MAX: number = 48;

export enum RichBlockType {
  PARAGRAPH = 'paragraph',
  HEADING = 'heading',
  QUOTE = 'quote',
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
}

export interface RichListItem {
  inlines: RichInlineNode[];
  // 列表项内含块级图(lightbox/大图)时改用 blocks:文字成段落、图片各自成块级 IMAGE,
  // 避免大图退化成 18px 行内小图。纯文字项仍只用 inlines(blocks 缺省)。
  blocks?: RichBlock[];
}

export interface RichBlock {
  type: RichBlockType;
  inlines?: RichInlineNode[];
  blocks?: RichBlock[];
  items?: RichListItem[];
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
    return blocks.filter((block: RichBlock) => CookedHtmlParser.hasBlockContent(block));
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
    const src: string = CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(tag, 'src'));
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
    if (url.startsWith('/')) {
      return `${AppConstants.BASE_URL}${url}`;
    }
    return url;
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
