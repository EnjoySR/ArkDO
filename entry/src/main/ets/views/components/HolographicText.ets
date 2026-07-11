// linux.do「Premium」称号的全息闪动效果的原生还原。
// 站点原做法(纯 CSS,无 JS):linear-gradient(135deg, 品红→青→黄→品红→青) + background-size:400%
// + background-clip:text 把渐变裁进字形,再用 @keyframes holographic 15s 无限循环平移 background-position。
//
// ArkUI 无 background-clip:text,改为:Stack 里「文字(destination)+ 超大渐变层(source, blendMode SRC_IN)」
// 离屏合成把渐变裁进字形;渐变层用 position 脱离布局(不撑大 Stack),按等价的 5 关键帧来回挪 = 颜色在字里流动。
// 循环用「有限一轮 + onFinish 若仍挂载则重启」,避免 iterations:-1 停不干净([[arkui-infinite-animation-stop]])。

// 全息渐变色标(与站点一致:magenta / cyan / yellow / magenta / cyan)。
const HOLO_COLORS: Array<[ResourceColor, number]> = [
  ['#FF00FF', 0.0],
  ['#00FFFF', 0.25],
  ['#FFFF00', 0.5],
  ['#FF00FF', 0.75],
  ['#00FFFF', 1.0]
];
// background-size:400% → 渐变层是文字的 4 倍,可平移量 = (400%-100%) = 文字尺寸的 3 倍。
const GRADIENT_SCALE: number = 4;
const SHIFT_SPAN: number = GRADIENT_SCALE - 1; // 3
// 15s 一整轮,4 段关键帧过渡 → 每段 3750ms。
const SEGMENT_MS: number = 3750;

@Component
export struct HolographicText {
  text: string = '';
  fontSize: number = 13;
  fontWeight: FontWeight = FontWeight.Medium;
  // blendMode 不生效时的兜底字色(至少显示成品红,不会消失)。
  fallbackColor: ResourceColor = '#FF00FF';

  // 测得的文字尺寸(vp);渐变层尺寸 = 4×,关键帧偏移基于它换算。
  @State private textWidth: number = 0;
  @State private textHeight: number = 0;
  // 渐变层左上角相对 Stack 的位置(vp),负值=向左/上挪,让渐变的右/下部盖住文字。
  @State private gradientX: number = 0;
  @State private gradientY: number = 0;

  private mounted: boolean = false;
  private running: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.running = false;
  }

  build() {
    Stack() {
      // destination:文字本体,既是裁剪遮罩、又是 blend 失效时的兜底可见层。
      Text(this.text)
        .fontSize(this.fontSize)
        .fontWeight(this.fontWeight)
        .fontColor(this.fallbackColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // source:超大渐变层,SRC_IN 只在文字像素处保留 → 渐变裁进字形。
      // 关键:外层宿主 Stack 显式定死为文字尺寸 + clip,超大渐变在其中溢出被裁,不会撑大布局(否则底下空一片)。
      if (this.textWidth > 0 && this.textHeight > 0) {
        Stack() {
          Column()
            .width(this.textWidth * GRADIENT_SCALE)
            .height(this.textHeight * GRADIENT_SCALE)
            .linearGradient({ angle: 135, colors: HOLO_COLORS })
            .position({ x: this.gradientX, y: this.gradientY })
        }
        .width(this.textWidth)
        .height(this.textHeight)
        .clip(true)
        .blendMode(BlendMode.SRC_IN)
      }
    }
    .alignContent(Alignment.TopStart)
    .clip(true)
    // 离屏合成:让内部 SRC_IN 只作用于本 Stack(文字)而非底下的页面。
    .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
    .onAreaChange((_: Area, area: Area) => {
      const w: number = Number(area.width);
      const h: number = Number(area.height);
      if (w > 0 && h > 0 && (Math.abs(w - this.textWidth) > 0.5 || Math.abs(h - this.textHeight) > 0.5)) {
        this.textWidth = w;
        this.textHeight = h;
        this.resetToStart();
        this.startHolographic();
      }
    })
  }

  // background-position 百分比 → 渐变层偏移(vp)。p%∈[0,100],偏移 = -p/100 * 可平移量。
  private offsetFor(percentX: number, percentY: number): [number, number] {
    const x: number = -(percentX / 100) * SHIFT_SPAN * this.textWidth;
    const y: number = -(percentY / 100) * SHIFT_SPAN * this.textHeight;
    return [x, y];
  }

  // 归到 0% 关键帧 (0%,50%),无过渡。
  private resetToStart(): void {
    const start: [number, number] = this.offsetFor(0, 50);
    this.gradientX = start[0];
    this.gradientY = start[1];
  }

  // 一整轮 15s:0%→25%→50%→75%→100%(=回到 0%),ease-in-out;onFinish 若仍挂载则重启形成无限循环。
  private startHolographic(): void {
    if (this.running || !this.mounted || this.textWidth <= 0 || this.textHeight <= 0) {
      return;
    }
    this.running = true;

    const p25: [number, number] = this.offsetFor(100, 0);
    const p50: [number, number] = this.offsetFor(100, 100);
    const p75: [number, number] = this.offsetFor(0, 100);
    const p100: [number, number] = this.offsetFor(0, 50);

    this.getUIContext().keyframeAnimateTo({
      iterations: 1,
      onFinish: () => {
        this.running = false;
        if (this.mounted) {
          this.startHolographic();
        }
      }
    }, [
      {
        duration: SEGMENT_MS,
        curve: Curve.EaseInOut,
        event: () => {
          this.gradientX = p25[0];
          this.gradientY = p25[1];
        }
      },
      {
        duration: SEGMENT_MS,
        curve: Curve.EaseInOut,
        event: () => {
          this.gradientX = p50[0];
          this.gradientY = p50[1];
        }
      },
      {
        duration: SEGMENT_MS,
        curve: Curve.EaseInOut,
        event: () => {
          this.gradientX = p75[0];
          this.gradientY = p75[1];
        }
      },
      {
        duration: SEGMENT_MS,
        curve: Curve.EaseInOut,
        event: () => {
          this.gradientX = p100[0];
          this.gradientY = p100[1];
        }
      }
    ]);
  }
}
