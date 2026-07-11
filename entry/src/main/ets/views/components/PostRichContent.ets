import { Log } from '../../services/logging/Log';
import {
  CookedHtmlParser,
  RichBlock,
  RichBlockType,
  RichInlineNode,
  RichInlineType,
  RichListItem
} from '../../services/content/CookedHtmlParser';
import { ViewerImage } from './ImageViewer';
import { AudioPlayer } from './AudioPlayer';
import { VideoPlayer } from './VideoPlayer';
import { FaIconView, getFaIcon, FaIconDefinition } from './FaIcon';
import { Poll, PollVoteResult } from '../../models/TopicDetail';
import { PollView } from './PollView';
import { UserAvatar } from './UserAvatar';
import { TopicCategoryBadge } from './TopicCategoryBadge';
import { User } from '../../models/User';
import { TopicCategory } from '../../models/Topic';
import { pasteboard } from '@kit.BasicServicesKit';
import { MathRenderService, MathImage } from '../../services/content/MathRenderService';
import { APP_IS_DARK_STORAGE_KEY } from '../../common/theme/ThemeManager';

const LOG_TAG: string = '[ArkDO][PostRichContent]';
// 块级图片自带尺寸小于该阈值（如 emoji 20×20、小图标）时按真实尺寸显示，
// 不撑满栏宽，避免小表情被 .width('100%') 拉成大方块。
const SMALL_IMAGE_MAX: number = 48;
// 剧透打码字符(块级与行内共用)。想换观感改这一行即可,如 ░(浅)/▒(中)/▓(深)/█(实心)。
const SPOILER_REDACT_CHAR: string = '▒';
// 公式位图染色矩阵(4×5):黑色字形按 alpha 覆盖度染成正文色 #374151(55,65,81)。
// 输入 rgb=0,只用 alpha 通道推出目标色,alpha 原样保留。深色主题改这三个分量即可。
const MATH_TINT_MATRIX: number[] = [
  0, 0, 0, 0.216, 0,
  0, 0, 0, 0.255, 0,
  0, 0, 0, 0.318, 0,
  0, 0, 0, 1, 0
];

// 深色主题版:染成正文色 #E7E9EE(231,233,238)/255=(0.906,0.914,0.933),否则公式深灰贴深底看不见。
const MATH_TINT_MATRIX_DARK: number[] = [
  0, 0, 0, 0.906, 0,
  0, 0, 0, 0.914, 0,
  0, 0, 0, 0.933, 0,
  0, 0, 0, 1, 0
];

// 收集待渲染公式用的轻量结构。
interface MathNode {
  latex: string;
  display: boolean;
}

@Component
export struct PostRichContent {
  cookedHtml: string = '';
  fallbackText: string = '';
  // 图片浏览器提到页面级渲染（bindContentCover 内部内容不会随状态刷新），
  // 这里只负责收集本帖图片并把「打开」请求回调给上层页面。
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  // 点击正文链接 / onebox 卡片时上抛给页面,由页面经 LinkRouter 判断跳原生详情或通用 WebView。
  onOpenLink: (url: string) => void = () => {};
  // 音视频播放:把媒体 URL 交给页面(经 bridge 下载委托过 CF)下到沙箱,返回本地路径。
  onResolveMedia: (url: string) => Promise<string> = () => Promise.reject(new Error('媒体下载未接入'));
  // 该 post 的投票列表(动态票数/已投项);cooked 里的 POLL 块按 name 关联到这里的 Poll 对象。
  polls: Poll[] = [];
  // 投票/撤销回调上抛给页面做乐观闭环。返回服务端校正结果;null=失败(供 PollView 回滚本地态)。
  onVote: (poll: Poll, optionIds: string[]) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  onRemoveVote: (poll: Poll) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  // @State 副本(持有与 polls 相同的 @Observed 实例)。PollView 的 @ObjectLink 必须以「状态变量的数组项」
  // 作为数据源,才能在投票/撤销就地改 Poll 字段后重渲染;若直接源自普通输入属性 polls,deep 变更不会传播。
  @State private renderablePolls: Poll[] = [];
  // 当前是否深色渲染(ThemeManager 维护):公式位图 colorFilter 矩阵按它切换,资源色不受影响。
  @StorageProp(APP_IS_DARK_STORAGE_KEY) private appIsDark: boolean = false;
  @State private expandedDisclosures: string[] = [];
  // 已揭示的剧透块/行内剧透段。key 是块路径(嵌套时形如 "2-q0-s1"),块级与行内共用。
  @State private revealedSpoilers: string[] = [];
  // 被用户点过(即"从默认折叠态翻转")的 callout 路径。展开态 = defaultExpanded XOR (path ∈ 此表),
  // 这样无需在 aboutToAppear 预知动态 path 即可支持每个 callout 各自的默认展开/折叠。
  @State private toggledCallouts: string[] = [];
  // 已渲染好的公式位图,key = mathLocalKey(latex, display)。异步出图后整体重赋触发重渲染;
  // 未就绪的公式先以裸 LaTeX 占位,出图后原地替换。
  @State private mathImages: Map<string, MathImage> = new Map();
  // 已发起渲染的公式 key,避免重复请求。
  private mathRequested: Set<string> = new Set();
  // 本帖是否已 retain 公式引擎(有公式才 retain,离开时 release)。
  private mathRetained: boolean = false;

  aboutToAppear(): void {
    this.renderablePolls = this.polls;
    this.prepareMath();
  }

  aboutToDisappear(): void {
    if (this.mathRetained) {
      this.mathRetained = false;
      MathRenderService.getInstance().release();
    }
  }

  // 扫描全部块收集数学公式;有则 retain 引擎并逐条请求出图。无公式则完全不碰引擎(零成本)。
  private prepareMath(): void {
    const nodes: MathNode[] = [];
    this.collectMath(this.getRenderableBlocks(), nodes);
    if (nodes.length === 0) {
      return;
    }
    const service: MathRenderService = MathRenderService.getInstance();
    service.retain();
    this.mathRetained = true;
    for (let i: number = 0; i < nodes.length; i++) {
      this.requestMath(nodes[i].latex, nodes[i].display);
    }
  }

  private requestMath(latex: string, display: boolean): void {
    const key: string = this.mathLocalKey(latex, display);
    if (this.mathRequested.has(key)) {
      return;
    }
    this.mathRequested.add(key);
    MathRenderService.getInstance().render(latex, display)
      .then((img: MathImage) => {
        const next: Map<string, MathImage> = new Map(this.mathImages);
        next.set(key, img);
        this.mathImages = next;
      })
      .catch(() => {
        // 失败保持占位(裸 LaTeX),不阻断其余公式。
      });
  }

  private mathLocalKey(latex: string, display: boolean): string {
    return `${display ? 'd' : 'i'}|${latex}`;
  }

  // 取已就绪的公式位图。调用方须先用 mathImages.has(...) 守卫,故此处必为已存在项。
  private mathImageOf(latex: string, display: boolean): MathImage {
    return this.mathImages.get(this.mathLocalKey(latex, display)) as MathImage;
  }

  // 行内 ForEach 的 key。对 MATH token 追加就绪标记:位图到位后 key 变化,强制 ForEach 重建该项、
  // 从裸 LaTeX 占位切到 ImageSpan(否则 key 不变,异步出图不会触发重渲染)。
  private inlineKey(token: RichInlineNode, index: number): string {
    const ready: string = token.type === RichInlineType.MATH && this.mathImages.has(this.mathLocalKey(token.text, false)) ? 'r' : 'p';
    return `${index}-${token.type}-${token.text}-${ready}`;
  }

  // 块级 ForEach 的 key。同理:MATH 块位图到位后翻转就绪标记,强制重建以切到 Image。
  private blockKey(block: RichBlock, index: number): string {
    const ready: string = block.type === RichBlockType.MATH && !!block.text && this.mathImages.has(this.mathLocalKey(block.text, true)) ? 'r' : 'p';
    return `${index}-${block.type}-${ready}`;
  }

  // 递归收集 inlines / items / titleInlines / 子块 里的行内公式,以及 MATH 块本身。
  private collectMath(blocks: RichBlock[], out: MathNode[]): void {
    for (let i: number = 0; i < blocks.length; i++) {
      const block: RichBlock = blocks[i];
      if (block.type === RichBlockType.MATH && block.text && block.text.length > 0) {
        out.push({ latex: block.text, display: true });
      }
      this.collectInlineMath(block.inlines, out);
      this.collectInlineMath(block.titleInlines, out);
      if (block.items) {
        for (let j: number = 0; j < block.items.length; j++) {
          this.collectInlineMath(block.items[j].inlines, out);
          const itemBlocks: RichBlock[] | undefined = block.items[j].blocks;
          if (itemBlocks && itemBlocks.length > 0) {
            this.collectMath(itemBlocks, out);
          }
        }
      }
      if (block.blocks && block.blocks.length > 0) {
        this.collectMath(block.blocks, out);
      }
    }
  }

  private collectInlineMath(inlines: RichInlineNode[] | undefined, out: MathNode[]): void {
    if (!inlines) {
      return;
    }
    for (let i: number = 0; i < inlines.length; i++) {
      const token: RichInlineNode = inlines[i];
      if (token.type === RichInlineType.MATH && token.text.length > 0) {
        out.push({ latex: token.text, display: false });
      }
    }
  }

  build() {
    Column() {
      ForEach(this.getRenderableBlocks(), (block: RichBlock, index: number) => {
        this.BlockView(block, index, `${index}`)
      }, (block: RichBlock, index: number) => this.blockKey(block, index))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private BlockView(block: RichBlock, index: number, path: string) {
    if (block.type === RichBlockType.PARAGRAPH) {
      this.InlineTextBlock(this.safeInlines(block), index > 0 ? 10 : 0, path)
    } else if (block.type === RichBlockType.HEADING) {
      this.HeadingBlock(block, index > 0 ? 14 : 0, path)
    } else if (block.type === RichBlockType.QUOTE) {
      this.QuoteBlock(block, index > 0 ? 12 : 0, path)
    } else if (block.type === RichBlockType.TOPIC_QUOTE) {
      this.TopicQuoteBlock(block, index > 0 ? 12 : 0, path)
    } else if (block.type === RichBlockType.CALLOUT) {
      this.CalloutBlock(block, index > 0 ? 12 : 0, path)
    } else if (block.type === RichBlockType.CODE) {
      this.CodeBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.IMAGE) {
      this.ImageBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.LIST) {
      this.ListBlock(block, index > 0 ? 10 : 0, path)
    } else if (block.type === RichBlockType.DISCLOSURE) {
      this.DisclosureBlock(block, index, index > 0 ? 12 : 0, path)
    } else if (block.type === RichBlockType.SPOILER) {
      this.SpoilerBlock(block, index > 0 ? 12 : 0, path)
    } else if (block.type === RichBlockType.DIVIDER) {
      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))
        .margin({ top: index > 0 ? 14 : 4, bottom: 4 })
    } else if (block.type === RichBlockType.POLL) {
      this.PollBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.ONEBOX) {
      this.OneboxBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.AUDIO) {
      this.AudioBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.VIDEO) {
      this.VideoBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.MATH) {
      this.MathBlock(block, index > 0 ? 12 : 0)
    } else {
      this.UnsupportedBlock(block, index > 0 ? 10 : 0)
    }
  }

  @Builder
  private PollBlock(block: RichBlock, marginTop: number) {
    // 直接 ForEach @State 数组,把匹配的 Poll 实例作为循环变量传给 PollView 的 @ObjectLink
    // (数据源须是「状态变量的数组项」,投票/撤销就地改字段后才会重渲染)。名字匹配的才渲染。
    Column() {
      ForEach(this.renderablePolls, (poll: Poll) => {
        if (this.pollMatchesBlock(poll, block.pollName)) {
          Column() {
            PollView({
              poll: poll,
              onVote: this.onVote,
              onRemoveVote: this.onRemoveVote
            })
          }
          .width('100%')
        }
      }, (poll: Poll) => poll.name)
    }
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private InlineTextBlock(inlines: RichInlineNode[], marginTop: number, path: string) {
    Text() {
      ForEach(inlines, (token: RichInlineNode, index: number) => {
        this.InlineToken(token, path)
      }, (token: RichInlineNode, index: number) => this.inlineKey(token, index))
    }
    .fontSize(15)
    .lineHeight(22)
    .fontColor($r('app.color.text_secondary'))
    .copyOption(CopyOptions.LocalDevice)
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private InlineToken(token: RichInlineNode, path: string) {
    if (token.spoiler && !this.isSpoilerRevealed(path)) {
      // 行内剧透未揭示:逐字符替换成 ░ 打码,点击揭示同段全部剧透。
      // 复制到的也只是 ░,不会漏真实文字。
      if (token.type === RichInlineType.LINE_BREAK) {
        Span('\n')
      } else if (token.type === RichInlineType.IMAGE) {
        // 行内 emoji 用一个打码字符占位,隐藏时不加载图片。
        Span(SPOILER_REDACT_CHAR)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.toggleSpoiler(path);
          })
      } else {
        Span(this.redactChars(token.text))
          .fontSize(token.type === RichInlineType.CODE || token.code ? 14 : 15)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.toggleSpoiler(path);
          })
      }
    } else if (token.type === RichInlineType.MATH) {
      // 行内公式:出图后以 ImageSpan 基线内联(周围文字仍是原生 Text,字体字号与全帖一致);
      // 未就绪时用等宽裸 LaTeX 占位,出图后原地替换。PNG 位图,colorFilter 染成正文色。
      if (this.mathImages.has(this.mathLocalKey(token.text, false))) {
        ImageSpan(this.mathImageOf(token.text, false).pixelMap)
          .width(this.mathImageOf(token.text, false).cssWidth)
          .height(this.mathImageOf(token.text, false).cssHeight)
          .margin({ left: 1, right: 1 })
          .verticalAlign(ImageSpanAlignment.BASELINE)
          .colorFilter(this.appIsDark ? MATH_TINT_MATRIX_DARK : MATH_TINT_MATRIX)
      } else {
        Span(token.text)
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor($r('app.color.text_secondary'))
      }
    } else if (token.type === RichInlineType.IMAGE && token.src && token.src.length > 0) {
      ImageSpan(token.src)
        .width(18)
        .height(18)
        .margin({ left: 1, right: 1 })
        .verticalAlign(ImageSpanAlignment.CENTER)
        .onClick(() => {
          this.openLink(token.href ? token.href : token.src as string);
        })
    } else if (token.type === RichInlineType.LINE_BREAK) {
      Span('\n')
    } else if (token.type === RichInlineType.LINK && token.href && token.href.length > 0) {
      if (token.attachment) {
        // 附件下载链接:前置下载图标(与官方一致),图标与文字同为一个可点区域。
        // 用已填充链接蓝的 SVG 变体——ImageSpan 无 fillColor,且 colorFilter 对矢量 SVG 不生效。
        ImageSpan($rawfile('fa_icons/download_blue.svg'))
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .verticalAlign(ImageSpanAlignment.CENTER)
          .margin({ right: 4 })
          .onClick(() => {
            this.openLink(token.href as string);
          })
      }
      Span(token.text)
        .fontSize(15)
        .fontColor($r('app.color.brand'))
        .fontWeight(token.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(token.italic ? FontStyle.Italic : FontStyle.Normal)
        .onClick(() => {
          this.openLink(token.href as string);
        })
    } else if (token.type === RichInlineType.CODE || token.code) {
      if (token.spoiler) {
        Span(token.text)
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor('#B45309')
          .backgroundColor($r('app.color.warn_soft_bg'))
          .onClick(() => {
            this.toggleSpoiler(path);
          })
      } else {
        Span(token.text)
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor('#B45309')
          .backgroundColor($r('app.color.warn_soft_bg'))
      }
    } else if (token.spoiler) {
      // 已揭示的行内剧透文字:再点一下恢复遮蔽(链接/emoji 保持各自的点击行为)。
      Span(token.text)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(token.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(token.italic ? FontStyle.Italic : FontStyle.Normal)
        .onClick(() => {
          this.toggleSpoiler(path);
        })
    } else {
      Span(token.text)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(token.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(token.italic ? FontStyle.Italic : FontStyle.Normal)
    }
  }

  @Builder
  private HeadingBlock(block: RichBlock, marginTop: number, path: string) {
    Text() {
      ForEach(this.safeInlines(block), (token: RichInlineNode, index: number) => {
        this.InlineToken(token, path)
      }, (token: RichInlineNode, index: number) => this.inlineKey(token, index))
    }
    .fontSize(this.getHeadingFontSize(block.level ? block.level : 2))
    .lineHeight(this.getHeadingLineHeight(block.level ? block.level : 2))
    .fontWeight(FontWeight.Bold)
    .fontColor($r('app.color.text_primary'))
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private QuoteBlock(block: RichBlock, marginTop: number, path: string) {
    Column() {
      Column() {
        ForEach(this.safeBlocks(block), (inner: RichBlock, index: number) => {
          this.BlockView(inner, index, `${path}-q${index}`)
        }, (inner: RichBlock, index: number) => this.blockKey(inner, index))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.fill_subtle'))
    .border({
      width: { left: 3 },
      color: $r('app.color.border')
    })
    // .borderRadius(8)
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  // 话题/帖子引用卡(<aside class="quote" data-topic>):头部(圆头像 + 标题 + 分类徽章 + 右箭头)+ 截断预览正文。
  // 点头部/箭头跳原帖详情(不就地展开);正文预览走 BlockView 同实例递归渲染(支持图片/嵌套),不新建 PostRichContent。
  @Builder
  private TopicQuoteBlock(block: RichBlock, marginTop: number, path: string) {
    Column() {
      // 头部:头像 + (标题 / 分类) + 右箭头。整块可点 → 跳原帖详情。
      Row() {
        UserAvatar({ user: this.quoteAvatarUser(block), avatarSize: 24 })
          .margin({ right: 8 })

        Column() {
          if (block.quoteTitle && block.quoteTitle.length > 0) {
            Text(block.quoteTitle)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#374151')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (block.quoteCategory) {
            Row() {
              TopicCategoryBadge({ category: block.quoteCategory as TopicCategory })
            }
            .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        FaIconView({ icon: this.faIconOf('chevron-right'), color: '#9CA3AF', iconSize: 16 })
          .margin({ left: 4, top: 2 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        if (block.href && block.href.length > 0) {
          this.openLink(block.href);
        }
      })

      // 截断预览正文:解析预览 cooked → BlockView 同实例递归渲染。
      Column() {
        ForEach(this.quotePreviewBlocks(block), (child: RichBlock, index: number) => {
          this.BlockView(child, index, `${path}-tq${index}`)
        }, (child: RichBlock, index: number) => this.blockKey(child, index))
      }
      .width('100%')
      .margin({ top: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor('#F8FAFC')
    .border({
      width: { left: 3 },
      color: '#CBD5E1'
    })
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  // 用直链头像 URL 构造最小 User,复用 UserAvatar 的 host webview 取图 + 圆形裁剪。
  private quoteAvatarUser(block: RichBlock): User {
    return {
      id: 0,
      username: block.quoteAuthor ? block.quoteAuthor : '',
      avatarTemplate: block.quoteAvatarUrl ? block.quoteAvatarUrl : ''
    };
  }

  // 解析引用预览 cooked 成块,交 BlockView 渲染。空预览返回空数组(只显示头部)。
  private quotePreviewBlocks(block: RichBlock): RichBlock[] {
    return CookedHtmlParser.parse(block.text ? block.text : '');
  }

  private faIconOf(id: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(id);
    return def ? def : { id, rawfilePath: `fa_icons/${id}.svg` };
  }

  // callout 标题专用行内渲染:整段染成主色(继承外层 Text 的加粗),链接仍可点(主色+下划线),
  // 与正文 InlineToken 区分——后者把普通文字硬编码成 #374151,会盖掉标题主色。
  @Builder
  private CalloutTitleToken(token: RichInlineNode, path: string, accent: string) {
    if (token.type === RichInlineType.IMAGE && token.src && token.src.length > 0) {
      ImageSpan(token.src)
        .width(18)
        .height(18)
        .margin({ left: 1, right: 1 })
        .verticalAlign(ImageSpanAlignment.CENTER)
        .onClick(() => {
          this.openLink(token.href ? token.href : token.src as string);
        })
    } else if (token.type === RichInlineType.LINE_BREAK) {
      Span(' ')
    } else if (token.type === RichInlineType.LINK && token.href && token.href.length > 0) {
      Span(token.text)
        .fontColor(accent)
        .decoration({ type: TextDecorationType.Underline, color: accent })
        .fontStyle(token.italic ? FontStyle.Italic : FontStyle.Normal)
        .onClick(() => {
          this.openLink(token.href as string);
        })
    } else if (token.type === RichInlineType.CODE || token.code) {
      Span(token.text)
        .fontFamily('monospace')
        .fontColor(accent)
    } else {
      Span(token.text)
        .fontColor(accent)
        .fontStyle(token.italic ? FontStyle.Italic : FontStyle.Normal)
    }
  }

  // Obsidian/Discourse callout 提示框:主色淡底(10%)、圆角、无边框;标题行为「图标 + 类型色加粗标题
  // (+ 可折叠时右侧箭头)」,可折叠时点标题行展开/收起(动画同剧透)。默认观感对齐 discourse-quote-callouts。
  @Builder
  private CalloutBlock(block: RichBlock, marginTop: number, path: string) {
    Column() {
      Row() {
        if (this.hasCalloutIcon(block)) {
          FaIconView({
            icon: this.calloutIconDef(block),
            color: this.calloutColor(block),
            iconSize: 15
          })
        }

        Text() {
          ForEach(this.calloutTitle(block), (token: RichInlineNode, tokenIndex: number) => {
            this.CalloutTitleToken(token, `${path}-ct`, this.calloutColor(block))
          }, (token: RichInlineNode, tokenIndex: number) => this.inlineKey(token, tokenIndex))
        }
        .fontSize(15)
        .lineHeight(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.calloutColor(block))
        .layoutWeight(1)
        .margin({ left: this.hasCalloutIcon(block) ? 8 : 0 })

        if (block.collapsible) {
          Text('▼')
            .fontSize(13)
            .fontColor(this.calloutColor(block))
            .margin({ left: 6 })
            .rotate({ angle: this.isCalloutExpanded(path, block.defaultExpanded === true) ? 0 : -90 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (block.collapsible) {
          this.toggleCallout(path);
        }
      })

      if (this.safeBlocks(block).length > 0 &&
        (!block.collapsible || this.isCalloutExpanded(path, block.defaultExpanded === true))) {
        Column() {
          ForEach(this.safeBlocks(block), (inner: RichBlock, childIndex: number) => {
            this.BlockView(inner, childIndex, `${path}-c${childIndex}`)
          }, (inner: RichBlock, childIndex: number) => this.blockKey(inner, childIndex))
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.calloutBackground(block))
    .borderRadius(8)
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CodeBlock(block: RichBlock, marginTop: number) {
    Column() {
      // 头部行：左侧语言标签(可选) + 右上角复制按钮(始终显示)
      Row() {
        if (block.language && block.language.length > 0) {
          Text(block.language)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .fontFamily('monospace')
            .layoutWeight(1)
        } else {
          Blank()
        }

        Row() {
          Image($rawfile('fa_icons/copy.svg'))
            .width(13)
            .height(13)
            .objectFit(ImageFit.Contain)
            .renderMode(ImageRenderMode.Template)
            .fillColor($r('app.color.text_secondary'))
            .draggable(false)
          Text('复制')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(6)
        .onClick(() => {
          this.copyCode(block.text ? block.text : '');
        })
      }
      .width('100%')
      .margin({ bottom: 6 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Text(block.text ? block.text : '')
          .fontSize(13)
          .lineHeight(19)
          .fontFamily('monospace')
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Start)
          .constraintSize({ minWidth: '100%' })
          .copyOption(CopyOptions.LocalDevice)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .align(Alignment.Start)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.fill_subtle'))
    .borderRadius(8)
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  private copyCode(text: string): void {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.getUIContext().getPromptAction().showToast({ message: '已复制', duration: 1500 });
      }).catch((err: Object) => {
        Log.e(`${LOG_TAG} copy code failed: ${JSON.stringify(err)}`);
      });
    } catch (err) {
      Log.e(`${LOG_TAG} copy code failed: ${JSON.stringify(err)}`);
    }
  }

  @Builder
  private ImageBlock(block: RichBlock, marginTop: number) {
    Column() {
      if (this.isSmallImage(block)) {
        // 小图（如 emoji、图标）：按 cooked 自带的真实尺寸显示，左对齐、不撑满、不显示 alt
        Image(block.src ? block.src : '')
          .width(block.width ? block.width : 20)
          .height(block.height ? block.height : 20)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .onClick(() => {
            this.openImageLink(block);
          })
      } else if (this.hasImageSize(block)) {
        Image(block.src ? block.src : '')
          .width('100%')
          .aspectRatio(this.getImageAspectRatio(block))
          .constraintSize({ maxHeight: 520 })
          .objectFit(ImageFit.Contain)
          .backgroundColor($r('app.color.fill_subtle'))
          .onClick(() => {
            this.openImageLink(block);
          })
      } else {
        Image(block.src ? block.src : '')
          .width('100%')
          .height(260)
          .objectFit(ImageFit.Contain)
          .backgroundColor($r('app.color.fill_subtle'))
          .onClick(() => {
            this.openImageLink(block);
          })
      }

    }
    .width('100%')
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ListBlock(block: RichBlock, marginTop: number, path: string) {
    Column() {
      ForEach(this.safeItems(block), (item: RichListItem, index: number) => {
        Row() {
          Text(block.ordered ? `${index + 1}.` : '•')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .width(24)

          Column() {
            if (item.blocks && item.blocks.length > 0) {
              // 含块级图的列表项:文字段落 + 全宽图片按序渲染(复用统一的块渲染)。
              ForEach(item.blocks, (child: RichBlock, childIndex: number) => {
                this.BlockView(child, childIndex, `${path}-i${index}-b${childIndex}`)
              }, (child: RichBlock, childIndex: number) => this.blockKey(child, childIndex))
            } else {
              this.InlineTextBlock(item.inlines, 0, `${path}-i${index}`)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: index > 0 ? 6 : 0 })
      }, (item: RichListItem, index: number) => `${index}`)
    }
    .width('100%')
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  // 链接预览卡片(onebox)。样式对齐官方 .onebox:白底 + 双层描边(内 1px #D3D3D3、外 4px #F2F2F2)、
  // 2px 圆角、16px 内边距。外层留 4px 内边距给 outline 让位,避免被父容器裁掉。
  @Builder
  private OneboxBlock(block: RichBlock, marginTop: number) {
    Column() {
      Column() {
        if (this.hasOneboxHeader(block)) {
          Row() {
            if (block.faviconUrl && block.faviconUrl.length > 0) {
              Image(block.faviconUrl)
                .width(16)
                .height(16)
                .objectFit(ImageFit.Contain)
                .borderRadius(3)
                .margin({ right: 8 })
                .draggable(false)
            }
            Text(block.domain ? block.domain : '')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }

        if (block.title && block.title.length > 0) {
          Text(block.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: this.hasOneboxHeader(block) ? 10 : 0 })
        }

        if (block.description && block.description.length > 0) {
          Text(block.description)
            .fontSize(15)
            .lineHeight(22)
            .fontColor($r('app.color.text_primary'))
            .wordBreak(WordBreak.BREAK_ALL)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: (block.title && block.title.length > 0) || this.hasOneboxHeader(block) ? 8 : 0 })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface_card'))
      .borderRadius(2)
      .border({ width: 1, color: $r('app.color.border') })
      .outline({ width: 4, color: $r('app.color.page_bg_gray'), radius: 2 })
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.openLink(block.href ? block.href : '');
      })
    }
    .width('100%')
    .padding({ left: 4, right: 4, bottom: 4 })
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  private hasOneboxHeader(block: RichBlock): boolean {
    return (!!block.domain && block.domain.length > 0) || (!!block.faviconUrl && block.faviconUrl.length > 0);
  }

  @Builder
  private AudioBlock(block: RichBlock, marginTop: number) {
    Column() {
      AudioPlayer({ src: block.src ? block.src : '', onResolveMedia: this.onResolveMedia })
    }
    .width('100%')
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  // 视频:点击后经下载委托下到沙箱再用原生 Video 播本地文件(同音频,直连拿不到字节)。
  // 有自带宽高时按比例,缺失时退到 16:9。
  @Builder
  private VideoBlock(block: RichBlock, marginTop: number) {
    Column() {
      VideoPlayer({
        src: block.src ? block.src : '',
        videoAspectRatio: this.hasImageSize(block) ? this.getImageAspectRatio(block) : 1.78,
        onResolveMedia: this.onResolveMedia
      })
    }
    .width('100%')
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private MathBlock(block: RichBlock, marginTop: number) {
    // 块级公式:居中显示,超宽则横向滚动(不撑破栏宽)。未就绪先以裸 LaTeX 占位。
    Column() {
      if (block.text && this.mathImages.has(this.mathLocalKey(block.text, true))) {
        Scroll() {
          Image(this.mathImageOf(block.text, true).pixelMap)
            .width(this.mathImageOf(block.text, true).cssWidth)
            .height(this.mathImageOf(block.text, true).cssHeight)
            .objectFit(ImageFit.Contain)
            .colorFilter(this.appIsDark ? MATH_TINT_MATRIX_DARK : MATH_TINT_MATRIX)
            .draggable(false)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Center)
        .width('100%')
      } else {
        Text(block.text ? block.text : '')
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private UnsupportedBlock(block: RichBlock, marginTop: number) {
    Column() {
      Text(`待实现：${this.getUnsupportedLabel(block)}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#C2410C')
        .width('100%')

      if (block.text && block.text.length > 0 && block.text !== `${this.getUnsupportedLabel(block)}待实现`) {
        Text(block.text)
          .fontSize(14)
          .lineHeight(20)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor($r('app.color.warn_soft_bg'))
    .border({
      width: 1,
      color: $r('app.color.warn_soft_bg')
    })
    .borderRadius(8)
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DisclosureBlock(block: RichBlock, index: number, marginTop: number, path: string) {
    Column() {
      Row() {
        Text('▼')
          .fontSize(18)
          .fontColor($r('app.color.text_primary'))
          .width(28)
          .textAlign(TextAlign.Center)
          .rotate({ angle: this.isDisclosureExpanded(index) ? 0 : -90 })

        Text(this.getDisclosureTitle(block))
          .fontSize(16)
          .fontWeight(FontWeight.Regular)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(40)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toggleDisclosure(index);
      })

      if (this.isDisclosureExpanded(index)) {
        Column() {
          ForEach(this.safeBlocks(block), (inner: RichBlock, childIndex: number) => {
            this.BlockView(inner, childIndex, `${path}-d${childIndex}`)
          }, (inner: RichBlock, childIndex: number) => this.blockKey(inner, childIndex))
        }
        .width('100%')
        .padding({ left: 28, right: 0, bottom: 12 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.fill_subtle'))
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  // 块级剧透:涂黑(redaction)。未揭示时不渲染真实内容,渲染「涂黑版」——每段文字
  // 变成透明字 + 深色底的实心条(行数/宽度与真实文字一致,换行自动断条,即 ███ 观感),
  // 图片变成深灰占位块(不加载图片本身)。点整块揭示;揭示后右上角「隐藏」胶囊糊回去
  // (不能依赖点空白冒泡:正文 Text 开 copyOption、图片/代码块各有点击消费者)。
  @Builder
  private SpoilerBlock(block: RichBlock, marginTop: number, path: string) {
    if (this.isSpoilerRevealed(path)) {
      Stack() {
        Column() {
          ForEach(this.safeBlocks(block), (inner: RichBlock, childIndex: number) => {
            this.BlockView(inner, childIndex, `${path}-s${childIndex}`)
          }, (inner: RichBlock, childIndex: number) => this.blockKey(inner, childIndex))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row() {
          Image($rawfile('fa_icons/eye-slash.svg'))
            .width(12)
            .height(12)
            .objectFit(ImageFit.Contain)
            .renderMode(ImageRenderMode.Template)
            .fillColor('#FFFFFF')
            .draggable(false)
          Text('隐藏')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor('#8C111827')
        .position({ top: 0, right: 0 })
        .onClick(() => {
          this.toggleSpoiler(path);
        })
      }
      .width('100%')
      .margin({ top: marginTop })
      .alignContent(Alignment.TopStart)
    } else {
      Column() {
        ForEach(this.safeBlocks(block), (inner: RichBlock, childIndex: number) => {
          this.RedactedBlockView(inner, childIndex)
        }, (inner: RichBlock, childIndex: number) => this.blockKey(inner, childIndex))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: marginTop })
      .onClick(() => {
        this.toggleSpoiler(path);
      })
    }
  }

  // 打码占位。文字类块:逐字符替换为 ░(U+2591),行数/长短与真实内容一致但读不出
  // 内容,复制到的也只是 ░。图片:深灰块占位(隐藏时不创建 Image,不加载图片)。
  @Builder
  private RedactedBlockView(block: RichBlock, index: number) {
    if (block.type === RichBlockType.IMAGE) {
      Column()
        .width('60%')
        .aspectRatio(this.hasImageSize(block) ? this.getImageAspectRatio(block) : 1.6)
        .constraintSize({ maxHeight: 220 })
        .backgroundColor($r('app.color.text_secondary'))
        .borderRadius(4)
        .margin({ top: index > 0 ? 10 : 0 })
    } else if (block.blocks && block.blocks.length > 0) {
      // 引用/折叠等容器:拍平递归打码,不保留容器样式(样式本身也可能剧透)。
      ForEach(block.blocks, (inner: RichBlock, childIndex: number) => {
        this.RedactedBlockView(inner, index + childIndex)
      }, (inner: RichBlock, childIndex: number) => this.blockKey(inner, childIndex))
    } else {
      Text(this.redactChars(this.redactedBlockText(block)))
        .fontSize(15)
        .lineHeight(22)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: index > 0 ? 10 : 0 })
    }
  }

  // 逐字符打码:换行保留(行结构可见),其余字符一律替换成打码字符。
  private redactChars(text: string): string {
    let out: string = '';
    for (let i: number = 0; i < text.length; i++) {
      out = `${out}${text.charAt(i) === '\n' ? '\n' : SPOILER_REDACT_CHAR}`;
    }
    return out;
  }

  // 打码底稿:只用于撑出与真实内容一致的行数/长短,展示前必经 redactChars 替换。
  private redactedBlockText(block: RichBlock): string {
    if (block.type === RichBlockType.CODE && block.text && block.text.length > 0) {
      return block.text;
    }
    if (block.inlines && block.inlines.length > 0) {
      let text: string = '';
      for (let i: number = 0; i < block.inlines.length; i++) {
        text = `${text}${block.inlines[i].text}`;
      }
      if (text.trim().length > 0) {
        return text;
      }
    }
    if (block.items && block.items.length > 0) {
      const lines: string[] = [];
      for (let i: number = 0; i < block.items.length; i++) {
        let line: string = '';
        const inlines: RichInlineNode[] = block.items[i].inlines;
        for (let j: number = 0; j < inlines.length; j++) {
          line = `${line}${inlines[j].text}`;
        }
        lines.push(line);
      }
      return lines.join('\n');
    }
    if (block.text && block.text.length > 0) {
      return block.text;
    }
    return SPOILER_REDACT_CHAR.repeat(8);
  }

  private isSpoilerRevealed(path: string): boolean {
    return this.revealedSpoilers.indexOf(path) >= 0;
  }

  // 揭示/恢复遮蔽切换(与官方 web 一致,可反复点)。
  private toggleSpoiler(path: string): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      if (this.isSpoilerRevealed(path)) {
        this.revealedSpoilers = this.revealedSpoilers.filter((item: string) => item !== path);
      } else {
        this.revealedSpoilers = this.revealedSpoilers.concat([path]);
      }
    });
  }

  private calloutColor(block: RichBlock): string {
    return block.calloutColor && block.calloutColor.length > 0 ? block.calloutColor : '#027aff';
  }

  // 主色 @ 10% 透明度作淡底(#AARRGGBB,0x1A≈10%)。非 6 位十六进制则原样返回。
  private calloutBackground(block: RichBlock): string {
    const c: string = this.calloutColor(block);
    return c.length === 7 ? `#1A${c.substring(1)}` : c;
  }

  private calloutIconDef(block: RichBlock): FaIconDefinition {
    const found: FaIconDefinition | undefined =
      block.calloutIcon && block.calloutIcon.length > 0 ? getFaIcon(block.calloutIcon) : undefined;
    return found ? found : { id: '', rawfilePath: '' };
  }

  private hasCalloutIcon(block: RichBlock): boolean {
    return this.calloutIconDef(block).rawfilePath.length > 0;
  }

  // 标题:优先 titleInlines;为空则回退为类型名(首字母大写),与 Obsidian 无标题时一致。
  private calloutTitle(block: RichBlock): RichInlineNode[] {
    if (block.titleInlines && block.titleInlines.length > 0) {
      return block.titleInlines;
    }
    const kind: string = block.calloutKind && block.calloutKind.length > 0 ? block.calloutKind : 'note';
    return [{
      type: RichInlineType.TEXT,
      text: kind.charAt(0).toUpperCase() + kind.substring(1)
    }];
  }

  // 展开态 = defaultExpanded XOR (path 被翻转过)。toggledCallouts 记录用户翻转过的 path。
  private isCalloutExpanded(path: string, defaultExpanded: boolean): boolean {
    const flipped: boolean = this.toggledCallouts.indexOf(path) >= 0;
    return defaultExpanded !== flipped;
  }

  private toggleCallout(path: string): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      if (this.toggledCallouts.indexOf(path) >= 0) {
        this.toggledCallouts = this.toggledCallouts.filter((item: string) => item !== path);
      } else {
        this.toggledCallouts = this.toggledCallouts.concat([path]);
      }
    });
  }

  private getRenderableBlocks(): RichBlock[] {
    const parsed: RichBlock[] = CookedHtmlParser.parse(this.cookedHtml);
    if (parsed.length > 0) {
      return parsed;
    }

    if (this.fallbackText.length === 0) {
      return [{
        type: RichBlockType.PARAGRAPH,
        inlines: [{
          type: RichInlineType.TEXT,
          text: '暂无文本内容'
        }]
      }];
    }

    return [{
      type: RichBlockType.PARAGRAPH,
      inlines: [{
        type: RichInlineType.TEXT,
        text: this.fallbackText
      }]
    }];
  }

  private safeInlines(block: RichBlock): RichInlineNode[] {
    return block.inlines ? block.inlines : [];
  }

  private safeBlocks(block: RichBlock): RichBlock[] {
    return block.blocks ? block.blocks : [];
  }

  private safeItems(block: RichBlock): RichListItem[] {
    return block.items ? block.items : [];
  }

  // POLL 块只带 name,按 name 关联到 renderablePolls 里的动态 Poll。精确匹配优先;
  // 无精确匹配且仅一个投票时兜底给它(cooked 的 data-poll-name 与 API name 偶有差异)。
  private pollMatchesBlock(poll: Poll, name?: string): boolean {
    const target: string = name && name.length > 0 ? name : 'poll';
    if (poll.name === target) {
      return true;
    }
    let hasExact: boolean = false;
    for (let index: number = 0; index < this.renderablePolls.length; index++) {
      if (this.renderablePolls[index].name === target) {
        hasExact = true;
        break;
      }
    }
    return !hasExact && this.renderablePolls.length === 1;
  }

  private getUnsupportedLabel(block: RichBlock): string {
    if (block.unsupportedKind && block.unsupportedKind.length > 0) {
      return block.unsupportedKind;
    }
    return '暂未支持内容';
  }

  private getDisclosureTitle(block: RichBlock): string {
    if (block.title && block.title.length > 0) {
      return block.title;
    }
    return '详情';
  }

  private isDisclosureExpanded(index: number): boolean {
    return this.expandedDisclosures.indexOf(index.toString()) >= 0;
  }

  private toggleDisclosure(index: number): void {
    const key: string = index.toString();
    const next: string[] = [];
    let removed: boolean = false;
    for (let itemIndex: number = 0; itemIndex < this.expandedDisclosures.length; itemIndex++) {
      const item: string = this.expandedDisclosures[itemIndex];
      if (item === key) {
        removed = true;
        continue;
      }
      next.push(item);
    }
    if (!removed) {
      next.push(key);
    }
    this.expandedDisclosures = next;
  }

  private getHeadingFontSize(level: number): number {
    if (level <= 1) {
      return 22;
    }
    if (level === 2) {
      return 20;
    }
    return 17;
  }

  private getHeadingLineHeight(level: number): number {
    if (level <= 1) {
      return 28;
    }
    if (level === 2) {
      return 26;
    }
    return 23;
  }

  private hasImageSize(block: RichBlock): boolean {
    const width: number = block.width ? block.width : 0;
    const height: number = block.height ? block.height : 0;
    return width > 0 && height > 0;
  }

  // 图片自带尺寸很小（如 emoji 20×20、小图标）：按真实尺寸显示而非撑满栏宽
  private isSmallImage(block: RichBlock): boolean {
    const width: number = block.width ? block.width : 0;
    const height: number = block.height ? block.height : 0;
    return width > 0 && height > 0 && width <= SMALL_IMAGE_MAX && height <= SMALL_IMAGE_MAX;
  }

  private getImageAspectRatio(block: RichBlock): number {
    const width: number = block.width ? block.width : 1;
    const height: number = block.height ? block.height : 1;
    return width / height;
  }

  private openImageLink(block: RichBlock): void {
    const images: ViewerImage[] = this.collectImages();
    if (images.length === 0) {
      return;
    }
    const clickedUrl: string = this.primaryImageUrl(block);
    let index: number = 0;
    for (let i: number = 0; i < images.length; i++) {
      if (images[i].url === clickedUrl) {
        index = i;
        break;
      }
    }
    // 交给上层页面在页面级渲染图片浏览器
    this.onOpenImages(images, index);
  }

  // 收集当前 post 内所有块级图片（含嵌在引用/折叠块里的），按出现顺序，
  // 看图用高清原图 href；行内 emoji 不计入。未揭示的剧透块里的图片不收集,
  // 否则从其他图片左右滑动就能看到剧透图。路径前缀规则须与 BlockView 一致。
  private collectImages(): ViewerImage[] {
    const result: ViewerImage[] = [];
    this.collectImagesFrom(this.getRenderableBlocks(), result, '');
    return result;
  }

  private collectImagesFrom(blocks: RichBlock[], result: ViewerImage[], pathPrefix: string): void {
    for (let i: number = 0; i < blocks.length; i++) {
      const block: RichBlock = blocks[i];
      const path: string = `${pathPrefix}${i}`;
      if (block.type === RichBlockType.IMAGE) {
        const primary: string = this.primaryImageUrl(block);
        if (primary.length > 0) {
          // 兜底用优化图 src（与帖子内联同源、多已缓存），原图加载失败时回退
          const optimized: string = block.src && block.src !== primary ? block.src : '';
          result.push({ url: primary, fallbackUrl: optimized });
        }
      }
      // 列表项内的块级图(item.blocks)也要进浏览器,否则点开只有它自己、无法左右翻页。
      if (block.type === RichBlockType.LIST && block.items) {
        for (let j: number = 0; j < block.items.length; j++) {
          const itemBlocks: RichBlock[] | undefined = block.items[j].blocks;
          if (itemBlocks && itemBlocks.length > 0) {
            this.collectImagesFrom(itemBlocks, result, `${path}-i${j}-b`);
          }
        }
      }
      if (block.blocks && block.blocks.length > 0) {
        if (block.type === RichBlockType.SPOILER) {
          if (this.isSpoilerRevealed(path)) {
            this.collectImagesFrom(block.blocks, result, `${path}-s`);
          }
        } else if (block.type === RichBlockType.QUOTE) {
          this.collectImagesFrom(block.blocks, result, `${path}-q`);
        } else if (block.type === RichBlockType.DISCLOSURE) {
          this.collectImagesFrom(block.blocks, result, `${path}-d`);
        } else {
          this.collectImagesFrom(block.blocks, result, `${path}-x`);
        }
      }
    }
  }

  // 看图优先用高清原图 href（lightbox 全尺寸）；缺失时才用优化图 src
  private primaryImageUrl(block: RichBlock): string {
    if (block.href && block.href.length > 0) {
      return block.href;
    }
    if (block.src && block.src.length > 0) {
      return block.src;
    }
    return '';
  }

  private openLink(url: string): void {
    if (url.length === 0) {
      return;
    }
    Log.i(`${LOG_TAG} link clicked url=${this.safeLinkLabel(url)}`);
    this.onOpenLink(url);
  }

  private safeLinkLabel(url: string): string {
    if (url.startsWith('https://linux.do')) {
      return 'linuxdo';
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return 'external';
    }
    return 'other';
  }
}
