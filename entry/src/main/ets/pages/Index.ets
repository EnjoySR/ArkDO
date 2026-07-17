import { RootTabPage } from '../views/pages/RootTabPage';
import { SEARCH_OVERLAY_BACK_TICK_KEY, SEARCH_OVERLAY_VISIBLE_KEY } from '../views/components/SearchOverlay';
import { IMAGE_VIEWER_BACK_TICK_KEY, IMAGE_VIEWER_VISIBLE_KEY } from '../views/components/ImageViewer';
import { HOME_COMPOSER_BACK_TICK_KEY, HOME_COMPOSER_VISIBLE_KEY } from '../views/pages/HomePage';

@Entry
@Component
struct Index {
  // 搜索浮层可见态镜像:浮层不进 Navigation 栈,系统返回键需在此拦截。
  @StorageProp(SEARCH_OVERLAY_VISIBLE_KEY) private searchOverlayVisible: boolean = false;
  // 图片预览可见态镜像:同为根级浮层,返回键在此拦截(翻回上一张/首图关闭,由 ImageViewer 消费)。
  @StorageProp(IMAGE_VIEWER_VISIBLE_KEY) private imageViewerVisible: boolean = false;
  // 首页发帖浮层可见态镜像:首页坐在 navBar,其根级浮层的返回键也在此拦截。
  @StorageProp(HOME_COMPOSER_VISIBLE_KEY) private homeComposerVisible: boolean = false;

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
    // 图片预览在最顶层,优先消费:bump 信号,ImageViewer 决定翻回上一张还是关闭。
    if (this.imageViewerVisible) {
      const prev: number = (AppStorage.get(IMAGE_VIEWER_BACK_TICK_KEY) as number | undefined) ?? 0;
      AppStorage.setOrCreate(IMAGE_VIEWER_BACK_TICK_KEY, prev + 1);
      return true;
    }
    if (this.searchOverlayVisible) {
      const prev: number = (AppStorage.get(SEARCH_OVERLAY_BACK_TICK_KEY) as number | undefined) ?? 0;
      AppStorage.setOrCreate(SEARCH_OVERLAY_BACK_TICK_KEY, prev + 1);
      return true;
    }
    // 首页发帖浮层:开着就消费返回键,bump tick 让 HomePage 关闭。
    if (this.homeComposerVisible) {
      const prev: number = (AppStorage.get(HOME_COMPOSER_BACK_TICK_KEY) as number | undefined) ?? 0;
      AppStorage.setOrCreate(HOME_COMPOSER_BACK_TICK_KEY, prev + 1);
      return true;
    }
    return false;
  }
}
