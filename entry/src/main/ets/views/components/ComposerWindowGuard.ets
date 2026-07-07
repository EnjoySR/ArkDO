import window from '@ohos.window';

// 关闭评论时,延迟退出全屏的时长(略大于遮罩淡出 220ms),让遮罩淡完再落全屏,避免状态栏先露白。
const COMPOSER_EXIT_MS: number = 240;

export type FullScreenChangeFn = (on: boolean) => void;

// 评论输入浮层的全屏窗口守卫:浮层展开时切全屏布局(让遮罩盖住状态栏、输入条贴键盘上沿),
// 收起时保持全屏直到遮罩淡出结束(COMPOSER_EXIT_MS)再落下——
// 否则窗口先退全屏会让状态栏区域先露白再盖回(用户反馈的白闪 BUG)。
// 全屏开关经 onChange 回调同步给页面 @State,页面据此给主内容补一个状态栏高度的顶部内边距。
export class ComposerWindowGuard {
  // 状态栏高度(vp),供页面全屏时补偿背后内容位移。init 时读一次。
  statusBarHeight: number = 0;
  private mainWindow?: window.Window = undefined;
  private exitTimer: number = -1;
  private isFullScreen: boolean = false;
  private onChange: FullScreenChangeFn;

  constructor(onChange: FullScreenChangeFn) {
    this.onChange = onChange;
  }

  // 页面挂载时调用:读主窗口与状态栏高度。
  // 读不到时退化为不切全屏(状态栏不被遮罩覆盖,但不影响输入本身)。
  init(context: Context): void {
    window.getLastWindow(context).then((win: window.Window) => {
      this.mainWindow = win;
      const sysArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = px2vp(sysArea.topRect.height);
    }).catch(() => {});
  }

  // 浮层展开→立即切全屏;收起→延迟到淡出动画结束再落下。
  toggle(showComposer: boolean): void {
    if (this.exitTimer >= 0) {
      clearTimeout(this.exitTimer);
      this.exitTimer = -1;
    }
    if (showComposer) {
      this.apply(true);
    } else {
      this.exitTimer = setTimeout(() => {
        this.exitTimer = -1;
        this.apply(false);
      }, COMPOSER_EXIT_MS);
    }
  }

  // 页面离开时调用:清掉待触发的退出计时器;若仍处于全屏(浮层未正常关闭),兜底还原布局。
  dispose(): void {
    if (this.exitTimer >= 0) {
      clearTimeout(this.exitTimer);
      this.exitTimer = -1;
    }
    if (this.isFullScreen) {
      this.mainWindow?.setWindowLayoutFullScreen(false).catch(() => {});
      this.isFullScreen = false;
    }
    this.mainWindow = undefined;
  }

  private apply(on: boolean): void {
    this.isFullScreen = on;
    this.onChange(on);
    this.mainWindow?.setWindowLayoutFullScreen(on).catch(() => {});
  }
}
