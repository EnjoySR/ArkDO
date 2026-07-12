import { AcceptedAnswer } from '../../models/TopicDetail';
import { User } from '../../models/User';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { APP_IS_DARK_STORAGE_KEY } from '../../common/theme/ThemeManager';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { PostRichContent } from './PostRichContent';
import { ViewerImage } from './ImageViewer';
import { UserAvatar } from './UserAvatar';

// 展开态正文最大高度:超出即裁剪并在底部渐隐,配合「阅读更多」引导跳楼看全文。
const CONTENT_MAX_HEIGHT: number = 260;
// 底部渐隐遮罩高度。
const FADE_HEIGHT: number = 56;

// discourse-solved 采纳答案面板:一楼正文下方渲染「已解决」卡片。
// 数组多解 → 铺多张卡片,每张卡片自持折叠态(自身 @State 驱动显隐,不依赖父级 deep 变更)。
@Component
export struct AcceptedAnswerPanel {
  answers: AcceptedAnswer[] = [];
  onJumpToPost: (postNumber: number) => Promise<void> = () => Promise.resolve();
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onResolveMedia: (url: string) => Promise<string> = () => Promise.reject(new Error('媒体下载未接入'));

  build() {
    if (this.answers.length > 0) {
      Column() {
        ForEach(this.answers, (answer: AcceptedAnswer) => {
          AcceptedAnswerCard({
            answer: answer,
            onJumpToPost: this.onJumpToPost,
            onOpenImages: this.onOpenImages,
            onOpenLink: this.onOpenLink,
            onResolveMedia: this.onResolveMedia
          })
            .margin({ top: 12 })
        }, (answer: AcceptedAnswer) => `${answer.postNumber}`)
      }
      .width('100%')
      .margin({ top: 12 })
    }
  }
}

@Component
struct AcceptedAnswerCard {
  // 渐隐终点需用「同色系零透明度」而非 Color.Transparent(透明黑会过路灰),故按主题取具体卡底色。
  @StorageProp(APP_IS_DARK_STORAGE_KEY) private ln: boolean = false;
  // 折叠态:自身 @State 驱动显隐才稳(纯父级传入的 deep 变更重渲染不可靠)。默认展开。
  @State private collapsed: boolean = false;
  answer: AcceptedAnswer = new AcceptedAnswer();
  onJumpToPost: (postNumber: number) => Promise<void> = () => Promise.resolve();
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onResolveMedia: (url: string) => Promise<string> = () => Promise.reject(new Error('媒体下载未接入'));

  build() {
    Column() {
      // 绿色「已解决」标题条:通栏铺满卡片顶部,圆角只在顶部两角。
      Row() {
        FaIconView({ icon: this.faIcon('square-check'), color: '#FFFFFF', iconSize: 18 })
          .margin({ right: 8 })
        Text('已解决')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.ld_success'))
      .borderRadius({ topLeft: 8, topRight: 8 })

      // 作者条:整条可点,切换折叠;右侧箭头随态翻转。
      Row() {
        UserAvatar({ user: this.buildUser(), avatarSize: 32 })
          .margin({ right: 10 })
        Text(this.answer.username)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        Text('·')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 8, right: 8 })
        Text(RelativeTime.fromNow(this.answer.createdAt))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .flexShrink(0)
        Blank()
        // 展开(chevron-up)/收起(chevron-down)分别用独立实例:复用同一实例只换 icon 属性不可靠。
        if (this.collapsed) {
          FaIconView({ icon: this.faIcon('chevron-down'), color: $r('app.color.icon_muted'), iconSize: 14 })
        } else {
          FaIconView({ icon: this.faIcon('chevron-up'), color: $r('app.color.icon_muted'), iconSize: 14 })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .onClick(() => {
        this.collapsed = !this.collapsed;
      })

      // 展开体:正文裁剪 + 底部渐隐 + 「阅读更多」跳楼。
      if (!this.collapsed) {
        Column() {
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              PostRichContent({
                cookedHtml: this.answer.cookedHtml,
                fallbackText: '',
                onOpenImages: this.onOpenImages,
                onOpenLink: this.onOpenLink,
                onResolveMedia: this.onResolveMedia,
                polls: []
              })
                .width('100%')
            }
            .width('100%')
            .constraintSize({ maxHeight: CONTENT_MAX_HEIGHT })
            .clip(true)
            .alignItems(HorizontalAlign.Start)

            // 底部渐隐:透明→卡底色,提示正文被裁。
            Column()
              .width('100%')
              .height(FADE_HEIGHT)
              .linearGradient({
                angle: 180,
                colors: this.fadeColors()
              })
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')

          Text('阅读更多')
            .fontSize(15)
            .fontColor($r('app.color.ld_accent'))
            .margin({ top: 12 })
            .onClick(() => {
              this.onJumpToPost(this.answer.postNumber);
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(8)
    .border({ width: 1, color: $r('app.color.border') })
    .clip(true)
    .alignItems(HorizontalAlign.Start)
  }

  // 渐隐色:同色系零透明度 → 不透明卡底色(#00 起点避开 Color.Transparent 的过路灰)。
  private fadeColors(): [ResourceColor, number][] {
    return this.ln
      ? [['#001F2228', 0.0], ['#FF1F2228', 1.0]]
      : [['#00FFFFFF', 0.0], ['#FFFFFFFF', 1.0]];
  }

  private buildUser(): User {
    return {
      id: 0,
      username: this.answer.username,
      avatarTemplate: this.answer.avatarTemplate
    };
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }
}
