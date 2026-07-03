import { describe, it, expect } from '@ohos/hypium';
import { CookedHtmlParser, RichBlock, RichBlockType, RichInlineNode, RichInlineType } from '../main/ets/services/content/CookedHtmlParser';

export default function cookedHtmlParserTest() {
  describe('cookedHtmlParserTest', () => {
    it('parsesParagraphInlineStylesAndLinks', 0, () => {
      const blocks: RichBlock[] = CookedHtmlParser.parse('<p>Hello <strong>ArkDO</strong> <a href="/t/123">Linux.do</a> <code>x()</code></p>');

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.PARAGRAPH);
      const inlines: RichInlineNode[] = blocks[0].inlines ? blocks[0].inlines as RichInlineNode[] : [];
      expect(inlines.length).assertEqual(5);
      expect(inlines[0].text).assertEqual('Hello ');
      expect(inlines[1].text).assertEqual('ArkDO');
      expect(inlines[1].bold).assertTrue();
      expect(inlines[3].type).assertEqual(RichInlineType.LINK);
      expect(inlines[3].text).assertEqual('Linux.do');
      expect(inlines[3].href).assertEqual('https://linux.do/t/123');
      expect(inlines[4].type).assertEqual(RichInlineType.CODE);
      expect(inlines[4].text).assertEqual('x()');
    });

    it('parsesQuoteCodeImageListAndDividerBlocks', 0, () => {
      const html: string = '<blockquote><p>引用 <em>内容</em></p></blockquote>' +
        '<pre><code class="lang-js">const a = 1;</code></pre>' +
        '<p><img src="/uploads/default/original/1X/a.png" alt="pic" width="320" height="180"></p>' +
        '<ul><li>第一项</li><li><a href="/u/nooop">用户</a></li></ul><hr>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(5);
      expect(blocks[0].type).assertEqual(RichBlockType.QUOTE);
      expect(blocks[1].type).assertEqual(RichBlockType.CODE);
      expect(blocks[1].text).assertEqual('const a = 1;');
      expect(blocks[1].language).assertEqual('js');
      expect(blocks[2].type).assertEqual(RichBlockType.IMAGE);
      expect(blocks[2].src).assertEqual('https://linux.do/uploads/default/original/1X/a.png');
      expect(blocks[2].width).assertEqual(320);
      expect(blocks[2].height).assertEqual(180);
      expect(blocks[3].type).assertEqual(RichBlockType.LIST);
      expect(blocks[3].ordered).assertFalse();
      expect(blocks[3].items?.length).assertEqual(2);
      expect(blocks[4].type).assertEqual(RichBlockType.DIVIDER);
    });

    it('marksUnsupportedDiscourseBlocksAsTodo', 0, () => {
      const html: string = '<div class="poll" data-poll-name="poll"><div class="poll-container">选项 A</div></div>' +
        '<table><tr><td>A</td></tr></table>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(2);
      expect(blocks[0].type).assertEqual(RichBlockType.UNSUPPORTED);
      expect(blocks[0].unsupportedKind).assertEqual('投票');
      expect(blocks[0].text).assertEqual('选项 A');
      expect(blocks[1].type).assertEqual(RichBlockType.UNSUPPORTED);
      expect(blocks[1].unsupportedKind).assertEqual('表格');
      expect(blocks[1].text).assertEqual('A');
    });
  });
}
