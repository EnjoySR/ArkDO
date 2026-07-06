import { AppConstants } from '../../common/constants/AppConstants';

export enum RichBlockType {
  PARAGRAPH = 'paragraph',
  HEADING = 'heading',
  QUOTE = 'quote',
  CODE = 'code',
  IMAGE = 'image',
  LIST = 'list',
  DISCLOSURE = 'disclosure',
  DIVIDER = 'divider',
  POLL = 'poll',
  UNSUPPORTED = 'unsupported'
}

export enum RichInlineType {
  TEXT = 'text',
  LINK = 'link',
  CODE = 'code',
  IMAGE = 'image',
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
}

export interface RichListItem {
  inlines: RichInlineNode[];
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
  ordered?: boolean;
  level?: number;
  // POLL 块:data-poll-name,用于在正文正确位置占位、并按名字关联 TopicPost.polls 的动态数据。
  pollName?: string;
}

class InlineState {
  bold: number = 0;
  italic: number = 0;
  code: number = 0;
  hrefStack: string[] = [];

  clone(): InlineState {
    const state: InlineState = new InlineState();
    state.bold = this.bold;
    state.italic = this.italic;
    state.code = this.code;
    state.hrefStack = this.hrefStack.slice();
    return state;
  }

  currentHref(): string {
    if (this.hrefStack.length === 0) {
      return '';
    }
    return this.hrefStack[this.hrefStack.length - 1];
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
      }
      return [{
        type: RichBlockType.QUOTE,
        blocks: quoteBlocks.length > 0 ? quoteBlocks : CookedHtmlParser.paragraphBlocks(innerHtml)
      }];
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
      const last: RichInlineNode | undefined = out.length > 0 ? out[out.length - 1] : undefined;
      if (last &&
        last.type === type &&
        (last.href ? last.href : '') === href &&
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
      } else if (tagName === 'a') {
        flush();
        if (closing) {
          state.hrefStack.pop();
        } else {
          state.hrefStack.push(CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(tag, 'href')));
        }
      } else if (tagName === 'img' && !closing) {
        flush();
        const src: string = CookedHtmlParser.resolveUrl(CookedHtmlParser.extractAttr(tag, 'src'));
        const alt: string = CookedHtmlParser.decodeHtmlEntities(CookedHtmlParser.extractAttr(tag, 'alt'));
        if (src.length > 0) {
          out.push({
            type: RichInlineType.IMAGE,
            text: alt.length > 0 ? alt : ' ',
            src,
            alt,
            href: state.currentHref()
          });
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
      items.push({
        inlines: CookedHtmlParser.parseInlines(itemHtml)
      });
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

    if (CookedHtmlParser.hasClassContaining(openTag, 'spoiler') ||
      CookedHtmlParser.hasClassContaining(openTag, 'spoiled')) {
      return '折叠/剧透内容';
    }

    if (tagName === 'video' || tagName === 'iframe' ||
      combined.indexOf('<video') >= 0 ||
      combined.indexOf('<iframe') >= 0) {
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
    // 处理"图 + 文字混排"容器：Discourse 会把 lightbox 图片和正文塞进同一个 <p>，
    // 例如 <p><div class="lightbox-wrapper">图</div><br>文字</p>。按 lightbox 单元切分，
    // 图片各自成 IMAGE 块、文字成段落，避免整段退化成一个 18px 行内小图。
    const result: RichBlock[] = [];
    let rest: string = innerHtml;
    let guard: number = 0;
    while (rest.length > 0 && guard < 200) {
      guard++;
      const unit: LightboxUnit | undefined = CookedHtmlParser.findLightboxUnit(rest);
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

  private static findLightboxUnit(html: string): LightboxUnit | undefined {
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
      cursor = tagEnd + 1;
    }
    return undefined;
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
    if (block.type === RichBlockType.CODE) {
      return !!block.text && block.text.length > 0;
    }
    if (block.type === RichBlockType.UNSUPPORTED) {
      return (!!block.text && block.text.length > 0) || (!!block.unsupportedKind && block.unsupportedKind.length > 0);
    }
    if (block.type === RichBlockType.IMAGE) {
      return !!block.src && block.src.length > 0;
    }
    if (block.type === RichBlockType.LIST) {
      return !!block.items && block.items.length > 0;
    }
    if (block.type === RichBlockType.DISCLOSURE) {
      return (!!block.title && block.title.length > 0) || (!!block.blocks && block.blocks.length > 0);
    }
    if (block.type === RichBlockType.POLL) {
      // POLL 块无 inlines/blocks,仅靠 pollName 占位,别被内容过滤器丢掉。
      return true;
    }
    return true;
  }
}
