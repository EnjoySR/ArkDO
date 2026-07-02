import { AppConstants } from '../../common/constants/AppConstants';

@Component
export struct CfChallengePage {
  build() {
    Column() {
      Text('Cloudflare 验证')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')

      Text(AppConstants.CHALLENGE_URL)
        .fontSize(14)
        .fontColor('#4B5563')
        .margin({ top: 12 })

      Text('第一阶段仅保留可见验证页入口，真实 ArkWeb 验证流程在后续阶段接入。')
        .fontSize(14)
        .fontColor('#6B7280')
        .margin({ top: 20 })
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }
}
