/**
 * AppStorage 中「当前是否宽屏布局」的布尔 key,供 UI 通过 @StorageProp 响应式绑定。
 * true 表示窗口宽度达到宽屏阈值(平板横屏 / 大屏),此时:
 *   - RootTabPage 的 Navigation 切成双栏 Split(左列表右详情);
 *   - 富文本图片启用宽屏规则(居中 + 宽度封顶 + 按屏高限高)。
 * false(手机、平板竖屏)保持单栏 Stack 与手机端原有渲染,行为完全不变。
 */
export const APP_IS_WIDE_STORAGE_KEY: string = 'appIsWide';

/**
 * 宽屏阈值(vp)。取 840:
 *   - 手机(≈360,横屏也极少超 840)→ 非宽屏,单栏,和现状一致;
 *   - 平板竖屏(≈711)→ 非宽屏,单栏(满足「竖屏不要双栏」);
 *   - 平板横屏(≈1138)→ 宽屏,双栏。
 * 注:Navigation 默认 Auto 在 520vp 就分栏,会把平板竖屏也切成双栏;这里用更高的
 * 840 阈值显式驱动 mode,才能做到「竖屏单栏 / 横屏双栏」。
 */
export const WIDE_THRESHOLD_VP: number = 840;

/**
 * 响应式断点。判定「当前窗口是否宽屏」并写入 AppStorage 供各页 @StorageProp('appIsWide') 读取。
 *
 * 实测宽度不用 mediaquery(在 onCreate 阶段窗口未就绪、且 `(width>=Nvp)` 语法不稳),
 * 改由 RootTabPage 根 Stack 的 onAreaChange 把实际布局宽度(vp)喂进 applyWidth——
 * 布局驱动,首帧与旋转/分屏都会触发,最可靠。
 */
export class BreakpointManager {
  /** 应用启动时调用一次:先把 key 播种为 false(非宽屏),保证首帧渲染前 AppStorage 有值。 */
  static init(): void {
    if (AppStorage.get<boolean>(APP_IS_WIDE_STORAGE_KEY) === undefined) {
      AppStorage.setOrCreate(APP_IS_WIDE_STORAGE_KEY, false);
    }
  }

  /** 由布局回调喂入当前窗口宽度(vp),按阈值折算宽屏标志,仅在变化时写回,避免无谓刷新。 */
  static applyWidth(widthVp: number): void {
    const wide: boolean = widthVp >= WIDE_THRESHOLD_VP;
    if (AppStorage.get<boolean>(APP_IS_WIDE_STORAGE_KEY) !== wide) {
      AppStorage.setOrCreate(APP_IS_WIDE_STORAGE_KEY, wide);
    }
  }
}
