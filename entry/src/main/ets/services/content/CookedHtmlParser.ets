import { AppConstants } from '../../common/constants/AppConstants';

export enum RichBlockType {
  PARAGRAPH = 'paragraph',
  HEADING = 'heading',
  QUOTE = 'quote',
  CODE = 'code',
  IMAGE = 'image',
  LIST = 'list',
  DIVIDER = 'divider',
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
  unsupportedKind?: string;
  language?: string;
  src?: string;
  alt?: string;
  width?: number;
  height?: number;
  href?: string;
  ordered?: boolean;
  level?: number;
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

export class CookedHtmlParser {
  static parse(html: string): RichBlock[] {
    const source: string = html ? html : '';
    const blocks: RichBlock[] = CookedHtmlParser.parseBlocks(source);
    return blocks.filter((block: RichBlock) => CookedHtmlParser.hasBlockContent(block));
  }

  static toPlainText(html: string): string {
    return CookedHtmlParser.normalizeText(CookedHtmlParser.stripTagsKeepingLines(html));
  }

  private static parseBlocks(html: string): RichBlock[] {
    const blocks: RichBlock[] = [];
    let index: number = 0;
    let pendingInlineHtml: string = '';

    const flushPendingInline = (): void => {
      const inlines: RichInlineNode[] = CookedHtmlParser.parseInlines(pendingInlineHtml);
      pendingInlineHtml = '';
      if (inlines.length > 0) {
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
      return CookedHtmlParser.paragraphBlocks(innerHtml);
    }

    if (CookedHtmlParser.isHeadingTag(tagName)) {
      return [{
        type: RichBlockType.HEADING,
        level: Number(tagName.substring(1)),
        inlines: CookedHtmlParser.parseInlines(innerHtml)
      }];
    }

    if (tagName === 'blockquote' || (tagName === 'aside' && CookedHtmlParser.hasClass(openTag, 'quote'))) {
      const quoteBlocks: RichBlock[] = CookedHtmlParser.parseBlocks(innerHtml);
      return [{
        type: RichBlockType.QUOTE,
        blocks: quoteBlocks.length > 0 ? quoteBlocks : CookedHtmlParser.paragraphBlocks(innerHtml)
      }];
    }

    if (tagName === 'pre') {
      return [CookedHtmlParser.codeBlockFromPre(innerHtml)];
    }

    if (tagName === 'ul' || tagName === 'ol') {
      return [CookedHtmlParser.listBlockFromHtml(innerHtml, tagName === 'ol')];
    }

    const unsupportedKind: string = CookedHtmlParser.detectUnsupportedKind(tagName, openTag, innerHtml);
    if (unsupportedKind.length > 0) {
      return [CookedHtmlParser.unsupportedBlock(unsupportedKind, innerHtml)];
    }

    if (tagName === 'figure' || tagName === 'div') {
      const imageBlock: RichBlock | undefined = CookedHtmlParser.firstImageBlock(innerHtml);
      const text: string = CookedHtmlParser.toPlainText(innerHtml);
      if (imageBlock && text.length === 0) {
        return [imageBlock];
      }
      if (text.length > 0) {
        return CookedHtmlParser.paragraphBlocks(innerHtml);
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
    if (inlines.length === 0) {
      return [];
    }
    return [{
      type: RichBlockType.PARAGRAPH,
      inlines
    }];
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
    return compacted.filter((token: RichInlineNode) => token.type !== RichInlineType.TEXT || token.text.length > 0);
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

    if (tagName === 'details' ||
      CookedHtmlParser.hasClassContaining(openTag, 'spoiler') ||
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
    return undefined;
  }

  private static firstImageBlock(innerHtml: string): RichBlock | undefined {
    const imageMatch: RegExpMatchArray | null = innerHtml.match(/<img\b[^>]*>/i);
    if (!imageMatch) {
      return undefined;
    }
    return CookedHtmlParser.imageBlockFromTag(imageMatch[0], '');
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
    return true;
  }
}
