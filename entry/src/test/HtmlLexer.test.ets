import { describe, it, expect } from '@ohos/hypium';
import {
  findClosingTag,
  findOpenTag,
  findTagEnd,
  getTagName,
  isBlockTag,
  isClosingTag,
  isHeadingTag,
  isSelfClosingTag,
  shouldReadChildrenAsPlainText
} from '../main/ets/services/content/html/HtmlLexer';
import {
  bestSrcFromTag,
  extractAttr,
  hasClass,
  hasClassContaining,
  parsePositiveNumber
} from '../main/ets/services/content/html/HtmlAttrs';

// 这两个模块是从 CookedHtmlParser 抽出的最底层纯函数,零依赖故可直接断言。
// 抽取前它们是 private static,只能经 parse() 整链间接覆盖,边界情况测不到。
export default function htmlLexerTest() {
  describe('htmlLexerTest', () => {

    // ---------- findOpenTag ----------

    it('findsOpenTagAtExactPosition', 0, () => {
      expect(findOpenTag('<p>hi</p>', 'p', 0)).assertEqual(0);
      expect(findOpenTag('text <img src="a">', 'img', 0)).assertEqual(5);
    });

    // 前缀撞车是这个函数存在的全部理由:找 <p 不能命中 <pre,找 <a 不能命中 <aside。
    it('doesNotMatchTagNamePrefixOfLongerTag', 0, () => {
      expect(findOpenTag('<pre>code</pre>', 'p', 0)).assertEqual(-1);
      expect(findOpenTag('<aside>x</aside>', 'a', 0)).assertEqual(-1);
    });

    it('matchesTagFollowedByAttributeOrSelfClose', 0, () => {
      expect(findOpenTag('<p class="x">hi</p>', 'p', 0)).assertEqual(0);
      expect(findOpenTag('<br/>', 'br', 0)).assertEqual(0);
    });

    it('isCaseInsensitiveAndRespectsFromIndex', 0, () => {
      expect(findOpenTag('<P>a</P><p>b</p>', 'p', 0)).assertEqual(0);
      expect(findOpenTag('<p>a</p><p>b</p>', 'p', 1)).assertEqual(8);
    });

    it('returnsMinusOneWhenTagAbsent', 0, () => {
      expect(findOpenTag('<div>x</div>', 'span', 0)).assertEqual(-1);
    });

    // ---------- findTagEnd ----------

    it('findsTagEndAtClosingAngleBracket', 0, () => {
      expect(findTagEnd('<p>hi</p>', 0)).assertEqual(2);
    });

    // 属性值里的 '>' 不是标签结束——这是引号状态机存在的理由。
    it('ignoresAngleBracketInsideQuotedAttribute', 0, () => {
      const html: string = '<img alt="a > b" src="x.png">';
      expect(findTagEnd(html, 0)).assertEqual(html.length - 1);
    });

    it('handlesSingleQuotedAttribute', 0, () => {
      const html: string = "<img alt='a > b'>";
      expect(findTagEnd(html, 0)).assertEqual(html.length - 1);
    });

    it('returnsMinusOneOnUnterminatedTag', 0, () => {
      expect(findTagEnd('<p class="x', 0)).assertEqual(-1);
    });

    // ---------- findClosingTag ----------

    it('findsMatchingCloseForFlatTag', 0, () => {
      // '<p>hi</p>' 的 </p> 在下标 5
      expect(findClosingTag('<p>hi</p>', 3, 'p')).assertEqual(5);
    });

    // 嵌套配对:内层 </div> 不能被当成外层的收尾。
    it('matchesNestedTagsByDepth', 0, () => {
      const html: string = '<div><div>inner</div>outer</div>';
      // 从外层开标签之后起算,应配到最后那个 </div>(下标 26)
      expect(findClosingTag(html, 5, 'div')).assertEqual(26);
    });

    // 自闭合同名标签不该增加深度,否则配对整体错位一层。
    it('doesNotCountSelfClosingTagAsNestingLevel', 0, () => {
      const html: string = '<div><br/>x</div>';
      expect(findClosingTag(html, 5, 'div')).assertEqual(11);
    });

    it('returnsMinusOneWhenCloseMissing', 0, () => {
      expect(findClosingTag('<div>no close', 5, 'div')).assertEqual(-1);
    });

    // ---------- 标签名判定 ----------

    it('extractsLowercasedTagName', 0, () => {
      expect(getTagName('<IMG src="x">')).assertEqual('img');
      expect(getTagName('</Div>')).assertEqual('div');
      expect(getTagName('<h2 class="a">')).assertEqual('h2');
    });

    it('returnsEmptyTagNameForMalformedInput', 0, () => {
      expect(getTagName('not a tag')).assertEqual('');
      expect(getTagName('<>')).assertEqual('');
    });

    it('detectsClosingTag', 0, () => {
      expect(isClosingTag('</p>')).assertTrue();
      expect(isClosingTag('<p>')).assertFalse();
    });

    it('detectsSelfClosingBySyntaxAndByVoidElement', 0, () => {
      expect(isSelfClosingTag('<br/>')).assertTrue();
      expect(isSelfClosingTag('<div />')).assertTrue();
      expect(isSelfClosingTag('<img src="x">')).assertTrue();
      expect(isSelfClosingTag('<hr>')).assertTrue();
      expect(isSelfClosingTag('<div>')).assertFalse();
    });

    it('detectsHeadingTags', 0, () => {
      expect(isHeadingTag('h1')).assertTrue();
      expect(isHeadingTag('h6')).assertTrue();
      expect(isHeadingTag('h7')).assertFalse();
      expect(isHeadingTag('p')).assertFalse();
    });

    it('classifiesBlockLevelTags', 0, () => {
      expect(isBlockTag('p')).assertTrue();
      expect(isBlockTag('table')).assertTrue();
      expect(isBlockTag('details')).assertTrue();
      expect(isBlockTag('h3')).assertTrue();
      expect(isBlockTag('span')).assertFalse();
      expect(isBlockTag('a')).assertFalse();
      expect(isBlockTag('strong')).assertFalse();
    });

    it('marksScriptAndStyleAsPlainTextContainers', 0, () => {
      expect(shouldReadChildrenAsPlainText('script')).assertTrue();
      expect(shouldReadChildrenAsPlainText('style')).assertTrue();
      expect(shouldReadChildrenAsPlainText('div')).assertFalse();
    });

    // ---------- 属性读取 ----------

    it('extractsAttributeInAllThreeQuotingStyles', 0, () => {
      expect(extractAttr('<img src="a.png">', 'src')).assertEqual('a.png');
      expect(extractAttr("<img src='b.png'>", 'src')).assertEqual('b.png');
      expect(extractAttr('<img src=c.png>', 'src')).assertEqual('c.png');
    });

    it('extractsAttributeCaseInsensitivelyAndReturnsEmptyWhenAbsent', 0, () => {
      expect(extractAttr('<img SRC="a.png">', 'src')).assertEqual('a.png');
      expect(extractAttr('<img src="a.png">', 'alt')).assertEqual('');
    });

    it('matchesClassExactlyButNotAsSubstring', 0, () => {
      expect(hasClass('<div class="poll other">', 'poll')).assertTrue();
      expect(hasClass('<div class="poll-outer">', 'poll')).assertFalse();
      expect(hasClass('<div class="POLL">', 'poll')).assertTrue();
    });

    it('matchesClassBySubstringForSuffixedDiscourseClasses', 0, () => {
      expect(hasClassContaining('<div class="poll-outer">', 'poll')).assertTrue();
      expect(hasClassContaining('<div class="lightbox-wrapper">', 'lightbox')).assertTrue();
      expect(hasClassContaining('<div class="quote">', 'poll')).assertFalse();
    });

    // ---------- srcset 选优 ----------

    it('fallsBackToSrcWhenSrcsetAbsent', 0, () => {
      expect(bestSrcFromTag('<img src="a.png">')).assertEqual('a.png');
    });

    it('picksHighestDensityCandidateFromSrcset', 0, () => {
      const tag: string = '<img src="a.png" srcset="a.png, b.png 1.5x, c.png 2x">';
      expect(bestSrcFromTag(tag)).assertEqual('c.png');
    });

    it('treatsDescriptorlessCandidateAsOneX', 0, () => {
      const tag: string = '<img src="a.png" srcset="low.png 0.5x, plain.png">';
      expect(bestSrcFromTag(tag)).assertEqual('plain.png');
    });

    // ---------- 正整数解析 ----------

    it('parsesPositiveNumberAndRejectsNonPositive', 0, () => {
      expect(parsePositiveNumber('640')).assertEqual(640);
      expect(parsePositiveNumber('0')).assertEqual(0);
      expect(parsePositiveNumber('-5')).assertEqual(0);
      expect(parsePositiveNumber('abc')).assertEqual(0);
      expect(parsePositiveNumber('')).assertEqual(0);
    });
  });
}
