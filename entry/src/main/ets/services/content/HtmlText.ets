// HTML 片段 → 纯文本工具:书签摘要、用户动态摘要等列表场景共用。
// 只做"去标签 + 解实体 + 折叠空白",不解析结构(结构化渲染走 CookedHtmlParser)。
export class HtmlText {
  // 去标签、解码实体、折叠空白。提及 <a class="mention">@x</a> → @x;
  // 图片 <a class="lightbox">[image]</a> → [image]。
  static toPlainText(html?: string): string {
    if (!html || html.length === 0) {
      return '';
    }
    let text: string = html.replace(/<[^>]*>/g, '');
    text = HtmlText.decodeEntities(text);
    text = text.replace(/\s+/g, ' ').trim();
    return text;
  }

  static decodeEntities(input: string): string {
    if (input.indexOf('&') < 0) {
      return input;
    }
    let text: string = input
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&apos;/g, "'")
      .replace(/&nbsp;/g, ' ')
      .replace(/&hellip;/g, '…')
      .replace(/&mdash;/g, '—')
      .replace(/&ndash;/g, '–');
    // 数字实体 &#123; / &#x1F;
    text = text.replace(/&#(\d+);/g, (_match: string, dec: string): string => {
      const code: number = Number.parseInt(dec, 10);
      return Number.isNaN(code) ? '' : String.fromCharCode(code);
    });
    text = text.replace(/&#[xX]([0-9a-fA-F]+);/g, (_match: string, hex: string): string => {
      const code: number = Number.parseInt(hex, 16);
      return Number.isNaN(code) ? '' : String.fromCharCode(code);
    });
    // &amp; 最后解,避免把上面已解出的实体二次误伤。
    text = text.replace(/&amp;/g, '&');
    return text;
  }
}
