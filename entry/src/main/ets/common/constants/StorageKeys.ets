// 根级浮层的 AppStorage key 集中处。
//
// 为什么要集中:这些 key 原先各自定义在拥有该浮层的页面/组件文件里(HomePage、SearchOverlay、
// ImageViewer、ComposerPage、DraftsPage…),导致 pages/Index.ets 这个 @Entry 仅仅为了拿三个
// 字符串常量,就被迫 import 了 SearchOverlay / ImageViewer / HomePage 三个重型 UI 组件——
// 一个只做返回键分发的入口页因此拖进了整棵首页依赖树。集中到这里后依赖方向恢复正常:
// 常量在底层,UI 在上层,谁都可以引而不产生反向边。
//
// 命名约定:
//   *_VISIBLE_KEY   —— 浮层可见态镜像(boolean)。浮层不进 Navigation 栈,系统返回键要靠它判断该谁消费。
//   *_BACK_TICK_KEY —— 返回键信号(number,单调自增)。Index/宿主 bump,浮层 @Watch 接住后自行关闭。
//   *_TICK          —— 通用变更信号(number,单调自增),用于跨页通知「数据变了,重新读」。
//
// 值本身只在内存中存活(AppStorage 非持久化),故字符串内容可自由调整;
// 但 SITES_TICK / SETTINGS_DOH_TICK 沿用了历史上的 snake_case 值,未做改动以免与既有日志对不上。

// 搜索浮层(根级,盖满全屏)。
export const SEARCH_OVERLAY_VISIBLE_KEY: string = 'searchOverlayVisible';
export const SEARCH_OVERLAY_BACK_TICK_KEY: string = 'searchOverlayBackTick';

// 图片预览(根级,层级最高,返回键优先消费)。
export const IMAGE_VIEWER_VISIBLE_KEY: string = 'imageViewerVisible';
export const IMAGE_VIEWER_BACK_TICK_KEY: string = 'imageViewerBackTick';

// 首页发帖浮层。首页坐在 navBar(非 NavDestination),其返回键须由 @Entry 拦截。
export const HOME_COMPOSER_VISIBLE_KEY: string = 'homeComposerVisible';
export const HOME_COMPOSER_BACK_TICK_KEY: string = 'homeComposerBackTick';

// 帖子详情页的回帖浮层(与首页发帖浮层各用一套,互不干扰)。
export const COMPOSER_OVERLAY_VISIBLE_KEY: string = 'composerOverlayVisible';
export const COMPOSER_OVERLAY_BACK_TICK_KEY: string = 'composerOverlayBackTick';

// 草稿页的续写浮层 + 草稿列表刷新信号。
export const DRAFTS_COMPOSER_VISIBLE_KEY: string = 'draftsComposerVisible';
export const DRAFTS_COMPOSER_BACK_TICK_KEY: string = 'draftsComposerBackTick';
export const DRAFTS_REFRESH_TICK_KEY: string = 'draftsRefreshTick';

// 站点列表变更信号(站点管理页改动后通知首页抽屉重读)。
export const SITES_TICK: string = 'sites_tick';

// DoH 设置变更信号(DoH 设置页改动后通知设置页刷新摘要)。
export const SETTINGS_DOH_TICK: string = 'settings_doh_tick';

// 自增一个 tick 信号,唤醒所有 @StorageProp/@StorageLink 到该 key 的监听方。
// 原先「读旧值 ?? 0 → +1 → setOrCreate」这三行在 Index 与 RootTabPage 里重复了 9 次。
export function bumpTick(key: string): void {
  const prev: number = (AppStorage.get(key) as number | undefined) ?? 0;
  AppStorage.setOrCreate(key, prev + 1);
}
