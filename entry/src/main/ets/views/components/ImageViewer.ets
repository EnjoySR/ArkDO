import { ImagePreview, PreviewDirection } from '@rv/image-preview';
import window from '@ohos.window';

/**
 * 一张待浏览的图片：url 为首选（原图 href，高清），优化图作为兜底。
 * fallbackUrl 为优化图 src（与贴子内联同源、多已缓存），原图加载失败时回退。
 */
export interface ViewerImage {
  url: string;
  fallbackUrl: string;
}

const MIN_SCALE: number = 1;
const MAX_SCALE: number = 4;
const DOUBLE_TAP_SCALE: number = 2.5;

/**
 * 全屏图片浏览器：Swiper 管多图翻页，每页用三方库 @rv/image-preview 的 ImagePreview
 * 承载缩放/平移/双击（direction=Horizontal 与横向 Swiper 协同，放大吃横滑、到边界让给 Swiper）。
 * 需在页面级渲染（放页面根 Stack 顶层），不能塞进 bindContentCover——其内容不随状态刷新。
 */
@ComponentV2
export struct ImageViewer {
  @Param images: ViewerImage[] = [];
  @Param startIndex: number = 0;
  @Param onClose: () => void = () => {};

  @Local currentIndex: number = 0;
  @Local failedIndexes: number[] = [];
  // 顶部状态栏高度，用于让关闭按钮避让状态栏
  @Local topInset: number = 0;

  aboutToAppear(): void {
    this.currentIndex = this.clampIndex(this.startIndex);
    this.resolveTopInset();
  }

  // 查询系统状态栏高度（沉浸式全屏下让关闭按钮不被状态栏遮挡）
  private resolveTopInset(): void {
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.topInset = px2vp(area.topRect.height);
      }).catch(() => {
      });
    } catch (err) {
      this.topInset = 0;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Swiper() {
        Repeat<ViewerImage>(this.images).each((ri: RepeatItem<ViewerImage>) => {
          ImagePreview({
            config: {
              minScale: MIN_SCALE,
              maxScale: MAX_SCALE,
              doubleClickDefaultScale: DOUBLE_TAP_SCALE,
              direction: PreviewDirection.Horizontal,
              onClick: () => {
                this.onClose();
              }
            }
          }) {
            // 渐进加载：底层优化图（已缓存、秒显占位，避免高清图未回来时纯黑），
            // 顶层高清原图加载完成后覆盖；高清失败则回退优化图。
            Stack() {
              Image(this.placeholderUrl(ri.index))
                .objectFit(ImageFit.Contain)
                .width('100%')
                .height('100%')
                .draggable(false)

              Image(this.resolveUrl(ri.index))
                .objectFit(ImageFit.Contain)
                .width('100%')
                .height('100%')
                .draggable(false)
                .onError(() => {
                  this.markFailed(ri.index);
                })
            }
            .width('100%')
            .height('100%')
          }
        })
      }
      .index(this.currentIndex)
      .loop(false)
      .indicator(false)
      .width('100%')
      .height('100%')
      // 让图片视口也扩展到状态栏/导航条区域，放大后能铺满全屏
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onChange((index: number) => {
        this.currentIndex = index;
      })

      // 页码指示（多图时显示），透传点击不拦截手势
      if (this.images.length > 1) {
        Column() {
          Text(`${this.currentIndex + 1} / ${this.images.length}`)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#00000080')
            .borderRadius(14)
            .padding({ left: 14, right: 14, top: 5, bottom: 5 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: 44 })
        .hitTestBehavior(HitTestMode.None)
      }

      // 关闭按钮（下移 topInset 避让状态栏）
      Text('✕')
        .fontSize(20)
        .fontColor('#FFFFFF')
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .borderRadius(20)
        .backgroundColor('#00000066')
        .margin({ top: this.topInset + 12, left: 12 })
        .onClick(() => {
          this.onClose();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    // 铺满顶部状态栏 + 底部导航条安全区，黑底沉浸式，避免露白
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // 占位图：优先用优化图（帖子内联同源、多已缓存，秒显）；没有则退回高清图本身
  private placeholderUrl(index: number): string {
    const item: ViewerImage = this.images[index];
    if (item.fallbackUrl.length > 0) {
      return item.fallbackUrl;
    }
    return item.url;
  }

  private resolveUrl(index: number): string {
    const item: ViewerImage = this.images[index];
    const failed: boolean = this.failedIndexes.indexOf(index) >= 0;
    if (failed && item.fallbackUrl.length > 0) {
      return item.fallbackUrl;
    }
    if (item.url.length > 0) {
      return item.url;
    }
    return item.fallbackUrl;
  }

  private markFailed(index: number): void {
    const item: ViewerImage = this.images[index];
    if (item.fallbackUrl.length === 0 || item.fallbackUrl === item.url) {
      return;
    }
    if (this.failedIndexes.indexOf(index) >= 0) {
      return;
    }
    this.failedIndexes = this.failedIndexes.concat([index]);
  }

  private clampIndex(index: number): number {
    if (index < 0) {
      return 0;
    }
    if (index >= this.images.length) {
      return this.images.length > 0 ? this.images.length - 1 : 0;
    }
    return index;
  }
}
