// 右缘楼层 scrubber(Discourse timeline 风):竖向 Slider 直接拖动跳楼。
// 用原生 Slider 而非手写手势——拖动→值映射框架托管,已填充段天然表达阅读进度。
// 顶=1 楼(最早),拖动时左侧气泡实时显示目标楼号,松手上抛跳楼。

// 轨道盒宽度:远宽于滑块本身,给气泡留足单行空间(气泡是盒内 position 子节点,宽度受父盒约束)。
// 空白区靠 hitTestBehavior(Transparent) 放行触摸,只有右缘 Slider 拦截拖动。
const SCRUBBER_STACK_WIDTH: number = 200;

@Component
export struct TopicScrubber {
  // 当前视口楼号(父组件 onScrollIndex 持续下发)。非拖动态时经 @Watch 同步进 sliderValue,
  // 让滑块跟随阅读位置;拖动/跳楼加载期间不跟随,避免把滑块拽走。
  @Prop @Watch('syncFromCurrent') currentPostNumber: number = 1;
  // 话题最高楼号 = Slider 上限;<= 1 时无从拖动,父组件不应挂载本组件。变更时重新钳位。
  @Prop @Watch('syncFromCurrent') highestPostNumber: number = 1;
  // 拖动结束(松手/点击轨道)上抛目标楼号,由父组件走 jumpToPostNumber 定位。
  // 返回 Promise:已加载楼瞬间 resolve,未加载楼 await 完 rewindow 才 resolve——
  // scrubber 据此决定 loading 何时消失,不再靠猜视口楼号(那会在目标已在屏时空等超时)。
  onJump: (postNumber: number) => Promise<void> = () => Promise.resolve();

  // 拖动态:轨道随手指走。
  @State private dragging: boolean = false;
  // 跳转态:松手后到 onJump 的 Promise resolve 前的加载窗口。未加载楼要走后台重开窗口
  // (rewindow),可能耗时一两秒且加载胶囊被产品关掉——期间保持滑块高亮 + 气泡"跳转到 N 楼",
  // 否则用户会以为松手没反应。已加载楼 Promise 立即 resolve,几乎不显示 loading。
  @State private jumping: boolean = false;
  private jumpTarget: number = 0;
  private jumpTimerId: number = -1;
  // Slider 当前值(唯一受控源)。拖动时随手指走;松手后停在目标楼——绝不立即弹回当前楼号,
  // 否则跳到未加载楼时后台还在异步拉取,滑块却已弹回 1 楼,看起来"松手没反应"。
  // 待内容真正加载完、父组件推高 currentPostNumber,syncFromCurrent 才把它平移到落点。
  @State private sliderValue: number = 1;
  // 轨道盒实测像素高(onAreaChange 写入):气泡贴手柄要按它把 sliderValue 换算成纵坐标。
  @State private trackHeightPx: number = 0;

  aboutToAppear(): void {
    this.sliderValue = this.clamp(this.currentPostNumber);
  }

  aboutToDisappear(): void {
    this.clearJumpTimer();
  }

  // currentPostNumber / highestPostNumber 变更回调:仅非拖动/非跳转态才把滑块同步到当前楼号。
  // 跳转态由 onJump 的 Promise 收尾(见 onChange),这里不掺和,避免中途视口楼号把滑块拽走。
  private syncFromCurrent(): void {
    if (this.dragging || this.jumping) {
      return;
    }
    this.sliderValue = this.clamp(this.currentPostNumber);
  }

  build() {
    // 满屏透明覆盖层(满高):只在右缘 Slider 处拦截触摸,其余放行给 List 滚动。
    // 满高 + alignItems Center 让滑块在屏幕垂直居中(根节点若只有 55% 高,会被父 Stack
    // 的 BottomEnd 对齐贴到底部——这是之前"滑块靠下"的根因)。
    Row() {
      // 轨道盒:Slider 与气泡同处一个 Stack,气泡按手柄 Y 绝对定位,才能贴着手柄上下走。
      // 盒子加宽(SCRUBBER_STACK_WIDTH)给气泡留单行空间;Slider 靠 alignContent End 贴右缘。
      // onAreaChange 量到轨道实际像素高,供 thumbCenterY 换算手柄纵坐标。
      Stack({ alignContent: Alignment.End }) {
        Slider({
          value: this.sliderValue,
          min: 1,
          max: Math.max(2, this.highestPostNumber),
          step: 1,
          direction: Axis.Vertical,
          // 顶部=1 楼(最早),底部=最高楼:往上滑趋近 1 楼,与阅读顺序一致。
          reverse: false
        })
          .width(this.isActive() ? 32 : 24)
          .height('100%')
          // 滑块换成竖向圆角长条(timeline 手柄感),而非默认小圆。
          .blockStyle({ type: SliderBlockType.SHAPE, shape: new Rect({ width: 6, height: 28, radius: 3 }) })
          .blockSize({ width: 6, height: 28 })
          // 长条手柄用未读小蓝点同色(#66CCFF,见 TopicListItem 未读徽标/蓝点)。
          .blockColor('#66CCFF')
          .trackColor(this.isActive() ? '#C7CED8' : '#D1D5DB')
          // 已填充段(顶→当前)与未填充段同色:整条轨道统一,不显进度深浅,只有长条手柄在动。
          .selectedColor(this.isActive() ? '#C7CED8' : '#D1D5DB')
          .trackThickness(this.isActive() ? 5 : 3)
          .showTips(false)
          .opacity(this.isActive() ? 1 : 0.55)
          .onChange((value: number, mode: SliderChangeMode) => {
            const v: number = Math.round(value);
            // 受控值始终跟手,避免中途重渲染把滑块拽离手指(拖动断触的常见根因)。
            this.sliderValue = v;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              // 松手:保持 sliderValue 停在 v(不弹回),进入跳转态并上抛。
              // loading 何时消失完全跟随 onJump 的 Promise:已加载楼立即 resolve→几乎不闪 loading;
              // 未加载楼拉完 rewindow 才 resolve→loading 恰好覆盖等待期。resolve/reject 都收尾。
              this.dragging = false;
              this.beginJump(v);
              this.onJump(v).then(() => this.endJump(), () => this.endJump());
            } else {
              this.dragging = true;
            }
          })

        // 拖动/跳转中的气泡:right-center 锚点贴到手柄左侧、纵坐标对齐手柄中心。跳转态内联 loading。
        if (this.dragging || this.jumping) {
          Row() {
            if (this.jumping) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color('#FFFFFF')
                .margin({ right: 6 })
            }
            Text(this.jumping ? `跳转到 ${this.jumpTarget} 楼` : `${this.sliderValue} 楼`)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
          }
          // 盒子已够宽,气泡按内容自然撑开、单行不换行(不再估算宽度)。
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#2563EB')
          .borderRadius(16)
          .shadow({ radius: 8, color: '#33000000', offsetX: 0, offsetY: 2 })
          // 气泡右-中锚点落在 Slider 左侧一点、手柄中心高度处 → 气泡整体浮在手柄左边、与之等高。
          .markAnchor({ x: '100%', y: '50%' })
          .position({ x: this.bubbleAnchorX(), y: this.thumbCenterY() })
        }
      }
      .width(SCRUBBER_STACK_WIDTH)
      .height('55%')
      // Slider 轨道在自身宽度里居中,右侧留半个宽度空档;正向 offset 把长条整体推到贴右缘。
      .offset({ x: 8 })
      // 加宽后空白区不该挡列表滚动:整盒放行触摸,只有 Slider 子节点在右缘拦截拖动。
      .hitTestBehavior(HitTestMode.Transparent)
      .onAreaChange((_o: Area, area: Area) => {
        this.trackHeightPx = area.height as number;
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    // 贴紧右缘(原来留 4 的内边距,现在往右靠)。
    .padding({ right: 0 })
    // 覆盖层本身不吃触摸,滚动照常穿透;只有 Slider 子节点在右缘拦截拖动。
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 气泡右-中锚点的横坐标(相对轨道盒左上角,vp):落在 Slider 左缘再往左留 10vp 间隙。
  // Slider 靠右对齐,其左缘 = 盒宽 − 滑块宽。
  private bubbleAnchorX(): number {
    const sliderW: number = this.isActive() ? 32 : 24;
    return SCRUBBER_STACK_WIDTH - sliderW - 10;
  }

  // 手柄中心相对轨道盒顶部的纵坐标(vp)。reverse:false 下 value=1 在顶、=max 在底;
  // 手柄中心行程约 [block/2, H-block/2],据填充比例 f 线性插值。
  private thumbCenterY(): number {
    const block: number = 28;
    const H: number = this.trackHeightPx;
    if (H <= block) {
      return H / 2;
    }
    const max: number = Math.max(2, this.highestPostNumber);
    let f: number = (this.clamp(this.sliderValue) - 1) / (max - 1);
    if (f < 0) {
      f = 0;
    }
    if (f > 1) {
      f = 1;
    }
    return block / 2 + f * (H - block);
  }

  private isActive(): boolean {
    return this.dragging || this.jumping;
  }

  // 进入跳转态:记目标楼,武装超时兜底(跳转失败/落地事件没来时也能复位,避免卡在高亮)。
  private beginJump(target: number): void {
    this.jumpTarget = target;
    this.jumping = true;
    this.clearJumpTimer();
    this.jumpTimerId = setTimeout(() => {
      this.endJump();
    }, 5000);
  }

  private endJump(): void {
    this.jumping = false;
    this.clearJumpTimer();
  }

  private clearJumpTimer(): void {
    if (this.jumpTimerId >= 0) {
      clearTimeout(this.jumpTimerId);
      this.jumpTimerId = -1;
    }
  }

  // 楼号钳进 [1, max],避免刚进页/越界时 Slider 越限。
  private clamp(postNumber: number): number {
    const max: number = Math.max(2, this.highestPostNumber);
    if (postNumber < 1) {
      return 1;
    }
    if (postNumber > max) {
      return max;
    }
    return postNumber;
  }
}
