// 页面级加载/错误占位:居中的 spinner + 提示文案 + 可选重试按钮。
// requiresChallenge 时文案用警示色(等待 Cloudflare 挑战场景)。
@Component
export struct LoadStateView {
  @Prop isLoading: boolean = false;
  @Prop message: string = '';
  @Prop requiresChallenge: boolean = false;
  // 是否显示重试按钮(由父页面判定,如加载失败且网络环境就绪)。
  @Prop showRetry: boolean = false;
  onRetry: () => void = () => {};

  build() {
    Column() {
      if (this.isLoading) {
        LoadingProgress()
          .width(30)
          .height(30)
          .color('#2563EB')
          .margin({ bottom: 12 })
      }

      Text(this.message)
        .fontSize(15)
        .fontColor(this.requiresChallenge ? '#B45309' : '#6B7280')
        .textAlign(TextAlign.Center)

      if (this.showRetry) {
        Button('重试')
          .fontSize(15)
          .fontColor('#2563EB')
          .backgroundColor('#F3F4F6')
          .height(38)
          .padding({ left: 18, right: 18 })
          .borderRadius(19)
          .margin({ top: 16 })
          .onClick(() => {
            this.onRetry();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24 })
  }
}
