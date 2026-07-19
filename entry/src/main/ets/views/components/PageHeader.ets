// 二级页统一返回头栏:圆形返回键 + 标题 + 可选尾部动作区。
//
// 抽取前这一段(40×40 圆形按钮 + 28 号 chevron_left + 20 号粗体标题 + height 56 +
// padding{left:12,right:8})在 14 个二级页里逐字复制,改一处样式要同步 14 个文件。
//
// title 用 @Prop 而非普通成员:普通成员只在构造时赋值一次,父页 @State 改标题
// (如活动列表按类型切标题)不会同步过来;@Prop 才跟随父级变化重渲染。
@Component
export struct PageHeader {
  @Prop title: string = '';
  onBack: () => void = () => {};
  // 尾部动作区(计数、齿轮、清空按钮等)。不传则为空,不占位。
  @BuilderParam trailing: () => void = this.noTrailing;
  // 右内边距。尾部是文字/计数时用 8;尾部是 40×40 圆形按钮时用 12,与左侧视觉对称。
  @Prop paddingRight: number = 8;

  @Builder
  private noTrailing() {
  }

  build() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([$r('app.color.text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.surface_muted'))
      .onClick(() => {
        this.onBack();
      })

      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      this.trailing()
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: this.paddingRight })
  }
}
