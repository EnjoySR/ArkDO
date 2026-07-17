// 首页右下角「同位 morph」悬浮按钮:列表在顶部区域时是「发帖」,滑过约 1.5 屏后原地换身份为「回到顶部」。
// 两个动作的出现时机天然互斥(要回顶时必然已滑离顶部,而滑动中发帖本就该让位),
// 故共用一个坑位,右下角永远只有一个图标。
//
// 为什么不做交叉淡入:两个图标外形毫无共同点(方框带笔 / 箭头带横线),同时半透会糊成一团。
// 改用「错峰替换」——旧图标缩小淡出 → 留一段空窗 → 新图标从小弹回原大;
// 底座圆形全程尺寸不动、只渐变颜色,读起来才是「同一个按钮换了身份」而非「一个消失另一个出现」。

const ICON_OUT_MS: number = 130;
const ICON_IN_MS: number = 180;
// 图标退场/入场的缩放起止点:不缩到 0,留点体量,免得像是被"吸走"。
const ICON_MIN_SCALE: number = 0.6;
// 底座配色渐变时长:略长于图标整体替换,让颜色成为贯穿两态的连续量。
const BG_MORPH_MS: number = 220;

@Component
export struct HomeFab {
  // 由父页滚动位置驱动:true=回顶态,false=发帖态。
  @Prop @Watch('onModeChanged') showBackToTop: boolean = false;
  onCompose: () => void = () => {};
  onBackToTop: () => void = () => {};

  // 当前实际渲染的图标。在错峰替换的"空窗"里才翻转,故会比 showBackToTop 滞后 ICON_OUT_MS——
  // 这个滞后是刻意的,不要用 showBackToTop 直接驱动图标,否则就退化成硬切了。
  @State private iconIsTop: boolean = false;
  @State private iconScale: number = 1;
  @State private iconOpacity: number = 1;
  // 替换动画进行中标志:快速来回滚动时,防多段动画叠加把图标停在半透明中间态。
  private morphing: boolean = false;

  private onModeChanged(): void {
    // 动画期间不抢:收尾的 onFinish 会重新对账目标态,必要时自动补一轮。
    if (this.morphing) {
      return;
    }
    this.runMorph();
  }

  private runMorph(): void {
    // 已经是目标身份则收工(也是上面"对账"的出口)。
    if (this.iconIsTop === this.showBackToTop) {
      this.morphing = false;
      return;
    }
    this.morphing = true;
    animateTo({
      duration: ICON_OUT_MS,
      curve: Curve.EaseIn,
      onFinish: () => {
        // 空窗:此刻图标已不可见,在这里换身份才不会被看到中间帧。
        this.iconIsTop = this.showBackToTop;
        animateTo({
          duration: ICON_IN_MS,
          curve: Curve.EaseOut,
          onFinish: () => {
            this.morphing = false;
            // 对账:退场/入场这 310ms 里若模式又翻回去了,这里补做一轮。
            this.runMorph();
          }
        }, () => {
          this.iconScale = 1;
          this.iconOpacity = 1;
        });
      }
    }, () => {
      this.iconScale = ICON_MIN_SCALE;
      this.iconOpacity = 0;
    });
  }

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(this.iconIsTop ? $r('sys.symbol.arrow_up_to_line') : $r('sys.symbol.square_and_pencil'))
        .fontSize(22)
        .fontColor([this.iconIsTop ? $r('app.color.fab_top_fg') : $r('app.color.fab_compose_fg')])
        .scale({ x: this.iconScale, y: this.iconScale })
        .opacity(this.iconOpacity)
    }
    .width(52)
    .height(52)
    // 发帖=实心品牌蓝(主动作,压得住场);回顶=中性底(辅助动作,视觉权重主动让位)。
    // 两套色都走资源,暗色由 dark/color.json 自动翻转,不用手动读 appIsDark。
    .backgroundColor(this.showBackToTop ? $r('app.color.fab_top_bg') : $r('app.color.fab_compose_bg'))
    // 回顶态是浅/深中性底,和页面背景对比弱,补一道发丝描边把它"托"起来;发帖态实心蓝不需要。
    .borderWidth(this.showBackToTop ? 1 : 0)
    .borderColor($r('app.color.fab_top_border'))
    .shadow({ radius: 8, color: $r('app.color.fab_shadow'), offsetX: 0, offsetY: 2 })
    // 隐式动画只作用于其上方声明的属性(背景色/描边),图标的缩放淡入淡出由 animateTo 显式接管。
    .animation({ duration: BG_MORPH_MS, curve: Curve.EaseInOut })
    .onClick(() => {
      if (this.showBackToTop) {
        this.onBackToTop();
      } else {
        this.onCompose();
      }
    })
  }
}
