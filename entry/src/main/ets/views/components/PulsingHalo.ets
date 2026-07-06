// 头像背后的脉冲光圈:多层同心圆错开时间,各自从 1x 放大到 2.1x 并淡出,无限循环,
// 形成"一圈圈向外扩散"的声呐/水波纹观感,让登录头像不再呆板。
// 用法:置于头像下方(同一 Stack 内先声明本组件、再声明头像),baseSize 对齐头像直径。
const HALO_MAX_SCALE: number = 1.55;  // 扩散终点倍率(不宜过大)
const HALO_START_OPACITY: number = 0.32;
const HALO_DURATION_MS: number = 3400; // 单圈扩散时长,越大越慢
const HALO_STAGGER_MS: number = 1130;  // 相邻两圈的启动间隔≈时长/圈数,错开才均匀连续

@Component
export struct PulsingHalo {
  baseSize: number = 34;
  color: ResourceColor = '#3B82F6';
  // 是否进入扩散终态。onAppear 后置为 true,配合 iterations:-1 形成无限循环。
  // 必须在首帧布局后再切换,否则实现动画不会触发(初始即终态=无过渡)。
  @State private expanded: boolean = false;

  build() {
    Stack() {
      this.Ring(0)
      this.Ring(HALO_STAGGER_MS)
      this.Ring(HALO_STAGGER_MS * 2)
    }
    .width(this.baseSize)
    .height(this.baseSize)
    .onAppear(() => {
      this.expanded = true;
    })
  }

  @Builder
  private Ring(delay: number) {
    Circle()
      .width(this.baseSize)
      .height(this.baseSize)
      .fill(this.color)
      .opacity(this.expanded ? 0 : HALO_START_OPACITY)
      .scale(this.expanded
        ? { x: HALO_MAX_SCALE, y: HALO_MAX_SCALE }
        : { x: 1, y: 1 })
      .animation({
        duration: HALO_DURATION_MS,
        curve: Curve.EaseOut,
        delay: delay,
        iterations: -1
      })
  }
}
