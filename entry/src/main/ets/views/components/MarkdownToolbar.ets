import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { MdAction, MdActionKind } from '../../utils/markdownInsert';

// 工具栏单个按钮:图标 id + 语义。action 有值走格式插入;special='image' 走选图上传回调。
interface ToolbarButton {
  iconId: string;
  action?: MdAction;
  special?: string;
}

// 工具栏按钮清单(顺序即展示顺序)。图片按钮 special 标记,其余携带 MdAction 由父级统一 apply。
const TOOLBAR_BUTTONS: ToolbarButton[] = [
  { iconId: 'image', special: 'image' },
  { iconId: 'bold', action: { kind: MdActionKind.Wrap, before: '**', after: '**', placeholder: '粗体' } },
  { iconId: 'italic', action: { kind: MdActionKind.Wrap, before: '_', after: '_', placeholder: '斜体' } },
  { iconId: 'quote-left', action: { kind: MdActionKind.LinePrefix, prefix: '> ' } },
  { iconId: 'code', action: { kind: MdActionKind.Wrap, before: '`', after: '`', placeholder: '代码' } },
  { iconId: 'file-code', action: { kind: MdActionKind.InsertCursor, snippet: '```\n\n```', cursorOffset: 4, selectLength: 0 } },
  { iconId: 'list-ul', action: { kind: MdActionKind.LinePrefix, prefix: '- ' } },
  { iconId: 'list-ol', action: { kind: MdActionKind.LinePrefix, ordered: true } },
  { iconId: 'hashtag', action: { kind: MdActionKind.LinePrefix, prefix: '# ' } },
  { iconId: 'link', action: { kind: MdActionKind.Wrap, before: '[', after: '](url)', placeholder: '链接文字' } }
];

// Markdown 快捷工具栏:一排图标,点击插入对应语法。横向可滚,轻量态与全屏态复用同一组件。
// 与文本无关——只发出「要做什么」(onAction / onPickImage),文本改写由持有 TextAreaController 的页面完成。
@Component
export struct MarkdownToolbar {
  // 图标颜色(默认次要文字色);随主题走。
  tintColor: ResourceColor = $r('app.color.text_secondary');
  // 上传是否进行中:置灰图片按钮避免重复触发。
  disabled: boolean = false;
  onAction: (action: MdAction) => void = (action: MdAction) => {};
  onPickImage: () => void = () => {};

  private iconOf(id: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(id);
    return def ? def : { id: id, rawfilePath: `fa_icons/${id}.svg` };
  }

  private handleTap(button: ToolbarButton): void {
    if (button.special === 'image') {
      if (!this.disabled) {
        this.onPickImage();
      }
      return;
    }
    if (button.action) {
      this.onAction(button.action);
    }
  }

  build() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(TOOLBAR_BUTTONS, (button: ToolbarButton) => {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            FaIconView({
              icon: this.iconOf(button.iconId),
              color: this.tintColor,
              iconSize: 18
            })
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .opacity(button.special === 'image' && this.disabled ? 0.4 : 1)
          .onClick(() => {
            this.handleTap(button);
          })
        }, (button: ToolbarButton) => button.iconId)
      }
      .padding({ left: 8, right: 8 })
      .height(48)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(48)
    .align(Alignment.Start)
  }
}
