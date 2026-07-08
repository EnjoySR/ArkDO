import { describe, it, expect } from '@ohos/hypium';
import { CookedHtmlParser, RichBlock, RichBlockType, RichInlineNode, RichInlineType } from '../main/ets/services/content/CookedHtmlParser';

export default function cookedHtmlParserTest() {
  describe('cookedHtmlParserTest', () => {
    it('parsesParagraphInlineStylesAndLinks', 0, () => {
      const blocks: RichBlock[] = CookedHtmlParser.parse('<p>Hello <strong>ArkDO</strong> <a href="/t/123">Linux.do</a> <code>x()</code></p>');

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.PARAGRAPH);
      const inlines: RichInlineNode[] = blocks[0].inlines ? blocks[0].inlines as RichInlineNode[] : [];
      expect(inlines.length).assertEqual(6);
      expect(inlines[0].text).assertEqual('Hello ');
      expect(inlines[1].text).assertEqual('ArkDO');
      expect(inlines[1].bold).assertTrue();
      expect(inlines[3].type).assertEqual(RichInlineType.LINK);
      expect(inlines[3].text).assertEqual('Linux.do');
      expect(inlines[3].href).assertEqual('https://linux.do/t/123');
      expect(inlines[5].type).assertEqual(RichInlineType.CODE);
      expect(inlines[5].text).assertEqual('x()');
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

    it('parsesDiscourseUploadPreviewLinksAsImageBlocks', 0, () => {
      const html: string = '<p><a href="/uploads/default/original/1X/full.png">' +
        '<img src="/uploads/default/optimized/1X/thumb.png" width="1684" height="236"></a>' +
        '<a class="attachment" href="/uploads/default/original/1X/full.png">image1684×236 22.4 KB</a></p>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.IMAGE);
      expect(blocks[0].src).assertEqual('https://linux.do/uploads/default/optimized/1X/thumb.png');
      expect(blocks[0].href).assertEqual('https://linux.do/uploads/default/original/1X/full.png');
      expect(blocks[0].width).assertEqual(1684);
      expect(blocks[0].height).assertEqual(236);
    });

    it('parsesDiscourseLightboxImagesAsImageBlocks', 0, () => {
      const html: string = '<div class="lightbox-wrapper"><a class="lightbox" href="/uploads/default/original/2X/full.jpeg" data-download-href="/uploads/default/xxx" title="加州街景">' +
        '<img src="/uploads/default/optimized/2X/opt.jpeg" alt="加州街景" width="1080" height="1920">' +
        '<div class="meta"><svg class="fa d-icon d-icon-far-image svg-icon"><use href="#far-image"></use></svg>' +
        '<span class="filename">加州街景</span><span class="informations">1080×1920 426 KB</span>' +
        '<svg class="fa d-icon d-icon-discourse-expand svg-icon"><use href="#discourse-expand"></use></svg></div></a></div>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.IMAGE);
      expect(blocks[0].src).assertEqual('https://linux.do/uploads/default/optimized/2X/opt.jpeg');
      expect(blocks[0].href).assertEqual('https://linux.do/uploads/default/original/2X/full.jpeg');
      expect(blocks[0].width).assertEqual(1080);
      expect(blocks[0].height).assertEqual(1920);
    });

    it('splitsLightboxImageAndTextInSameParagraph', 0, () => {
      const html: string = '<p><div class="lightbox-wrapper"><a class="lightbox" href="https://cdn.ldstatic.com/original/x.png" title="image" rel="noopener nofollow ugc">' +
        '<img src="https://cdn.ldstatic.com/optimized/x_690x432.png" alt="image" width="690" height="432" data-dominant-color="DCE0E0">' +
        '<div class="meta"><svg class="fa d-icon"><use href="#far-image"></use></svg>' +
        '<span class="filename">image</span><span class="informations">701×439 45.5 KB</span></div></a></div><br>\n' +
        '真是欲哭无泪啊 月底清零 真的6</p>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(2);
      expect(blocks[0].type).assertEqual(RichBlockType.IMAGE);
      expect(blocks[0].src).assertEqual('https://cdn.ldstatic.com/optimized/x_690x432.png');
      expect(blocks[0].href).assertEqual('https://cdn.ldstatic.com/original/x.png');
      expect(blocks[0].width).assertEqual(690);
      expect(blocks[0].height).assertEqual(432);
      expect(blocks[1].type).assertEqual(RichBlockType.PARAGRAPH);
      const textInlines: RichInlineNode[] = blocks[1].inlines ? blocks[1].inlines as RichInlineNode[] : [];
      expect(textInlines[0].text).assertEqual('真是欲哭无泪啊 月底清零 真的6');
    });

    it('promotesBareAnimatedImageInMixedParagraphToImageBlock', 0, () => {
      // 动图(class="animated")不套 lightbox,和正文塞在同一个 <p>。以前会被当行内图压成 18px,
      // 现在应切成:文字段落 + 整幅 IMAGE 块(带原始宽高,渲染层据此按比例铺满栏宽)。
      const html: string = '<p>天气卡片<br>\n' +
        '<img src="https://cdn3.ldstatic.com/original/4X/6/2/7/weather.webp" alt="PixPin" width="690" height="415" class="animated"></p>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(2);
      expect(blocks[0].type).assertEqual(RichBlockType.PARAGRAPH);
      expect(blocks[1].type).assertEqual(RichBlockType.IMAGE);
      expect(blocks[1].src).assertEqual('https://cdn3.ldstatic.com/original/4X/6/2/7/weather.webp');
      expect(blocks[1].width).assertEqual(690);
      expect(blocks[1].height).assertEqual(415);
    });

    it('keepsSmallEmojiInlineWithinMixedParagraph', 0, () => {
      // emoji(width=20 <= 48,class="emoji")必须保持行内,不能被误提升为整幅图块。
      const html: string = '<p>哈哈 <img src="https://linux.do/images/emoji/smile.png" alt=":smile:" title=":smile:" class="emoji" width="20" height="20"> 收到</p>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.PARAGRAPH);
      const inlines: RichInlineNode[] = blocks[0].inlines ? blocks[0].inlines as RichInlineNode[] : [];
      const hasInlineImage: boolean = inlines.some((node: RichInlineNode) => node.type === RichInlineType.IMAGE);
      expect(hasInlineImage).assertTrue();
    });

    it('parsesDetailsBlocksAsDisclosureBlocks', 0, () => {
      const html: string = '<details><summary>总结</summary><p>我的用户名是： Ryan119911</p></details>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.DISCLOSURE);
      expect(blocks[0].title).assertEqual('总结');
      expect(blocks[0].blocks?.length).assertEqual(1);
      expect(blocks[0].blocks?.[0].type).assertEqual(RichBlockType.PARAGRAPH);
    });

    it('rendersDiscourseAsideQuoteWithoutBlankLinesOrNestedQuote', 0, () => {
      const html: string = '<aside class="quote group-g-merchant2" data-username="claudemaster" data-display-name="opuscheap">\n' +
        '<div class="title">\n<div class="quote-controls"></div>\n' +
        '<img alt="" width="24" height="24" src="https://cdn.ldstatic.com/avatar.png" class="avatar"> opuscheap:</div>\n' +
        '<blockquote>\n<p>claudemaster</p>\n</blockquote>\n</aside>\n' +
        '<p>用户名： zuiying<br>\n谢谢佬</p>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(2);
      expect(blocks[0].type).assertEqual(RichBlockType.QUOTE);
      const quoteBlocks: RichBlock[] = blocks[0].blocks ? blocks[0].blocks as RichBlock[] : [];
      // 恰好两段：来源标题 + 引用正文；无空白段落，正文未被再包一层 QUOTE。
      expect(quoteBlocks.length).assertEqual(2);
      expect(quoteBlocks[0].type).assertEqual(RichBlockType.PARAGRAPH);
      const titleInlines: RichInlineNode[] = quoteBlocks[0].inlines ? quoteBlocks[0].inlines as RichInlineNode[] : [];
      expect(titleInlines[0].type).assertEqual(RichInlineType.IMAGE);
      expect(quoteBlocks[1].type).assertEqual(RichBlockType.PARAGRAPH);
      const bodyInlines: RichInlineNode[] = quoteBlocks[1].inlines ? quoteBlocks[1].inlines as RichInlineNode[] : [];
      expect(bodyInlines[0].text).assertEqual('claudemaster');
      expect(blocks[1].type).assertEqual(RichBlockType.PARAGRAPH);
    });

    it('parsesPollBlockWithName', 0, () => {
      const html: string =
        '<div class="poll" data-poll-name="poll"><div class="poll-container">选项 A</div></div>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.POLL);
      expect(blocks[0].pollName).assertEqual('poll');
    });

    it('parsesBlockSpoilerAsSpoilerBlockWithInnerContent', 0, () => {
      const html: string = '<div class="spoiler"><p>剧透正文 <strong>加粗</strong></p>' +
        '<p><img src="/uploads/default/original/1X/s.png" width="320" height="180"></p></div>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.SPOILER);
      const inner: RichBlock[] = blocks[0].blocks ? blocks[0].blocks as RichBlock[] : [];
      expect(inner.length).assertEqual(2);
      expect(inner[0].type).assertEqual(RichBlockType.PARAGRAPH);
      const innerInlines: RichInlineNode[] = inner[0].inlines ? inner[0].inlines as RichInlineNode[] : [];
      expect(innerInlines[0].text).assertEqual('剧透正文 ');
      expect(inner[1].type).assertEqual(RichBlockType.IMAGE);
    });

    it('marksInlineSpoilerSpansAndKeepsSurroundingTextPlain', 0, () => {
      const html: string = '<p>前文 <span class="spoiler">秘密 <em>内容</em></span> 后文</p>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.PARAGRAPH);
      const inlines: RichInlineNode[] = blocks[0].inlines ? blocks[0].inlines as RichInlineNode[] : [];
      expect(inlines.length).assertEqual(4);
      expect(inlines[0].text).assertEqual('前文 ');
      expect(!!inlines[0].spoiler).assertFalse();
      expect(inlines[1].text).assertEqual('秘密 ');
      expect(inlines[1].spoiler).assertTrue();
      expect(inlines[2].text).assertEqual('内容');
      expect(inlines[2].spoiler).assertTrue();
      expect(inlines[2].italic).assertTrue();
      expect(inlines[3].text).assertEqual(' 后文');
      expect(!!inlines[3].spoiler).assertFalse();
    });

    it('marksInlineSpoilerEmojiImage', 0, () => {
      const html: string = '<p><span class="spoiler">看这个 <img src="/images/emoji/apple/joy.png" ' +
        'title=":joy:" class="emoji" alt=":joy:" width="20" height="20"></span></p>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      const inlines: RichInlineNode[] = blocks[0].inlines ? blocks[0].inlines as RichInlineNode[] : [];
      expect(inlines.length).assertEqual(2);
      expect(inlines[0].spoiler).assertTrue();
      expect(inlines[1].type).assertEqual(RichInlineType.IMAGE);
      expect(inlines[1].spoiler).assertTrue();
    });

    it('keepsPlainSpansUnmarkedAfterSpoilerCloses', 0, () => {
      const html: string = '<p><span class="spoiler">A</span><span class="chcxy">B</span>C</p>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      const inlines: RichInlineNode[] = blocks[0].inlines ? blocks[0].inlines as RichInlineNode[] : [];
      expect(inlines.length).assertEqual(2);
      expect(inlines[0].text).assertEqual('A');
      expect(inlines[0].spoiler).assertTrue();
      // spoiler 闭合后普通 span 与裸文本合并为无标记文本。
      expect(inlines[1].text).assertEqual('BC');
      expect(!!inlines[1].spoiler).assertFalse();
    });

    it('marksUnsupportedDiscourseBlocksAsTodo', 0, () => {
      const html: string = '<table><tr><td>A</td></tr></table>';

      const blocks: RichBlock[] = CookedHtmlParser.parse(html);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual(RichBlockType.UNSUPPORTED);
      expect(blocks[0].unsupportedKind).assertEqual('表格');
      expect(blocks[0].text).assertEqual('A');
    });
  });
}
