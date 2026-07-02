import { AppConstants } from '../../common/constants/AppConstants';

@Component
export struct HomePage {
  private featureEntries: string[] = [
    '帖子列表：第二阶段接入',
    'ArkWeb 登录：后续接入',
    'Cloudflare 验证：可见页面接入'
  ];

  build() {
    Column() {
      Row() {
        Text(AppConstants.APP_NAME)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 12 })

      Column() {
        Text('架构骨架已就绪')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')

        Text('第一阶段仅准备原生页面、服务边界和验证页结构，不访问 Linux.do。')
          .fontSize(14)
          .fontColor('#4B5563')
          .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .backgroundColor('#F3F4F6')

      Column() {
        ForEach(this.featureEntries, (item: string) => {
          Row() {
            Text(item)
              .fontSize(16)
              .fontColor('#111827')
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .margin({ bottom: 10 })
        }, (item: string) => item)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }
}
