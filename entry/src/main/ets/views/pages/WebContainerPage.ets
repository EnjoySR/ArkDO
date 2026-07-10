@Component
export struct WebContainerPage {
  build() {
    Column() {
      Text('Web 容器')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text('第一阶段不承载真实 ArkWeb 请求。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }
}
