// HTML 词法原语:标签定位与标签名判定。
//
// 从 CookedHtmlParser 抽出——这一层零依赖(不认识 RichBlock,不认识 Discourse),
// 是整个解析栈的最底层,单独成文件后可直接单测,不必构造完整的 cooked HTML。
//
// 注意这不是一个合规的 HTML 解析器,而是针对 Discourse 输出的 cooked HTML 的实用扫描器:
// 输入已经是服务端清洗过的良构片段,故不处理注释、CDATA、畸形嵌套等一般 HTML 的边界情况。

// 从 fromIndex 起找 <tagName 的开标签起点。
// 必须校验标签名后的下一个字符,否则找 <a 会命中 <aside、找 <p 会命中 <pre。
export function findOpenTag(html: string, tagName: string, fromIndex: number): number {
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

// 从 tagStart 起找该标签的 '>' 位置。
// 必须跟引号状态:属性值里的 '>' (如 alt="a > b")不是标签结束。
export function findTagEnd(html: string, tagStart: number): number {
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

// 找与 fromIndex 处开标签配对的 </tagName 位置,按嵌套深度配对。
// 自闭合的同名标签不增加深度,否则 <div/> 会把配对错位一层。
export function findClosingTag(html: string, fromIndex: number, tagName: string): number {
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
      const openEnd: number = findTagEnd(html, nextOpen);
      if (openEnd < 0) {
        return -1;
      }
      const openTag: string = html.substring(nextOpen, openEnd + 1);
      if (!isSelfClosingTag(openTag)) {
        depth++;
      }
      index = openEnd + 1;
      continue;
    }

    depth--;
    if (depth === 0) {
      return nextClose;
    }
    const closeEnd: number = findTagEnd(html, nextClose);
    index = closeEnd >= 0 ? closeEnd + 1 : nextClose + lowerTag.length + 3;
  }

  return -1;
}

// 从完整标签文本取小写标签名,如 '<IMG src="x">' → 'img'。取不到返回空串。
export function getTagName(tag: string): string {
  const match: RegExpMatchArray | null = tag.match(/^<\/?\s*([a-zA-Z0-9]+)/);
  return match ? match[1].toLowerCase() : '';
}

export function isClosingTag(tag: string): boolean {
  return /^<\//.test(tag);
}

// 显式自闭合(以 /> 结尾)或 HTML 空元素。这里只列 cooked HTML 里实际会出现的三个。
export function isSelfClosingTag(tag: string): boolean {
  const tagName: string = getTagName(tag);
  return /\/\s*>$/.test(tag) || tagName === 'br' || tagName === 'img' || tagName === 'hr';
}

export function isHeadingTag(tagName: string): boolean {
  return /^h[1-6]$/.test(tagName);
}

// 块级标签:遇到它就要结束当前段落、另起一个 RichBlock。
export function isBlockTag(tagName: string): boolean {
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
    isHeadingTag(tagName);
}

// 内容按纯文本读、不再往里解析标签的容器。
export function shouldReadChildrenAsPlainText(tagName: string): boolean {
  return tagName === 'script' || tagName === 'style';
}
