// 分页列表的尾行:加载中转圈 + 「上拉加载更多 / 没有更多了」。
//
// 抽取前这 17 行在 6 个分页页面里逐字复制(其中 5 份完全一致)。
//
// isLoading / hasMore 必须是 @Prop:普通成员只在构造时赋值一次,父页翻 @State 时
// 尾行不会重绘——转圈会一直转下去、"没有更多了"也永远不出现。
@Component
export struct ListFooter {
  @Prop isLoading: boolean = false;
  @Prop hasMore: boolean = true;
  // 到底时的文案。通知页历史上用的是「已到底」,与其余页不同;
  // 属用户可见文案,抽取时原样保留,未擅自统一。
  endText: string = '没有更多了';
  accentColor: Resource = $r('app.color.ld_accent');
  textColor: Resource = $r('app.color.text_faint');

  build() {
    Row() {
      if (this.isLoading) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.accentColor)
          .margin({ right: 8 })
      }
      Text(this.hasMore ? '上拉加载更多' : this.endText)
        .fontSize(13)
        .fontColor(this.textColor)
    }
    .width('100%')
    .height(54)
    .justifyContent(FlexAlign.Center)
  }
}
