import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';

// 顶栏通知铃铛:有未读时显示实心铃铛 + 红色数字 Badge,并做"间歇式摇铃"动画;
// 无未读时铃铛常驻(切描边静默态)、不挂红点、不晃动。点击回调交由外部接入通知页。
const BELL_COLOR: string = '#F5A623';   // 铃铛统一用琥珀色实心;有无未读只以"红点+晃动"区分
const BADGE_COLOR: string = '#F5222D';         // 红点/数字底色
const SHAKE_PAUSE_MS: number = 3200;           // 每轮摇铃之间的停顿(间歇式,避免持续晃动的疲劳感)

@Component
export struct NotificationBell {
  @Prop @Watch('onUnreadChanged') unreadCount: number = 0;
  onBellClick: () => void = () => {};

  // 铃铛当前旋转角(度)。绕顶部支点摆动 = 摇铃观感。
  @State private bellAngle: number = 0;
  // 是否处于摇铃循环中。用作 start/stop 的门闩,让无限循环可被随时中止。
  private shaking: boolean = false;

  aboutToDisappear(): void {
    // 组件销毁时中止循环:停顿中的 setTimeout 回调会因 shaking=false 提前返回。
    this.shaking = false;
  }

  // unreadCount 变化时:>0 启动摇铃,归 0 时停摆并复位角度。
  private onUnreadChanged(): void {
    if (this.unreadCount > 0) {
      this.startShake();
    } else {
      this.stopShake();
    }
  }

  build() {
    Button() {
      Badge({
        count: this.unreadCount,
        maxCount: 99,
        position: BadgePosition.RightTop,
        style: { badgeSize: 15, badgeColor: BADGE_COLOR, fontSize: 10, color: '#FFFFFF' }
      }) {
        // Stack 包一层,把 rotate 施加在内置容器上(自定义组件不能直接挂通用属性)。
        // 支点设在顶部中点(centerY:'0%'),摆动时铃口左右甩,才像挂着的铃铛在响。
        Stack() {
          FaIconView({
            icon: this.bellIcon(),
            color: BELL_COLOR,
            iconSize: 24
          })
        }
        .rotate({ angle: this.bellAngle, centerX: '50%', centerY: '0%' })
      }
    }
    .width(42)
    .height(42)
    .backgroundColor(Color.Transparent)
    .padding(0)
    .margin({ right: 4 })
    .onClick(() => {
      this.onBellClick();
    })
    .onAppear(() => {
      if (this.unreadCount > 0) {
        this.startShake();
      }
    })
  }

  private bellIcon(): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon('bell');
    return def ? def : { id: 'bell', rawfilePath: '' };
  }

  private startShake(): void {
    if (this.shaking) {
      return;
    }
    this.shaking = true;
    this.runShakeCycle();
  }

  private stopShake(): void {
    this.shaking = false;
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.bellAngle = 0;
    });
  }

  // 一轮阻尼摇铃:14° → -12° → 9° → -6° → 3° → 0°,幅度衰减像被拨动后的余震;
  // 结束后停顿 SHAKE_PAUSE_MS 再进入下一轮 = 间歇式,不会一直晃。
  private runShakeCycle(): void {
    if (!this.shaking) {
      return;
    }
    this.getUIContext().keyframeAnimateTo({
      iterations: 1,
      onFinish: () => {
        if (this.shaking) {
          setTimeout(() => {
            this.runShakeCycle();
          }, SHAKE_PAUSE_MS);
        }
      }
    }, [
      { duration: 110, curve: Curve.EaseInOut, event: () => { this.bellAngle = 14; } },
      { duration: 110, curve: Curve.EaseInOut, event: () => { this.bellAngle = -12; } },
      { duration: 100, curve: Curve.EaseInOut, event: () => { this.bellAngle = 9; } },
      { duration: 90, curve: Curve.EaseInOut, event: () => { this.bellAngle = -6; } },
      { duration: 80, curve: Curve.EaseInOut, event: () => { this.bellAngle = 3; } },
      { duration: 80, curve: Curve.EaseInOut, event: () => { this.bellAngle = 0; } }
    ]);
  }
}
