import {
  CookedHtmlParser,
  RichBlock,
  RichBlockType,
  RichInlineNode,
  RichInlineType,
  RichListItem
} from '../../services/content/CookedHtmlParser';
import { ViewerImage } from './ImageViewer';
import { Poll, PollVoteResult } from '../../models/TopicDetail';
import { PollView } from './PollView';
import { pasteboard } from '@kit.BasicServicesKit';

const LOG_TAG: string = '[ArkDO][PostRichContent]';
// 块级图片自带尺寸小于该阈值（如 emoji 20×20、小图标）时按真实尺寸显示，
// 不撑满栏宽，避免小表情被 .width('100%') 拉成大方块。
const SMALL_IMAGE_MAX: number = 48;

@Component
export struct PostRichContent {
  cookedHtml: string = '';
  fallbackText: string = '';
  // 图片浏览器提到页面级渲染（bindContentCover 内部内容不会随状态刷新），
  // 这里只负责收集本帖图片并把「打开」请求回调给上层页面。
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  // 该 post 的投票列表(动态票数/已投项);cooked 里的 POLL 块按 name 关联到这里的 Poll 对象。
  polls: Poll[] = [];
  // 投票/撤销回调上抛给页面做乐观闭环。返回服务端校正结果;null=失败(供 PollView 回滚本地态)。
  onVote: (poll: Poll, optionIds: string[]) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  onRemoveVote: (poll: Poll) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  // @State 副本(持有与 polls 相同的 @Observed 实例)。PollView 的 @ObjectLink 必须以「状态变量的数组项」
  // 作为数据源,才能在投票/撤销就地改 Poll 字段后重渲染;若直接源自普通输入属性 polls,deep 变更不会传播。
  @State private renderablePolls: Poll[] = [];
  @State private expandedDisclosures: string[] = [];

  aboutToAppear(): void {
    this.renderablePolls = this.polls;
  }

  build() {
    Column() {
      ForEach(this.getRenderableBlocks(), (block: RichBlock, index: number) => {
        this.BlockView(block, index)
      }, (block: RichBlock, index: number) => `${index}-${block.type}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private BlockView(block: RichBlock, index: number) {
    if (block.type === RichBlockType.PARAGRAPH) {
      this.InlineTextBlock(this.safeInlines(block), index > 0 ? 10 : 0)
    } else if (block.type === RichBlockType.HEADING) {
      this.HeadingBlock(block, index > 0 ? 14 : 0)
    } else if (block.type === RichBlockType.QUOTE) {
      this.QuoteBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.CODE) {
      this.CodeBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.IMAGE) {
      this.ImageBlock(block, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.LIST) {
      this.ListBlock(block, index > 0 ? 10 : 0)
    } else if (block.type === RichBlockType.DISCLOSURE) {
      this.DisclosureBlock(block, index, index > 0 ? 12 : 0)
    } else if (block.type === RichBlockType.DIVIDER) {
      Divider()
        .strokeWidth(1)
        .color('#E5E7EB')
        .margin({ top: index > 0 ? 14 : 4, bottom: 4 })
    } else if (block.type === RichBlockType.POLL) {
      this.PollBlock(block, index > 0 ? 12 : 0)
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
  private InlineTextBlock(inlines: RichInlineNode[], marginTop: number) {
    Text() {
      ForEach(inlines, (token: RichInlineNode, index: number) => {
        this.InlineToken(token)
      }, (token: RichInlineNode, index: number) => `${index}-${token.type}-${token.text}`)
    }
    .fontSize(15)
    .lineHeight(22)
    .fontColor('#374151')
    .copyOption(CopyOptions.LocalDevice)
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private InlineToken(token: RichInlineNode) {
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
      Span('\n')
    } else if (token.type === RichInlineType.LINK && token.href && token.href.length > 0) {
      Span(token.text)
        .fontSize(15)
        .fontColor('#2563EB')
        .fontWeight(token.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(token.italic ? FontStyle.Italic : FontStyle.Normal)
        .onClick(() => {
          this.openLink(token.href as string);
        })
    } else if (token.type === RichInlineType.CODE || token.code) {
      Span(token.text)
        .fontSize(14)
        .fontFamily('monospace')
        .fontColor('#B45309')
        .backgroundColor('#FEF3C7')
    } else {
      Span(token.text)
        .fontSize(15)
        .fontColor('#374151')
        .fontWeight(token.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(token.italic ? FontStyle.Italic : FontStyle.Normal)
    }
  }

  @Builder
  private HeadingBlock(block: RichBlock, marginTop: number) {
    Text() {
      ForEach(this.safeInlines(block), (token: RichInlineNode, index: number) => {
        this.InlineToken(token)
      }, (token: RichInlineNode, index: number) => `${index}-${token.type}-${token.text}`)
    }
    .fontSize(this.getHeadingFontSize(block.level ? block.level : 2))
    .lineHeight(this.getHeadingLineHeight(block.level ? block.level : 2))
    .fontWeight(FontWeight.Bold)
    .fontColor('#111827')
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private QuoteBlock(block: RichBlock, marginTop: number) {
    Column() {
      Column() {
        ForEach(this.safeBlocks(block), (inner: RichBlock, index: number) => {
          this.BlockView(inner, index)
        }, (inner: RichBlock, index: number) => `${index}-${inner.type}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor('#F8FAFC')
    .border({
      width: { left: 3 },
      color: '#CBD5E1'
    })
    // .borderRadius(8)
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
            .fontColor('#6B7280')
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
            .fillColor('#6B7280')
            .draggable(false)
          Text('复制')
            .fontSize(12)
            .fontColor('#6B7280')
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
          .fontColor('#111827')
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
    .backgroundColor('#F3F4F6')
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
        console.error(`${LOG_TAG} copy code failed: ${JSON.stringify(err)}`);
      });
    } catch (err) {
      console.error(`${LOG_TAG} copy code failed: ${JSON.stringify(err)}`);
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
          .backgroundColor('#F3F4F6')
          .onClick(() => {
            this.openImageLink(block);
          })
      } else {
        Image(block.src ? block.src : '')
          .width('100%')
          .height(260)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#F3F4F6')
          .onClick(() => {
            this.openImageLink(block);
          })
      }

      if (!this.isSmallImage(block) && block.alt && block.alt.length > 0) {
        Text(block.alt)
          .fontSize(12)
          .fontColor('#6B7280')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
          .width('100%')
      }
    }
    .width('100%')
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ListBlock(block: RichBlock, marginTop: number) {
    Column() {
      ForEach(this.safeItems(block), (item: RichListItem, index: number) => {
        Row() {
          Text(block.ordered ? `${index + 1}.` : '•')
            .fontSize(15)
            .fontColor('#6B7280')
            .width(24)

          Column() {
            this.InlineTextBlock(item.inlines, 0)
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
          .fontColor('#6B7280')
          .width('100%')
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor('#FFF7ED')
    .border({
      width: 1,
      color: '#FED7AA'
    })
    .borderRadius(8)
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DisclosureBlock(block: RichBlock, index: number, marginTop: number) {
    Column() {
      Row() {
        Text('▼')
          .fontSize(18)
          .fontColor('#111827')
          .width(28)
          .textAlign(TextAlign.Center)
          .rotate({ angle: this.isDisclosureExpanded(index) ? 0 : -90 })

        Text(this.getDisclosureTitle(block))
          .fontSize(16)
          .fontWeight(FontWeight.Regular)
          .fontColor('#111827')
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
            this.BlockView(inner, childIndex)
          }, (inner: RichBlock, childIndex: number) => `${childIndex}-${inner.type}`)
        }
        .width('100%')
        .padding({ left: 28, right: 0, bottom: 12 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor('#F5F5F5')
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
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
  // 看图用高清原图 href；行内 emoji 不计入。
  private collectImages(): ViewerImage[] {
    const result: ViewerImage[] = [];
    this.collectImagesFrom(this.getRenderableBlocks(), result);
    return result;
  }

  private collectImagesFrom(blocks: RichBlock[], result: ViewerImage[]): void {
    for (let i: number = 0; i < blocks.length; i++) {
      const block: RichBlock = blocks[i];
      if (block.type === RichBlockType.IMAGE) {
        const primary: string = this.primaryImageUrl(block);
        if (primary.length > 0) {
          // 兜底用优化图 src（与帖子内联同源、多已缓存），原图加载失败时回退
          const optimized: string = block.src && block.src !== primary ? block.src : '';
          result.push({ url: primary, fallbackUrl: optimized });
        }
      }
      if (block.blocks && block.blocks.length > 0) {
        this.collectImagesFrom(block.blocks, result);
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
    console.info(`${LOG_TAG} link clicked url=${this.safeLinkLabel(url)}`);
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
