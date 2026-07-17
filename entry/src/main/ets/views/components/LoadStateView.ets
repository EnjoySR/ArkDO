import { ChallengeRecoveryEventBus, ChallengeRecoveryState } from '../../services/challenge/ChallengeRecoveryEventBus';

// 静默过验中"手动验证"按钮的延迟出现时间:保护快乐路径(通常几秒就静默过了),
// 别让用户第一时间就把自己拽进全屏验证页。与首页空态保持一致。
const MANUAL_VERIFY_DELAY_MS: number = 6000;

// 页面级加载/失败/无数据/CF 挑战统一占位:居中渲染,四态互斥。全项目二级页的列表空态都走这一个组件,
// 不再各写一套。四态优先级:requiresChallenge(CF 挑战)> isLoading(加载中)> showRetry(失败可重试)> 无数据。
// - requiresChallenge:接管全局 CF 恢复状态,后台静默过验中转圈+提示,静默数秒才放出"手动验证";终态直接给手动入口。
//   恢复成功由页面各自订阅 SessionEventBus 自动重载,组件不介入数据加载。
// - 无数据态:可选圆环图标 emptyIcon + 主标题 emptyTitle + 可选副标题 emptySubtitle;三者皆空时回退显示 message。
// 配色统一 ld_accent(#0088CC 站点青蓝)+ fill_subtle 浅底。
@Component
export struct LoadStateView {
  @Prop isLoading: boolean = false;
  // 失败态文案(也作加载/无数据态的兜底文案)。加载态优先用 loadingText。
  @Prop message: string = '';
  // 加载中文案(可选)。列表页"加载中…"与失败文案不同,用它区分;缺省回退 message。
  @Prop loadingText: string = '';
  @Prop requiresChallenge: boolean = false;
  // 是否显示重试按钮(由父页面判定,如加载失败且网络环境就绪)。仅非挑战态生效;挑战态由恢复状态自行决定按钮。
  @Prop showRetry: boolean = false;
  // 无数据态:可选圆环图标(sys.symbol 资源)+ 主标题 + 可选副标题。
  @Prop emptyIcon?: Resource = undefined;
  @Prop emptyTitle: string = '';
  @Prop emptySubtitle: string = '';
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
      .fontColor($r('app.color.ld_accent'))
      .backgroundColor($r('app.color.fill_subtle'))
      .height(38)
      .padding({ left: 18, right: 18 })
      .borderRadius(19)
      .margin({ top: 16 })
      .onClick(() => {
        this.onManualVerify();
      })
  }

  // 无数据态:圆环图标(可选)+ 主标题 + 副标题(可选);无主标题时回退显示 message。
  @Builder
  EmptyContent() {
    if (this.emptyIcon) {
      Column() {
        SymbolGlyph(this.emptyIcon)
          .fontSize(30)
          .fontColor([$r('app.color.text_faint')])
      }
      .width(66)
      .height(66)
      .borderRadius(33)
      .border({ width: 1, color: $r('app.color.border') })
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 16 })
    }

    if (this.emptyTitle.length > 0) {
      Text(this.emptyTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)

      if (this.emptySubtitle.length > 0) {
        Text(this.emptySubtitle)
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
          .padding({ left: 40, right: 40 })
      }
    } else {
      Text(this.message)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
  }

  build() {
    Column() {
      if (this.requiresChallenge) {
        // 挑战态:后台静默过验中 / 终态未完成(升级弹窗被关掉未通过)。
        if (this.recoveryState === ChallengeRecoveryState.RESOLVING) {
          LoadingProgress()
            .width(30)
            .height(30)
            .color($r('app.color.ld_accent'))
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
      } else if (this.isLoading) {
        LoadingProgress()
          .width(30)
          .height(30)
          .color($r('app.color.ld_accent'))
          .margin({ bottom: 12 })

        Text(this.loadingText.length > 0 ? this.loadingText : this.message)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      } else if (this.showRetry) {
        Text(this.message)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)

        Button('重试')
          .fontSize(15)
          .fontColor($r('app.color.ld_accent'))
          .backgroundColor($r('app.color.fill_subtle'))
          .height(38)
          .padding({ left: 18, right: 18 })
          .borderRadius(19)
          .margin({ top: 16 })
          .onClick(() => {
            this.onRetry();
          })
      } else {
        this.EmptyContent()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24 })
  }
}
