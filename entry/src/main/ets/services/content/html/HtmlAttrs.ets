// HTML 属性读取。只依赖字符串与正则,不依赖词法层与任何领域类型。

// 从标签文本取属性值,支持双引号 / 单引号 / 无引号三种写法。取不到返回空串。
export function extractAttr(tag: string, attrName: string): string {
  const pattern: RegExp = new RegExp(`${attrName}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i');
  const match: RegExpMatchArray | null = tag.match(pattern);
  if (!match) {
    return '';
  }
  return match[2] ? match[2] : (match[3] ? match[3] : (match[4] ? match[4] : ''));
}

// class 精确命中(整个 class 名相等)。
export function hasClass(tag: string, className: string): boolean {
  const classes: string = extractAttr(tag, 'class').toLowerCase();
  return classes.split(/\s+/).indexOf(className.toLowerCase()) >= 0;
}

// class 模糊命中(任一 class 名包含该关键字)。
// Discourse 有大量带后缀的 class(如 poll-outer / lightbox-wrapper),精确匹配挡不住。
export function hasClassContaining(tag: string, keyword: string): boolean {
  const classes: string[] = extractAttr(tag, 'class').toLowerCase().split(/\s+/);
  const lowerKeyword: string = keyword.toLowerCase();
  for (let index: number = 0; index < classes.length; index++) {
    if (classes[index].indexOf(lowerKeyword) >= 0) {
      return true;
    }
  }
  return false;
}

// 从 img 标签取最优图源:有 srcset 时挑倍率最高的一档,否则退回 src。
// Discourse 的 srcset 形如 "a.png, b.png 1.5x, c.png 2x";无描述符按 1x 计。
export function bestSrcFromTag(tag: string): string {
  const src: string = extractAttr(tag, 'src');
  const srcset: string = extractAttr(tag, 'srcset');
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

// 解析正整数(用于 width/height 属性)。非法或非正数一律返回 0,由调用方当作「未提供」。
export function parsePositiveNumber(raw: string): number {
  const value: number = parseInt(raw, 10);
  if (isNaN(value) || value <= 0) {
    return 0;
  }
  return value;
}
