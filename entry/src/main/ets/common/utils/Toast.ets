import { UIContext } from '@kit.ArkUI';
import { Log } from '../../services/logging/Log';

const LOG_TAG: string = '[ArkDO][Toast]';

// 常规提示时长。操作结果反馈(收藏成功/已复制等)默认用这个。
export const TOAST_DEFAULT_MS: number = 2000;
// 短提示。浮层关闭前的即时反馈用这个,避免盖住后续动画。
export const TOAST_SHORT_MS: number = 1500;

// 全局 toast 门面。原先 12 个页面各写一份逐字相同的 private showToast,
// 差异只在时长和「失败是否记日志」;统一到此处后时长走上面两个常量。
//
// 取 UIContext 而非在内部 getContext():toast 必须挂到发起方所在的 UI 实例上,
// 多窗口(平板双栏)下拿错实例会弹到另一半屏幕去。调用方一律传 this.getUIContext()。
export function showToast(ui: UIContext, message: string, duration: number = TOAST_DEFAULT_MS): void {
  try {
    ui.getPromptAction().showToast({ message: message, duration: duration });
  } catch (error) {
    // 提示失败不影响主流程,只留痕:组件已销毁或 UI 实例失效时会走到这里。
    Log.i(`${LOG_TAG} toast failed: ${message}`);
  }
}
