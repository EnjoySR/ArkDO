@Component
export struct WebContainerPage {
  build() {
    Column() {
      Text('Web 容器')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')

      Text('第一阶段不承载真实 ArkWeb 请求。')
        .fontSize(14)
        .fontColor('#6B7280')
        .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }
}
