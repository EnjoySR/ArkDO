import { ChallengeRecoveryEventBus, ChallengeRecoveryState } from '../../services/challenge/ChallengeRecoveryEventBus';

// 静默过验中"手动验证"按钮的延迟出现时间:保护快乐路径(通常几秒就静默过了),
// 别让用户第一时间就把自己拽进全屏验证页。与首页空态保持一致。
const MANUAL_VERIFY_DELAY_MS: number = 6000;

// 页面级加载/错误占位:居中的 spinner + 提示文案 + 可选重试按钮。
// requiresChallenge 时接管全局 CF 恢复状态:后台静默过验中显示 spinner + 提示,静默数秒仍未过才放出
// "手动验证"入口;终态(升级弹窗被关掉未通过)直接给"手动验证"。恢复成功由页面各自订阅 SessionEventBus 自动重载,
// 组件不介入数据加载。任何二级页把加载空态换成本组件即可统一获得整套 CF 过验体验,无需各自重写。
@Component
export struct LoadStateView {
  @Prop isLoading: boolean = false;
  @Prop message: string = '';
  @Prop requiresChallenge: boolean = false;
  // 是否显示重试按钮(由父页面判定,如加载失败且网络环境就绪)。仅非挑战态生效;挑战态由恢复状态自行决定按钮。
  @Prop showRetry: boolean = false;
  onRetry: () => void = () => {};

  // 挑战恢复状态:驱动挑战占位在"后台静默过验中 / 终态未完成"两态间切换。
  @State private recoveryState: ChallengeRecoveryState = ChallengeRecoveryEventBus.getCurrentState();
  // 静默期"手动验证"按钮是否已延迟出现。
  @State private showManualVerify: boolean = false;
  private manualVerifyTimer: number = -1;
  private unsubscribeRecoveryState?: () => void = undefined;

  aboutToAppear(): void {
    if (!this.unsubscribeRecoveryState) {
      this.unsubscribeRecoveryState = ChallengeRecoveryEventBus.subscribeState((state: ChallengeRecoveryState) => {
        this.handleRecoveryStateChanged(state);
      });
    }
    // 挂载即处于静默过验态(挑战早于本页出现)时也要起延迟计时:订阅只回调后续迁移,初值需手动同步一次。
    this.handleRecoveryStateChanged(this.recoveryState);
  }

  aboutToDisappear(): void {
    if (this.unsubscribeRecoveryState) {
      this.unsubscribeRecoveryState();
      this.unsubscribeRecoveryState = undefined;
    }
    this.clearManualVerifyTimer();
  }

  // 挑战恢复状态迁移:进入静默态时延迟放出"手动验证"按钮;离开则清掉计时器并收起。
  private handleRecoveryStateChanged(state: ChallengeRecoveryState): void {
    this.recoveryState = state;
    if (state === ChallengeRecoveryState.RESOLVING) {
      this.showManualVerify = false;
      this.clearManualVerifyTimer();
      this.manualVerifyTimer = setTimeout(() => {
        this.manualVerifyTimer = -1;
        this.showManualVerify = true;
      }, MANUAL_VERIFY_DELAY_MS);
    } else {
      this.clearManualVerifyTimer();
      this.showManualVerify = false;
    }
  }

  // "手动验证"按钮:静默/空闲态请求协调器接管弹页;冷却态无活跃挑战,退化为普通重试(重载本页)。
  private onManualVerify(): void {
    if (this.recoveryState === ChallengeRecoveryState.COOLDOWN) {
      this.onRetry();
      return;
    }
    ChallengeRecoveryEventBus.requestManual();
  }

  private clearManualVerifyTimer(): void {
    if (this.manualVerifyTimer >= 0) {
      clearTimeout(this.manualVerifyTimer);
      this.manualVerifyTimer = -1;
    }
  }

  @Builder
  ManualVerifyButton() {
    Button('手动验证')
      .fontSize(15)
      .fontColor($r('app.color.brand'))
      .backgroundColor($r('app.color.fill_subtle'))
      .height(38)
      .padding({ left: 18, right: 18 })
      .borderRadius(19)
      .margin({ top: 16 })
      .onClick(() => {
        this.onManualVerify();
      })
  }

  build() {
    Column() {
      if (this.requiresChallenge) {
        // 挑战态:后台静默过验中 / 终态未完成(升级弹窗被关掉未通过)。
        if (this.recoveryState === ChallengeRecoveryState.RESOLVING) {
          LoadingProgress()
            .width(30)
            .height(30)
            .color($r('app.color.brand'))
            .margin({ bottom: 12 })

          Text('正在自动验证访问，请稍候…')
            .fontSize(15)
            .fontColor($r('app.color.warning'))
            .textAlign(TextAlign.Center)

          // 静默几秒仍未过才放出手动入口,避免把快乐路径提前拽进全屏验证页。
          if (this.showManualVerify) {
            this.ManualVerifyButton()
          }
        } else {
          Text('访问验证未完成')
            .fontSize(15)
            .fontColor($r('app.color.warning'))
            .textAlign(TextAlign.Center)

          this.ManualVerifyButton()
        }
      } else {
        if (this.isLoading) {
          LoadingProgress()
            .width(30)
            .height(30)
            .color($r('app.color.brand'))
            .margin({ bottom: 12 })
        }

        Text(this.message)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)

        if (this.showRetry) {
          Button('重试')
            .fontSize(15)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.fill_subtle'))
            .height(38)
            .padding({ left: 18, right: 18 })
            .borderRadius(19)
            .margin({ top: 16 })
            .onClick(() => {
              this.onRetry();
            })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24 })
  }
}
