import { RootTabPage } from '../views/pages/RootTabPage';
import { SEARCH_OVERLAY_BACK_TICK_KEY, SEARCH_OVERLAY_VISIBLE_KEY } from '../views/components/SearchOverlay';

@Entry
@Component
struct Index {
  // 搜索浮层可见态镜像:浮层不进 Navigation 栈,系统返回键需在此拦截。
  @StorageProp(SEARCH_OVERLAY_VISIBLE_KEY) private searchOverlayVisible: boolean = false;

  build() {
    Column() {
      RootTabPage()
    }
    .width('100%')
    .height('100%')
  }

  // 返回键:搜索浮层开着时消费返回键并 bump 关闭信号(RootTabPage 监听后关浮层),
  // 否则放行走系统默认(Navigation 出栈 / 退出应用)。
  onBackPress(): boolean {
    if (this.searchOverlayVisible) {
      const prev: number = (AppStorage.get(SEARCH_OVERLAY_BACK_TICK_KEY) as number | undefined) ?? 0;
      AppStorage.setOrCreate(SEARCH_OVERLAY_BACK_TICK_KEY, prev + 1);
      return true;
    }
    return false;
  }
}
