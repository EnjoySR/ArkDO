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

// discourse-solved 采纳答案面板:一楼正文下方渲染「已解决」框。
// 对齐网页端——整框只有一条绿「已解决」标题(多解时附「· N 个方案」),下面 ForEach 铺多张精简卡
// (作者条+正文+阅读更多),卡间发丝线分隔;每卡自持折叠态(自身 @State 驱动才稳)。
@Component
export struct AcceptedAnswerPanel {
  answers: AcceptedAnswer[] = [];
  onJumpToPost: (postNumber: number) => Promise<void> = () => Promise.resolve();
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onResolveMedia: (url: string) => Promise<string> = () => Promise.reject(new Error('媒体下载未接入'));
  // 答案正文里的引用卡展开/跳转,与正常楼层一致透传;缺则 PostRichContent 落空实现,展开转圈即消失、跳转无反应。
  onJumpToQuote: (topicId: number, postNumber: number, fallbackUrl: string) => void = () => {};
  onResolveQuotedPost: (topicId: number, postNumber: number) => Promise<string> = () => Promise.resolve('');

  build() {
    if (this.answers.length > 0) {
      Column() {
        // 绿色「已解决」标题条:整框只此一条;多解附「· N 个方案」。顶部圆角交给外层 clip。
        Row() {
          FaIconView({ icon: this.faIcon('square-check'), color: '#FFFFFF', iconSize: 18 })
            .margin({ right: 8 })
          Text('已解决')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
          if (this.answers.length > 1) {
            Text(`· ${this.answers.length} 个方案`)
              .fontSize(13)
              .fontColor('#D9FFFFFF')
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.ld_success'))

        // 多解:每个答案一张精简卡;index>0 顶部发丝线分隔。
        ForEach(this.answers, (answer: AcceptedAnswer, index: number) => {
          AcceptedAnswerCard({
            answer: answer,
            showDivider: index > 0,
            // 首个方案默认展开、其余默认收起(多解不刷屏,主答案仍立即可见)。
            initiallyCollapsed: index > 0,
            onJumpToPost: this.onJumpToPost,
            onOpenImages: this.onOpenImages,
            onOpenLink: this.onOpenLink,
            onResolveMedia: this.onResolveMedia,
            onJumpToQuote: this.onJumpToQuote,
            onResolveQuotedPost: this.onResolveQuotedPost
          })
        }, (answer: AcceptedAnswer) => `${answer.postNumber}`)
      }
      .width('100%')
      .margin({ top: 12 })
      .backgroundColor($r('app.color.surface_card'))
      .borderRadius(8)
      .border({ width: 1, color: $r('app.color.border') })
      .clip(true)
      .alignItems(HorizontalAlign.Start)
    }
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }
}

// 单个答案精简卡:无绿条、无外壳(框壳由 Panel 持有),仅作者条 + 展开体;卡间靠顶部发丝线分隔。
@Component
struct AcceptedAnswerCard {
  // 渐隐终点需用「同色系零透明度」而非 Color.Transparent(透明黑会过路灰),故按主题取具体卡底色。
  @StorageProp(APP_IS_DARK_STORAGE_KEY) private ln: boolean = false;
  // 折叠态:自身 @State 驱动显隐才稳(纯父级传入的 deep 变更重渲染不可靠)。
  @State private collapsed: boolean = false;
  answer: AcceptedAnswer = new AcceptedAnswer();
  // 是否在卡顶画分隔线:多解时非首卡为 true,与上一张答案隔开。
  showDivider: boolean = false;
  // 进场初始折叠态(方案 B:首卡展开、其余收起)。不在字段初始化器里引用它(按值捕获会拿默认值),
  // 改在 aboutToAppear 落到 collapsed。
  initiallyCollapsed: boolean = false;
  onJumpToPost: (postNumber: number) => Promise<void> = () => Promise.resolve();
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onResolveMedia: (url: string) => Promise<string> = () => Promise.reject(new Error('媒体下载未接入'));
  onJumpToQuote: (topicId: number, postNumber: number, fallbackUrl: string) => void = () => {};
  onResolveQuotedPost: (topicId: number, postNumber: number) => Promise<string> = () => Promise.resolve('');

  aboutToAppear(): void {
    this.collapsed = this.initiallyCollapsed;
  }

  build() {
    Column() {
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
        // 单实例定向旋转:collapsed 时转 180° 朝下(固定 icon 只转不换,规避复用实例换 icon 属性不可靠);
        // 旋转随下方 animateTo 平滑补间。
        FaIconView({ icon: this.faIcon('chevron-up'), color: $r('app.color.icon_muted'), iconSize: 14 })
          .rotate({ angle: this.collapsed ? 180 : 0 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .onClick(() => {
        // 折叠切换裹进 animateTo:箭头旋转 + 展开体入退场 transition + 下方楼层回流,一次协调播完。
        this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
          this.collapsed = !this.collapsed;
        });
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
                onJumpToQuote: this.onJumpToQuote,
                onResolveQuotedPost: this.onResolveQuotedPost,
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
        // 入场:淡入 + 从上方 8px 下滑就位;退场对称(上滑淡出)。由外层 animateTo 驱动播放。
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: -8 }))
          .animation({ duration: 250, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 卡间发丝线:非首卡顶部一条,与上一答案隔开(框壳边框由 Panel 持有)。
    .border({ width: { top: this.showDivider ? 1 : 0 }, color: $r('app.color.border') })
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
