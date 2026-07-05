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
 * 全屏图片浏览器（自建）：Swiper 多图滑动 + 对焦点缩放 + 带边界平移 + 双击定点放大。
 * 未放大时 Swiper 翻页，放大后禁翻页并允许平移。
 * 需在页面级渲染（放页面根 Stack 顶层），不能塞进 bindContentCover——其内容不随状态刷新。
 */
@Component
export struct ImageViewer {
  images: ViewerImage[] = [];
  startIndex: number = 0;
  onClose: () => void = () => {};

  // 驱动 UI（页码 + 当前页缩放/平移判断）的索引，仅由 onChange 更新
  @State private currentIndex: number = 0;
  // 绑定给 Swiper.index() 的索引，与 currentIndex 拆开，避免 Swiper 回写导致 currentIndex 赋同值不刷新
  @State private swiperIndex: number = 0;
  @State private imgScale: number = MIN_SCALE;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private failedIndexes: number[] = [];
  // 顶部状态栏高度，用于让关闭按钮避让状态栏
  @State private topInset: number = 0;

  // 手势起始基准（非响应式）
  private baseScale: number = MIN_SCALE;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;
  private pinchCenterX: number = 0;
  private pinchCenterY: number = 0;
  // 视口尺寸
  private viewW: number = 0;
  private viewH: number = 0;
  // 本次触摸是否发生过移动/多指（用于抑制拖动/捏合抬手后的误单击关闭）
  private movedDuringTouch: boolean = false;
  private touchDownX: number = 0;
  private touchDownY: number = 0;

  aboutToAppear(): void {
    this.currentIndex = this.clampIndex(this.startIndex);
    this.swiperIndex = this.currentIndex;
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
        ForEach(this.images, (item: ViewerImage, index: number) => {
          Image(this.resolveUrl(index))
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
            .scale({
              x: index === this.currentIndex ? this.imgScale : 1,
              y: index === this.currentIndex ? this.imgScale : 1
            })
            .translate({
              x: index === this.currentIndex ? this.offsetX : 0,
              y: index === this.currentIndex ? this.offsetY : 0
            })
            .onError(() => {
              this.markFailed(index);
            })
            .onTouch((event: TouchEvent) => {
              this.trackTouchMovement(event);
            })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                PinchGesture({ fingers: 2 })
                  .onActionStart((event: GestureEvent) => {
                    console.info(`[ArkDO][ImageViewer] Pinch start imgScale=${this.imgScale.toFixed(2)}`);
                    this.movedDuringTouch = true;
                    this.baseScale = this.imgScale;
                    this.baseOffsetX = this.offsetX;
                    this.baseOffsetY = this.offsetY;
                    this.pinchCenterX = event.pinchCenterX;
                    this.pinchCenterY = event.pinchCenterY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const next: number = this.clampScale(this.baseScale * event.scale);
                    const ratio: number = next / this.baseScale;
                    // 让捏合中心在缩放前后保持不动
                    const fx: number = this.pinchCenterX - this.viewW / 2;
                    const fy: number = this.pinchCenterY - this.viewH / 2;
                    this.offsetX = fx - (fx - this.baseOffsetX) * ratio;
                    this.offsetY = fy - (fy - this.baseOffsetY) * ratio;
                    this.imgScale = next;
                    this.clampOffset();
                  })
                  .onActionEnd(() => {
                    console.info(`[ArkDO][ImageViewer] Pinch end imgScale=${this.imgScale.toFixed(2)}`);
                    if (this.imgScale <= MIN_SCALE) {
                      this.resetTransform('pinchEnd');
                    }
                  }),
                // 未放大时方向设 None：不消费横滑，交给外层 Swiper 翻页；放大后才用于平移
                PanGesture({ fingers: 1, direction: this.imgScale > MIN_SCALE ? PanDirection.All : PanDirection.None })
                  .onActionStart(() => {
                    console.info(`[ArkDO][ImageViewer] Pan start imgScale=${this.imgScale.toFixed(2)} viewW=${this.viewW.toFixed(0)} baseOffsetX=${this.baseOffsetX.toFixed(1)}`);
                    this.baseOffsetX = this.offsetX;
                    this.baseOffsetY = this.offsetY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    if (this.imgScale <= MIN_SCALE) {
                      return;
                    }
                    const rawX: number = this.baseOffsetX + event.offsetX;
                    const maxX: number = this.viewW * (this.imgScale - 1) / 2;
                    this.offsetX = rawX;
                    this.offsetY = this.baseOffsetY + event.offsetY;
                    this.clampOffset();
                    console.info(`[ArkDO][ImageViewer] Pan update evtDx=${event.offsetX.toFixed(1)} rawX=${rawX.toFixed(1)} maxX=${maxX.toFixed(1)} clampedX=${this.offsetX.toFixed(1)}`);
                  }),
                GestureGroup(GestureMode.Exclusive,
                  TapGesture({ count: 2 })
                    .onAction((event: GestureEvent) => {
                      this.handleDoubleTap(event);
                    }),
                  TapGesture({ count: 1 })
                    .onAction(() => {
                      // 拖动/捏合抬手后会误触发单击，用移动护栏挡掉，避免误退出
                      if (this.movedDuringTouch) {
                        return;
                      }
                      this.onClose();
                    })
                )
              )
            )
        }, (item: ViewerImage, index: number) => `${index}`)
      }
      .index(this.swiperIndex)
      .loop(false)
      .indicator(false)
      .disableSwipe(this.imgScale > MIN_SCALE)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        console.info(`[ArkDO][ImageViewer] Swiper onChange index=${index} imgScale=${this.imgScale.toFixed(2)}`);
        this.currentIndex = index;
        this.swiperIndex = index;
        this.resetTransform('swiperChange');
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
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.viewW = newValue.width as number;
      this.viewH = newValue.height as number;
    })
  }

  // 跟踪单次触摸是否移动过：按下清零，移动超阈值或出现多指即置位。
  // 供单击关闭判断，避免拖动/捏合抬手后被误判成点击而退出。
  private trackTouchMovement(event: TouchEvent): void {
    const touches: TouchObject[] = event.touches;
    if (event.type === TouchType.Down) {
      this.movedDuringTouch = false;
      if (touches && touches.length > 0) {
        this.touchDownX = touches[0].x;
        this.touchDownY = touches[0].y;
      }
    } else if (event.type === TouchType.Move) {
      if (touches && touches.length > 1) {
        this.movedDuringTouch = true;
        return;
      }
      if (touches && touches.length > 0) {
        const dx: number = Math.abs(touches[0].x - this.touchDownX);
        const dy: number = Math.abs(touches[0].y - this.touchDownY);
        if (dx > 8 || dy > 8) {
          this.movedDuringTouch = true;
        }
      }
    }
  }

  private handleDoubleTap(event: GestureEvent): void {
    // 快速连续拖动会被误判成双击（两次紧邻触摸），本次触摸移动过就不当双击，避免拖动中途误复位
    if (this.movedDuringTouch) {
      console.info(`[ArkDO][ImageViewer] DoubleTap suppressed (moved)`);
      return;
    }
    if (this.imgScale > MIN_SCALE) {
      this.resetTransform('doubleTapReset');
      return;
    }
    // 以双击点为中心放大
    let tapX: number = this.viewW / 2;
    let tapY: number = this.viewH / 2;
    if (event.fingerList && event.fingerList.length > 0 && event.fingerList[0]) {
      tapX = event.fingerList[0].localX;
      tapY = event.fingerList[0].localY;
    }
    const fx: number = tapX - this.viewW / 2;
    const fy: number = tapY - this.viewH / 2;
    this.imgScale = DOUBLE_TAP_SCALE;
    this.offsetX = fx * (1 - DOUBLE_TAP_SCALE);
    this.offsetY = fy * (1 - DOUBLE_TAP_SCALE);
    this.clampOffset();
    console.info(`[ArkDO][ImageViewer] DoubleTap zoom-in imgScale=${this.imgScale}`);
  }

  // 限制平移范围，避免把图拖出屏幕
  private clampOffset(): void {
    const maxX: number = this.viewW * (this.imgScale - 1) / 2;
    const maxY: number = this.viewH * (this.imgScale - 1) / 2;
    this.offsetX = this.clamp(this.offsetX, -maxX, maxX);
    this.offsetY = this.clamp(this.offsetY, -maxY, maxY);
  }

  private resetTransform(reason: string): void {
    console.info(`[ArkDO][ImageViewer] resetTransform reason=${reason} imgScaleWas=${this.imgScale.toFixed(2)}`);
    this.imgScale = MIN_SCALE;
    this.offsetX = 0;
    this.offsetY = 0;
    this.baseScale = MIN_SCALE;
    this.baseOffsetX = 0;
    this.baseOffsetY = 0;
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

  private clamp(value: number, min: number, max: number): number {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  private clampScale(value: number): number {
    return this.clamp(value, MIN_SCALE, MAX_SCALE);
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
