import { ImagePreview, PreviewDirection } from '@rv/image-preview';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';

/**
 * 一张待浏览的图片：url 为首选（原图 href，高清），优化图作为兜底。
 * fallbackUrl 为优化图 src（与贴子内联同源、多已缓存），原图加载失败时回退。
 */
export interface ViewerImage {
  url: string;
  fallbackUrl: string;
}

// 预览可见态镜像 + 系统返回键信号:浮层不进 Navigation 栈,返回键由 Index @Entry 拦截并
// bump 计数,经 RootTabPage 以 @Param 传入本组件消费(非首图翻回上一张,首图才关闭)。
export const IMAGE_VIEWER_VISIBLE_KEY: string = 'imageViewerVisible';
export const IMAGE_VIEWER_BACK_TICK_KEY: string = 'imageViewerBackTick';

const MIN_SCALE: number = 1;
const MAX_SCALE: number = 4;
const DOUBLE_TAP_SCALE: number = 2.5;

// 拖动关闭：竖直位移绝对值超过该阈值即关闭，否则回弹（上/下拖同等）
const DISMISS_THRESHOLD: number = 120;
// 缩放估计值高于该值即视为「已放大」，此时禁用拖动关闭（让位给库的图片平移）
const ZOOM_EPSILON: number = 1.05;

/**
 * 全屏图片浏览器：Swiper 管多图翻页，每页用三方库 @rv/image-preview 的 ImagePreview
 * 承载缩放/平移/双击。direction=Horizontal：水平平移到边界让给横向 Swiper 翻页（多图切换的必需项）。
 * 注意这是库的取舍——Horizontal 不夹竖直（放大后可把图拖出屏外），Vertical 虽夹竖直却会吃掉水平、翻页失效，
 * 二者不可兼得；多图翻页优先，故用 Horizontal，竖直越界是库限制暂无法外部修正。
 * 需在页面级渲染（放页面根 Stack 顶层），不能塞进 bindContentCover——其内容不随状态刷新。
 */
@ComponentV2
export struct ImageViewer {
  @Param images: ViewerImage[] = [];
  @Param startIndex: number = 0;
  @Param onClose: () => void = () => {};
  // 系统返回键信号计数(Index 拦截后 bump):非首图翻回上一张,首图关闭预览。
  @Param backTick: number = 0;

  @Local currentIndex: number = 0;
  @Local failedIndexes: number[] = [];
  // 高清原图已加载完成的页下标（隐藏该页 loading 指示）
  @Local loadedIndexes: number[] = [];
  // 顶部状态栏高度，用于让关闭按钮避让状态栏
  @Local topInset: number = 0;
  // 拖动关闭的实时竖直位移（>0 向下、<0 向上拖动中）
  @Local dragOffsetY: number = 0;
  // 缩放估计值：库不暴露真实 scale，靠并行的双击/双指手势自维护，仅用于判断「是否已放大」。
  // 未放大(≈1)才放行拖动关闭；放大后禁用，把竖直拖动让给库的图片平移。
  @Local scaleGuess: number = 1;
  private pinchBase: number = 1;
  // 返回键翻页用控制器:showPrevious 带切换动画并触发 onChange(直接改 .index 无动画)。
  private swiperController: SwiperController = new SwiperController();

  // 返回键:非首图翻回上一张(动画翻页,onChange 会同步 currentIndex 并重置缩放估计),首图关闭。
  @Monitor('backTick')
  onBackTick(): void {
    if (this.currentIndex > 0) {
      this.swiperController.showPrevious();
      return;
    }
    this.onClose();
  }

  aboutToAppear(): void {
    this.currentIndex = this.clampIndex(this.startIndex);
    // 状态栏高度读全局插图(ImmersiveWindow 维护):预览打开时状态栏可能已被隐藏,
    // 此刻查 getWindowAvoidArea 会得 0,关闭按钮就会顶进挖孔/刘海区;AppStorage 里是冻结的真实高度。
    this.topInset = (AppStorage.get(SYS_TOP_INSET_KEY) as number | undefined) ?? 0;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Swiper(this.swiperController) {
        Repeat<ViewerImage>(this.images).each((ri: RepeatItem<ViewerImage>) => {
          ImagePreview({
            config: {
              minScale: MIN_SCALE,
              maxScale: MAX_SCALE,
              doubleClickDefaultScale: DOUBLE_TAP_SCALE,
              // Horizontal：水平到边界让给横向 Swiper 翻页（多图切换必需）。
              // 换 Vertical 会夹住竖直但吃掉水平、导致翻页失效，故保持 Horizontal。
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
                .onComplete(() => {
                  this.markLoaded(ri.index);
                })
                .onError(() => {
                  this.markFailed(ri.index);
                  // 回退到优化图后也算「已就绪」，隐藏 loading
                  this.markLoaded(ri.index);
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
      // 拖动关闭时整页内容随手指上/下移
      .translate({ y: this.dragOffsetY })
      .onChange((index: number) => {
        this.currentIndex = index;
        // 翻页后库会重置该页缩放，同步重置估计值，让新页可下滑关闭
        this.scaleGuess = 1;
        this.dragOffsetY = 0;
      })

      // 高清原图加载中的转圈（当前页未就绪且未失败时显示；优化图已垫底，仅提示高清在路上）
      if (!this.isLoaded(this.currentIndex) && this.failedIndexes.indexOf(this.currentIndex) < 0) {
        Column() {
          LoadingProgress()
            .width(44)
            .height(44)
            .color('#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }

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
    // 黑底：下滑关闭时随位移渐透，露出身后页面（iOS 风格拖拽消隐）
    .backgroundColor(this.backdropColor())
    // 铺满顶部状态栏 + 底部导航条安全区，黑底沉浸式，避免露白
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 并行手势：与库内手势共存。双击/双指仅用于自维护缩放估计；竖直 Pan 做「未放大时上/下拖关闭」。
    .parallelGesture(
      GestureGroup(GestureMode.Parallel,
        TapGesture({ count: 2 })
          .onAction(() => {
            this.scaleGuess = this.scaleGuess > ZOOM_EPSILON ? MIN_SCALE : DOUBLE_TAP_SCALE;
          }),
        PinchGesture()
          .onActionStart(() => {
            this.pinchBase = this.scaleGuess;
          })
          .onActionUpdate((event: GestureEvent) => {
            const next: number = this.pinchBase * event.scale;
            this.scaleGuess = next < MIN_SCALE ? MIN_SCALE : (next > MAX_SCALE ? MAX_SCALE : next);
          }),
        PanGesture({ direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => {
            // 已放大 → 让位给库的图片平移；未放大时上/下拖均可关闭
            if (this.scaleGuess > ZOOM_EPSILON) {
              this.dragOffsetY = 0;
              return;
            }
            this.dragOffsetY = event.offsetY;
          })
          .onActionEnd(() => {
            if (this.scaleGuess > ZOOM_EPSILON) {
              return;
            }
            if (Math.abs(this.dragOffsetY) > DISMISS_THRESHOLD) {
              this.onClose();
              return;
            }
            this.springBack();
          })
          .onActionCancel(() => {
            this.springBack();
          })
      )
    )
  }

  // 回弹到原位（拖动未过阈值）
  private springBack(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.dragOffsetY = 0;
    });
  }

  // 黑底透明度随拖动位移（上/下同等）递减，最低留 25% 黑（保证内容仍可辨）
  private backdropColor(): string {
    const fade: number = Math.abs(this.dragOffsetY) / 300;
    const clamped: number = fade > 0.75 ? 0.75 : fade;
    const alpha: number = Math.round((1 - clamped) * 255);
    let hex: string = alpha.toString(16);
    if (hex.length < 2) {
      hex = `0${hex}`;
    }
    return `#${hex}000000`;
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

  private isLoaded(index: number): boolean {
    return this.loadedIndexes.indexOf(index) >= 0;
  }

  private markLoaded(index: number): void {
    if (this.loadedIndexes.indexOf(index) >= 0) {
      return;
    }
    this.loadedIndexes = this.loadedIndexes.concat([index]);
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
