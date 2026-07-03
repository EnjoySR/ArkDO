import {
  CookedHtmlParser,
  RichBlock,
  RichBlockType,
  RichInlineNode,
  RichInlineType,
  RichListItem
} from '../../services/content/CookedHtmlParser';

const LOG_TAG: string = '[ArkDO][PostRichContent]';

@Component
export struct PostRichContent {
  cookedHtml: string = '';
  fallbackText: string = '';

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
    } else if (block.type === RichBlockType.DIVIDER) {
      Divider()
        .strokeWidth(1)
        .color('#E5E7EB')
        .margin({ top: index > 0 ? 14 : 4, bottom: 4 })
    } else {
      this.UnsupportedBlock(block, index > 0 ? 10 : 0)
    }
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
    Row() {
      Divider()
        .vertical(true)
        .strokeWidth(3)
        .color('#CBD5E1')
        .height('100%')
        .margin({ right: 10 })

      Column() {
        ForEach(this.safeBlocks(block), (inner: RichBlock, index: number) => {
          this.BlockView(inner, index)
        }, (inner: RichBlock, index: number) => `${index}-${inner.type}`)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor('#F8FAFC')
    .borderRadius(8)
    .margin({ top: marginTop })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private CodeBlock(block: RichBlock, marginTop: number) {
    Column() {
      if (block.language && block.language.length > 0) {
        Text(block.language)
          .fontSize(12)
          .fontColor('#6B7280')
          .fontFamily('monospace')
          .width('100%')
          .margin({ bottom: 6 })
      }

      Scroll() {
        Text(block.text ? block.text : '')
          .fontSize(13)
          .lineHeight(19)
          .fontFamily('monospace')
          .fontColor('#111827')
          .copyOption(CopyOptions.LocalDevice)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#F3F4F6')
    .borderRadius(8)
    .margin({ top: marginTop })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ImageBlock(block: RichBlock, marginTop: number) {
    Column() {
      Image(block.src ? block.src : '')
        .width('100%')
        .height(this.getImageDisplayHeight(block))
        .objectFit(ImageFit.Contain)
        .backgroundColor('#F3F4F6')
        .borderRadius(8)
        .onClick(() => {
          if (block.href && block.href.length > 0) {
            this.openLink(block.href);
          } else if (block.src && block.src.length > 0) {
            this.openLink(block.src);
          }
        })

      if (block.alt && block.alt.length > 0) {
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

  private getUnsupportedLabel(block: RichBlock): string {
    if (block.unsupportedKind && block.unsupportedKind.length > 0) {
      return block.unsupportedKind;
    }
    return '暂未支持内容';
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

  private getImageDisplayHeight(block: RichBlock): number {
    const width: number = block.width ? block.width : 0;
    const height: number = block.height ? block.height : 0;
    if (width > 0 && height > 0) {
      const ratioHeight: number = Math.round(280 * height / width);
      return Math.max(96, Math.min(360, ratioHeight));
    }
    return 220;
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
