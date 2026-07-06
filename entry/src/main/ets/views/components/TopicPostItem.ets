import { curves } from '@kit.ArkUI';
import { Poll, PollVoteResult, PostBoost, PostReaction, TopicPost } from '../../models/TopicDetail';
import { CookedHtmlParser, RichInlineNode, RichInlineType } from '../../services/content/CookedHtmlParser';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { ReactionMutation, ReactionSnapshot } from '../../services/topic/ReactionMutation';
import { getReactionEmoji, REACTION_ORDER } from './EmojiRegistry';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { PostRichContent } from './PostRichContent';
import { ViewerImage } from './ImageViewer';
import { UserAvatar } from './UserAvatar';

const LIKE_RED: string = '#EF4444';
const LIKE_GRAY: string = '#BDBDBD';

// 表情短名 + 已解析的本地资源(过滤未知表情后类型非空,供 Image 使用)。
interface ReactionIcon {
  id: string;
  icon: Resource;
}

// bindPopup onStateChange 回调事件(结构匹配 ArkUI 的 { isVisible: boolean })。
interface PopupStateEvent {
  isVisible: boolean;
}

@Component
export struct TopicPostItem {
  // @ObjectLink 绑定 @Observed 的 TopicPost:楼层 read 翻真时精准触发本组件重渲染,
  // 蓝点 opacity 过渡才会播放。由父组件 ForEach 传入,不能有默认值。
  @ObjectLink post: TopicPost;
  lastReadPostNumber: number = -1;
  // 图片浏览器在页面级渲染，这里把 PostRichContent 的「打开」请求继续上抛给页面
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  // 正文链接 / onebox 卡片点击继续上抛给页面(由页面经 LinkRouter 判断跳原生详情或通用 WebView)。
  onOpenLink: (url: string) => void = () => {};
  // 表情回应切换:本组件就地乐观更新 this.post(@ObjectLink 自身变更→精准重渲染),
  // 页面只负责发 PUT + 失败时用 snapshot 回滚。
  onToggleReaction: (post: TopicPost, reaction: string, snapshot: ReactionSnapshot) => void = () => {};
  // 点该楼回复按钮:把整条 post 上抛给页面,由页面按 postNumber+作者昵称打开定向回复输入框。
  onReply: (post: TopicPost) => void = () => {};
  // 点火箭:把整条 post 上抛给页面,由页面打开 boost 输入浮层。
  onAddBoost: (post: TopicPost) => void = () => {};
  // 投票/撤销:把整条 post 与目标 poll 上抛给页面做乐观闭环。返回服务端校正结果;null=失败。
  onVote: (post: TopicPost, poll: Poll, optionIds: string[]) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  onRemoveVote: (post: TopicPost, poll: Poll) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  // 点头部「回复别人」指示器 / 展开区「跳到帖子」:按 postNumber 上抛给页面滚动定位。
  onJumpToPost: (postNumber: number) => void = () => {};
  // 展开「被回复」时上抛给页面拉取列表(页面持有 bridge/TopicService);返回楼层数组,失败返回 null。
  onLoadReplies: (post: TopicPost) => Promise<TopicPost[] | null> = () => Promise.resolve(null);
  @State private showReactionPicker: boolean = false;
  // 被回复列表:展开态 / 加载态 / 已加载数据。按 memory objectlink-state-source,状态放本组件 @State
  // (而非 @Observed TopicPost 深层字段),重渲染才稳。
  @State private repliesExpanded: boolean = false;
  @State private repliesLoading: boolean = false;
  @State private replies: TopicPost[] = [];
  // 点赞按钮图标的弹簧缩放:每次切换回应时做一次 pop(先缩到 0.7,再用弹簧回弹到 1,带 overshoot)。
  @State private likeIconScale: number = 1;

  build() {
    ListItem() {
      Column() {
        this.PostAuthorHeader()

        PostRichContent({
          cookedHtml: this.post.cookedHtml,
          fallbackText: this.post.plainText,
          onOpenImages: this.onOpenImages,
          onOpenLink: this.onOpenLink,
          polls: this.post.polls ? this.post.polls : [],
          onVote: (poll: Poll, optionIds: string[]) => {
            return this.onVote(this.post, poll, optionIds);
          },
          onRemoveVote: (poll: Poll) => {
            return this.onRemoveVote(this.post, poll);
          }
        })
          .width('100%')
          .margin({ top: 12 })

        this.PostFooter()
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .border({
        width: { bottom: 1 },
        color: '#E5E7EB'
      })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private PostAuthorHeader() {
    Row() {
      UserAvatar({ user: this.post.author, avatarSize: 40 })
        .margin({ right: 12 })

      // 昵称在上,姓名 + 称号一行在下。
      Column() {
        Text(this.getAuthorName())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(this.getUsername())
            .fontSize(13)
            .fontColor('#9CA3AF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.hasUserTitle()) {
            Text(this.getUserTitle())
              .fontSize(13)
              .fontColor('#9CA3AF')
              .margin({ left: this.getUsername().length > 0 ? 6 : 0 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 「回复别人」指示器:本楼回复了某楼时,在时间左侧显示 share 图标 + 被回复者头像。
      // 点击整块 → 滚动定位到被回复的楼层。
      if (this.hasReplyTo()) {
        Row({ space: 4 }) {
          FaIconView({ icon: this.faIcon('share'), color: '#9CA3AF', iconSize: 16 })
          UserAvatar({ user: this.post.replyToUser, avatarSize: 20 })
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 8 })
        .onClick(() => {
          const target: number | undefined = this.post.replyToPostNumber;
          if (target !== undefined) {
            this.onJumpToPost(target);
          }
        })
      }

      // 右上角:时间,时间右边是未读小蓝点。
      Row() {
        Text(this.getRelativeTime())
          .fontSize(13)
          .fontColor('#9CA3AF')

        // 蓝点常驻占位:读后 opacity 1→0 渐隐(~1.2s),槽位保留,左侧时间不位移。
        Circle()
          .width(8)
          .height(8)
          .fill('#66CCFF')
          .margin({ left: 2 })
          .opacity(this.isPostRead() ? 0 : 1)
          .animation({ duration: 1200, curve: Curve.EaseInOut })
      }
      .alignItems(VerticalAlign.Center)
      .margin({ left: 8 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // 楼层底部页脚:大 Row = 左侧表情回应汇总 + 右侧操作入口;外层 Column 预留 boost 界面(TODO)。
  @Builder
  private PostFooter() {
    Column() {
      Row() {
        // 左组:表情回应汇总 + (被回复时)被回复数量入口。
        Row({ space: 12 }) {
          // 表情回应汇总(图标组 + 回应人数)。无回应时整块不渲染,否则空 Row 仍会占位 +
          // 触发左组 space 间距,导致被回复数量区左侧多出一段空白。
          if (this.hasReactions()) {
            Row({ space: 2 }){
              ForEach(this.getReactionIcons(), (item: ReactionIcon) => {
                Image(item.icon)
                  .width(16)
                  .height(16)
                  .objectFit(ImageFit.Contain)
              }, (item: ReactionIcon) => item.id)

              Text(`${this.post.reactionUsersCount}`)
                .fontSize(16)
                .fontColor('#BDBDBD')
                .margin({ left: 8 })
            }
            .alignItems(VerticalAlign.Center)
          }

          // 被回复数量 + chevron:点击展开/收起本楼的被回复列表。
          if (this.hasReplies()) {
            Row({ space: 4 }) {
              Text(`${this.post.replyCount}`)
                .fontSize(16)
                .fontColor('#BDBDBD')
              // 加载中在按钮上就地转圈(替换 chevron);加载成功后才展开列表。
              // chevron 用结构化 if/else 分别渲染:ArkUI 对子组件对象类型属性的 diff 更新不可靠,
              // 若复用同一 FaIconView 只换 icon 属性,收起时箭头不会翻回向下(见 objectlink-state-source)。
              if (this.repliesLoading) {
                LoadingProgress()
                  .width(14)
                  .height(14)
                  .color('#BDBDBD')
              } else if (this.repliesExpanded) {
                FaIconView({ icon: this.faIcon('chevron-up'), color: '#BDBDBD', iconSize: 14 })
              } else {
                FaIconView({ icon: this.faIcon('chevron-down'), color: '#BDBDBD', iconSize: 14 })
              }
            }
            .alignItems(VerticalAlign.Center)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            // 展开时用更深的 #E9E9E9 作为"已激活"态,收起时用较浅的 #F3F4F6。
            .backgroundColor(this.repliesExpanded ? '#E9E9E9' : '#F3F4F6')
            .borderRadius(4)
            .onClick(() => {
              this.toggleReplies();
            })
          }
        }
        .alignItems(VerticalAlign.Center)

        // 右:操作入口 —— 点赞/回应按钮 + (无 boost 时)火箭 + 回复按钮
        // 火箭放置规则:本楼还没有别人的 boost 时,火箭入口跟随在这里、位于回复按钮左边;
        // 一旦本楼已有 boost,火箭改到 boost 列表末尾(见 BoostRow),此处不再显示。
        Row() {
          this.LikeButton()
          if (this.canAddBoost() && !this.hasBoosts()) {
            this.RocketButton(38, 0)
          }
          this.ReplyButton()
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      // 本楼已有 boost 时:头像+短文本气泡排,末尾接火箭入口。
      if (this.hasBoosts()) {
        this.BoostRow()
      }

      // 被回复列表展开区。
      if (this.repliesExpanded) {
        this.RepliesSection()
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  // 被回复列表:竖线 + 逐条精简项(头像40 + 昵称/用户名 + 正文 + 跳到帖子),底部收起按钮。
  // 竖线用 background 绘制在内容列背后(见 ReplyThreadLine),随内容高度自适应;头像/收起按钮
  // 不透明,会盖在线上面,只在竖直空隙露出连接线段(经典 Discourse 楼层连接线观感)。
  @Builder
  private RepliesSection() {
    Column() {
        ForEach(this.replies, (reply: TopicPost, index: number) => {
            Column() {
              // 上部:头像 + 昵称/用户名 + 正文。
              Row() {
                UserAvatar({ user: reply.author, avatarSize: 40 })
                  .margin({ right: 12 })

                Column() {
                  // 昵称 + 用户名一行。
                  Row({ space: 6 }) {
                    Text(this.replyAuthorName(reply))
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#111827')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (this.replyUsername(reply).length > 0) {
                      Text(this.replyUsername(reply))
                        .fontSize(13)
                        .fontColor('#9CA3AF')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }

                  PostRichContent({
                    cookedHtml: reply.cookedHtml,
                    fallbackText: reply.plainText,
                    onOpenImages: this.onOpenImages,
                    onOpenLink: this.onOpenLink
                  })
                    .width('100%')
                    .margin({ top: 6 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              // 底部条:跳到帖子(缩进对齐正文起点 x=52);仅最后一条回复在其左侧、贴竖线处放收起按钮。
              Row() {
                if (index === this.replies.length - 1) {
                  this.CollapseButton()
                }
                this.JumpToPost(reply)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 14 })
              .padding({ left: index === this.replies.length - 1 ? 0 : 52 })
            }
            .width('100%')
            .padding({ top: 12, bottom: 0})
          }, (reply: TopicPost) => reply.id.toString())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 竖线用 background 绘制:builder 以本组件自身尺寸为约束,height('100%') = 内容高度并自适应,
      // 不像 Stack 里的百分比高度会撑到父级视口高度导致底部大片空白。
      .background(this.ReplyThreadLine(), { align: Alignment.TopStart })
  }

  // 收起按钮:白底描边圆角方块 + 向上箭头。放在最后一条回复「跳到帖子」左侧、贴竖线处。
  // 32 宽:左移 4 使其中心落在竖线(x=20),右间距 16 使右侧跳到帖子仍落在正文缩进起点(4+32+16=52)。
  @Builder
  private CollapseButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      FaIconView({ icon: this.faIcon('chevron-up'), color: '#646464', iconSize: 14 })
    }
    .width(32)
    .height(32)
    .padding(0)
    .margin({ left: 4, right: 16 })
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(4)
    .onClick(() => {
      this.repliesExpanded = false;
    })
  }

  // 跳到帖子:点击滚动定位到该回复对应的楼层。
  @Builder
  private JumpToPost(reply: TopicPost) {
    Row({ space: 4 }) {
      FaIconView({ icon: this.faIcon('arrow-down'), color: '#9CA3AF', iconSize: 12 })
      Text('跳到帖子')
        .fontSize(13)
        .fontColor('#9CA3AF')
    }
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onJumpToPost(reply.postNumber);
    })
  }

  // 楼层连接竖线:1px、颜色 #E9E9E9,x 落在头像水平中心(头像40 → 中心20,线宽1 → 左移 19.5)。
  // 竖线随内容高度自适应到底;最后一条回复 padding.bottom=0 使内容底=收起按钮底,
  // 白色按钮正好盖住线尾,不会穿出按钮下沿。
  @Builder
  private ReplyThreadLine() {
    Column()
      .width(1)
      .height('100%')
      .backgroundColor('#E9E9E9')
      .margin({ left: 19.5 })
  }

  // 点赞/回应按钮:38x38。短按=切换 heart;长按=弹出 10 表情面板。
  @Builder
  private LikeButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Stack() {
        this.LikeButtonIcon()
      }
      .scale({ x: this.likeIconScale, y: this.likeIconScale })
    }
    .width(38)
    .height(38)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(10)
    // priorityGesture:让按钮的手势优先于子 Image 的默认拖拽(否则长按被 Image 的长按拖拽吃掉)。
    // Exclusive 组:短按走 Tap(切换 heart),长按走 LongPress(弹表情面板),二者互斥不冲突。
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture()
          .onAction(() => {
            this.showReactionPicker = true;
          }),
        TapGesture()
          .onAction(() => {
            this.toggleReaction('heart');
          })
      )
    )
    .bindPopup(this.showReactionPicker, {
      builder: this.ReactionPicker,
      placement: Placement.Top,
      onStateChange: (event: PopupStateEvent) => {
        if (!event.isVisible) {
          this.showReactionPicker = false;
        }
      }
    })
  }

  // 回复按钮:38x38,点击打开定向回复输入框(占位「回复<本楼作者>」),图标 reply。
  @Builder
  private ReplyButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      FaIconView({ icon: this.faIcon('reply'), color: '#646464', iconSize: 16 })
    }
    .width(38)
    .height(38)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(10)
    .onClick(() => {
      this.onReply(this.post);
    })
  }

  // boost 列表:头像+短文本气泡逐个平铺(可换行),末尾接火箭入口(canBoost 时)。
  @Builder
  private BoostRow() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      ForEach(this.boostList(), (boost: PostBoost) => {
        Row() {
          UserAvatar({ user: boost.user, avatarSize: 20 })
          Text() {
            // boost 内容按行内节点渲染:文字用 Span、emoji 用 ImageSpan,
            // 避免纯 emoji 的 boost 被当成空文本丢失。
            ForEach(this.boostInlines(boost), (token: RichInlineNode, tokenIndex: number) => {
              if (token.type === RichInlineType.IMAGE && token.src && token.src.length > 0) {
                ImageSpan(token.src)
                  .width(16)
                  .height(16)
                  .margin({ left: 1, right: 1 })
                  .verticalAlign(ImageSpanAlignment.CENTER)
              } else if (token.type === RichInlineType.LINE_BREAK) {
                Span(' ')
              } else {
                Span(token.text)
              }
            }, (token: RichInlineNode, tokenIndex: number) => `${tokenIndex}-${token.type}-${token.text}`)
          }
          .fontSize(13)
          .fontColor('#646464')
          .margin({ left: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .padding({ left: 4, right: 10, top: 4, bottom: 4 })
        .backgroundColor('#F3F4F6')
        .borderRadius(16)
        .constraintSize({ maxWidth: '72%' })
        .margin({ right: 8, top: 6 })
      }, (boost: PostBoost) => boost.id.toString())

      if (this.canAddBoost()) {
        // 火箭跟在 boost 气泡后面:与气泡等高(28)、同样的上边距(6),外边距盒一致才能垂直居中对齐。
        this.RocketButton(28, 6)
      }
    }
    .width('100%')
    .margin({ top: 2 })
  }

  // 火箭入口:点击上抛给页面打开 boost 输入浮层。两处复用(操作行内 38/0 / boost 列表末尾 28/6)。
  @Builder
  private RocketButton(size: number, topMargin: number) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      FaIconView({ icon: this.faIcon('rocket'), color: '#BDBDBD', iconSize: 16 })
    }
    .width(size)
    .height(size)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(10)
    .margin({ top: topMargin })
    .onClick(() => {
      this.onAddBoost(this.post);
    })
  }

  private boostList(): PostBoost[] {
    return this.post.boosts ? this.post.boosts : [];
  }

  // 把 boost 的 cooked HTML 解析成行内节点(文字 + emoji 图片),供气泡内 Text 混排渲染。
  private boostInlines(boost: PostBoost): RichInlineNode[] {
    return CookedHtmlParser.toInlineNodes(boost.cookedHtml);
  }

  private hasBoosts(): boolean {
    return this.boostList().length > 0;
  }

  private canAddBoost(): boolean {
    return this.post.canBoost === true;
  }

  // 按钮图标:未回应=空心灰心;heart=实心红心;其它表情=该表情 PNG。
  @Builder
  private LikeButtonIcon() {
    if (this.post.currentUserReaction === 'heart') {
      FaIconView({ icon: this.faIcon('heart'), color: LIKE_RED, iconSize: 16 })
    } else if (this.hasEmojiReaction()) {
      Image(this.currentReactionEmoji())
        .width(16)
        .height(16)
        .objectFit(ImageFit.Contain)
        .draggable(false)
    } else {
      FaIconView({ icon: this.faIcon('far-heart'), color: LIKE_GRAY, iconSize: 16 })
    }
  }

  // 就地乐观切换:先快照,再改 this.post(触发本楼重渲染),把快照交给页面用于失败回滚。
  private toggleReaction(reaction: string): void {
    const snapshot: ReactionSnapshot = ReactionMutation.snapshot(this.post);
    ReactionMutation.applyToggle(this.post, reaction);
    this.playLikePop();
    this.onToggleReaction(this.post, reaction, snapshot);
  }

  // 图标 pop:先瞬间缩到 0.7(不带动画),再用弹簧回弹到 1(低阻尼→overshoot 回弹)。
  private playLikePop(): void {
    this.likeIconScale = 0.7;
    this.getUIContext().animateTo({ curve: curves.springMotion(0.55, 0.45) }, () => {
      this.likeIconScale = 1;
    });
  }

  // 长按弹出的 10 表情面板(2 行 x 5),点某个即以该表情回应。
  @Builder
  private ReactionPicker() {
    Column() {
      Row() {
        ForEach(this.pickerRow(0), (name: string) => {
          this.PickerEmoji(name)
        }, (name: string) => name)
      }

      Row() {
        ForEach(this.pickerRow(1), (name: string) => {
          this.PickerEmoji(name)
        }, (name: string) => name)
      }
    }
    .padding(6)
  }

  @Builder
  private PickerEmoji(name: string) {
    Image(this.pickerEmoji(name))
      .width(28)
      .height(28)
      .objectFit(ImageFit.Contain)
      .draggable(false)
      .margin(6)
      .onClick(() => {
        this.showReactionPicker = false;
        this.toggleReaction(name);
      })
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }

  // 当前回应是「非 heart 且我们有对应 PNG」的表情时为真。
  private hasEmojiReaction(): boolean {
    const cur: string | undefined = this.post.currentUserReaction;
    return cur !== undefined && cur !== 'heart' && getReactionEmoji(cur) !== undefined;
  }

  // 仅在 hasEmojiReaction() 为真时调用;回退值不会触发,保证返回非空 Resource。
  private currentReactionEmoji(): Resource {
    const cur: string | undefined = this.post.currentUserReaction;
    if (cur !== undefined) {
      const res: Resource | undefined = getReactionEmoji(cur);
      if (res !== undefined) {
        return res;
      }
    }
    return $r('app.media.emoji_heart');
  }

  private pickerRow(rowIndex: number): string[] {
    return REACTION_ORDER.slice(rowIndex * 5, rowIndex * 5 + 5);
  }

  private pickerEmoji(name: string): Resource {
    const res: Resource | undefined = getReactionEmoji(name);
    return res !== undefined ? res : $r('app.media.emoji_heart');
  }

  // 把楼层的 reactions 解析成 {短名, 已解析资源} 配对,过滤掉未知表情。
  // 分离出来是为了让 icon 类型收窄为非空 Resource(Image 不接受 undefined)。
  private getReactionIcons(): ReactionIcon[] {
    const icons: ReactionIcon[] = [];
    const reactions: PostReaction[] = this.post.reactions ? this.post.reactions : [];
    for (let index: number = 0; index < reactions.length; index++) {
      const icon: Resource | undefined = getReactionEmoji(reactions[index].id);
      if (icon !== undefined) {
        icons.push({ id: reactions[index].id, icon: icon });
      }
    }
    return icons;
  }

  private hasReactions(): boolean {
    return this.post.reactionUsersCount !== undefined &&
      this.post.reactionUsersCount > 0 &&
      this.getReactionIcons().length > 0;
  }

  private isPostRead(): boolean {
    // 优先信详情响应里的 read;缺失时用 topic 层水位线 lastReadPostNumber 兜底。
    if (this.post.read === true) {
      return true;
    }
    if (this.post.read === false) {
      return false;
    }
    return this.lastReadPostNumber >= 0 && this.post.postNumber <= this.lastReadPostNumber;
  }

  private getAuthorName(): string {
    const displayName: string | undefined = this.post.author?.displayName;
    if (displayName && displayName.length > 0) {
      return displayName;
    }

    const username: string | undefined = this.post.author?.username;
    if (username && username.length > 0) {
      return username;
    }

    return '未知用户';
  }

  private getUsername(): string {
    const displayName: string | undefined = this.post.author?.displayName;
    const username: string | undefined = this.post.author?.username;
    if (!username || username.length === 0) {
      return '';
    }
    // 昵称行已用 displayName;若无 displayName、昵称已回退成 username,则第二行不再重复。
    if (displayName && displayName.length > 0) {
      return username;
    }
    return '';
  }

  private getUserTitle(): string {
    const title: string | undefined = this.post.userTitle;
    return title ? title : '';
  }

  private hasUserTitle(): boolean {
    return this.getUserTitle().length > 0;
  }

  private getRelativeTime(): string {
    return RelativeTime.fromNow(this.post.createdAt);
  }

  // 本楼是「回复某楼」:被回复楼号 + 被回复者齐备时,头部显示 share 图标 + 头像。
  private hasReplyTo(): boolean {
    return this.post.replyToPostNumber !== undefined && this.post.replyToUser !== undefined;
  }

  // 本楼「被回复」:reply_count > 0 时,底部显示被回复数量 + chevron。
  private hasReplies(): boolean {
    return this.post.replyCount !== undefined && this.post.replyCount > 0;
  }

  // 展开/收起被回复列表。首次点击:按钮上转圈加载,加载成功后才展开(不先展开再加载,
  // 避免展开区在数据到来前先露出竖线/空白)。已加载过则直接展开,不重复请求。
  private async toggleReplies(): Promise<void> {
    if (this.repliesExpanded) {
      this.repliesExpanded = false;
      return;
    }
    // 已加载过:直接展开。
    if (this.replies.length > 0) {
      this.repliesExpanded = true;
      return;
    }
    // 加载中:忽略重复点击。
    if (this.repliesLoading) {
      return;
    }
    // 未加载:先在按钮上转圈拉取,成功后再展开;失败(页面已弹 toast)保持收起,允许重试。
    this.repliesLoading = true;
    const loaded: TopicPost[] | null = await this.onLoadReplies(this.post);
    this.repliesLoading = false;
    if (loaded !== null) {
      this.replies = loaded;
      this.repliesExpanded = true;
    }
  }

  private replyAuthorName(reply: TopicPost): string {
    const displayName: string | undefined = reply.author?.displayName;
    if (displayName && displayName.length > 0) {
      return displayName;
    }
    const username: string | undefined = reply.author?.username;
    if (username && username.length > 0) {
      return username;
    }
    return '未知用户';
  }

  // 第二行用户名:仅当已用 displayName 作昵称时才显示,避免与昵称重复。
  private replyUsername(reply: TopicPost): string {
    const displayName: string | undefined = reply.author?.displayName;
    const username: string | undefined = reply.author?.username;
    if (!username || username.length === 0) {
      return '';
    }
    if (displayName && displayName.length > 0) {
      return username;
    }
    return '';
  }

}
