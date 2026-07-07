import { curves } from '@kit.ArkUI';
import { Poll, PollVoteResult, PostBoost, PostReaction, TopicPost } from '../../models/TopicDetail';
import { CookedHtmlParser, RichInlineNode, RichInlineType } from '../../services/content/CookedHtmlParser';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { ReactionMutation } from '../../services/topic/ReactionMutation';
import { getReactionEmoji, REACTION_ORDER } from './EmojiRegistry';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { PostRichContent } from './PostRichContent';
import { ViewerImage } from './ImageViewer';
import { UserAvatar } from './UserAvatar';

const LIKE_RED: string = '#EF4444';
const LIKE_GRAY: string = '#BDBDBD';

// 拷贝链接成功后按钮右下角"画勾"动画,对齐 Discourse post-action-feedback:
// 复制成功后按钮右下角"画勾"反馈。strokeDashOffset 在本环境不吃 animateTo,改用「左→右揭示」实现描边过程:
// 勾路径 x 单调递增(2→8.36→20),放在固定尺寸盒里;外层容器 clip(true)+宽度 0→W 动画,从左到右逐段显现=画勾。
const COPY_CHECK_W: number = 22;
const COPY_CHECK_H: number = 16;
const COPY_CHECK_PATH: string = 'M2 8.8 L8.36 14 L20 2';
const COPY_CHECK_STROKE: number = 2;
const COPY_CHECK_X: number = 22;   // 揭示容器在 38 按钮内的左上角坐标 → 落到右下角
const COPY_CHECK_Y: number = 24;
const COPY_CHECK_DRAW_MS: number = 1700;
const COPY_CHECK_COLOR: string = '#22C55E';
const COPY_FEEDBACK_TIMEOUT_MS: number = 3000;
const COPY_FEEDBACK_TRANSITION_MS: number = 250;

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
  // @ObjectLink 绑定 @Observed 的 TopicPost:楼层 read/reporting 变化精准触发本组件重渲染,
  // 蓝点 opacity 过渡才会播放。由父组件 ForEach 传入,不能有默认值。
  // @Watch:reporting/read 变化时开/停"呼吸"定时器(见 syncBreathing)。
  @ObjectLink @Watch('onPostStateChanged') post: TopicPost;
  lastReadPostNumber: number = -1;
  // 本楼是进入时快照的"第一条未读楼":顶部渲染"上次访问"红色分隔线(对齐官网 last visit 线)。
  // 普通 prop:锚楼由页面在楼层创建前确定且不再变化,无需响应式。
  showLastVisitedLine: boolean = false;
  // 通知/引用跳转的目标楼:挂载后背景短暂高亮再渐隐(对齐官网 anchor 高亮),一次性。
  flashOnAppear: boolean = false;
  // 图片浏览器在页面级渲染，这里把 PostRichContent 的「打开」请求继续上抛给页面
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};
  // 正文链接 / onebox 卡片点击继续上抛给页面(由页面经 LinkRouter 判断跳原生详情或通用 WebView)。
  onOpenLink: (url: string) => void = () => {};
  // 表情回应切换:请求先行,页面发 PUT 并返回成败;成功后本组件才改 this.post
  // (@ObjectLink 自身变更→精准重渲染),请求期间按钮转圈防重复点击。
  onToggleReaction: (post: TopicPost, reaction: string) => Promise<boolean> = () => Promise.resolve(false);
  // 点该楼回复按钮:把整条 post 上抛给页面,由页面按 postNumber+作者昵称打开定向回复输入框。
  onReply: (post: TopicPost) => void = () => {};
  // 点火箭:把整条 post 上抛给页面,由页面打开 boost 输入浮层。
  onAddBoost: (post: TopicPost) => void = () => {};
  // 投票/撤销:把整条 post 与目标 poll 上抛给页面做乐观闭环。返回服务端校正结果;null=失败。
  onVote: (post: TopicPost, poll: Poll, optionIds: string[]) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  onRemoveVote: (post: TopicPost, poll: Poll) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  // 点头部「回复别人」指示器 / 展开区「跳到帖子」:按 postNumber 上抛给页面滚动定位。
  // 返回 Promise:目标楼未加载时页面会重开窗口(网络请求),期间入口图标显示加载中。
  onJumpToPost: (postNumber: number) => Promise<void> = () => Promise.resolve();
  // 展开「被回复」时上抛给页面拉取列表(页面持有 bridge/TopicService);返回楼层数组,失败返回 null。
  onLoadReplies: (post: TopicPost) => Promise<TopicPost[] | null> = () => Promise.resolve(null);
  // 点「更多」展开区:拷贝该楼永久链接、书签 toggle。均上抛给页面(页面持有 bridge/slug/剪贴板)。
  onCopyPostLink: (post: TopicPost) => void = () => {};
  // 书签 toggle 上抛页面发网络,返回操作后的最终收藏态(失败=回滚后的原态),用于校正本地显示。
  onToggleBookmark: (post: TopicPost) => Promise<boolean> = () => Promise.resolve(false);
  @State private showReactionPicker: boolean = false;
  // 「更多」展开态:点 ellipsis 后换出「拷贝链接 + 书签」两个按钮。对齐官方:展开后不再收起。
  @State private moreExpanded: boolean = false;
  // 拷贝链接成功反馈:按钮右下角描边画绿勾。visible=挂载、opacity=淡入淡出、drawn=strokeDashOffset 目标(0=画满)。
  @State private copyCheckVisible: boolean = false;
  @State private copyCheckOpacity: number = 0;
  // 揭示宽度:0=隐藏,动画到 COPY_CHECK_W=画满(左→右揭示,替代 strokeDashOffset 的描边动画)。
  @State private copyCheckReveal: number = 0;
  private copyFadeTimerId: number = -1;
  private copyHideTimerId: number = -1;
  // 书签显示态:必须用自身 @State 驱动(纯 @ObjectLink 的 post.bookmarked 变更在本大组件里不触发重渲染,
  // 见 memory objectlink-state-source)。aboutToAppear 从 post 初始化,点击乐观翻转,再用页面回传态校正。
  @State private bookmarkedLocal: boolean = false;
  // 书签请求进行中:按钮显示 loading(不做乐观更新,等网络结果再切换图标)。
  @State private bookmarkLoading: boolean = false;
  // 被回复列表:展开态 / 加载态 / 已加载数据。按 memory objectlink-state-source,状态放本组件 @State
  // (而非 @Observed TopicPost 深层字段),重渲染才稳。
  @State private repliesExpanded: boolean = false;
  @State private repliesLoading: boolean = false;
  @State private replies: TopicPost[] = [];
  // 点赞按钮图标的弹簧缩放:每次切换回应时做一次 pop(先缩到 0.7,再用弹簧回弹到 1,带 overshoot)。
  @State private likeIconScale: number = 1;
  // 上报进行中蓝点"呼吸"(颜色变浅再变回):定时器每 700ms 翻 breatheDim + 有限动画驱动。
  // 用自身 @State + clearInterval 可靠停止;不用 ArkUI 隐式 iterations:-1(无限动画停不干净)。
  @State private breathing: boolean = false;
  @State private breatheDim: boolean = false;
  private breatheTimerId: number = -1;
  // 表情回应请求进行中:点赞按钮转圈,期间忽略再次点击(请求先行,不做乐观更新)。
  @State private reactionLoading: boolean = false;
  // 目标楼高亮进行中:背景淡蓝,定时后渐隐回透明(backgroundColor 绑定隐式动画)。
  @State private flashActive: boolean = false;
  private flashTimerId: number = -1;
  // 「跳到帖子」跳转进行中的目标楼号(>0 时该行箭头换加载图标;重开窗口是网络请求,需要反馈)。
  @State private jumpLoadingPostNumber: number = 0;

  build() {
    ListItem() {
      Column() {
        if (this.showLastVisitedLine) {
          this.LastVisitedDivider()
        }

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
      // 左右留白由本组件持有(而非 List 的 padding):高亮背景才能通栏铺满屏幕宽。
      .padding({ left: 10, right: 10, top: 12, bottom: 12 })
      .border({
        width: { bottom: 1 },
        color: '#E5E7EB'
      })
      .alignItems(HorizontalAlign.Start)
      // 渐隐终点必须是同色系零透明度(#00+淡蓝):Color.Transparent 是透明黑,
      // RGBA 逐通道插值时中间帧会过路半透明灰(蓝→灰→消失的成因)。
      .backgroundColor(this.flashActive ? '#E8F1FE' : '#00E8F1FE')
      .animation({ duration: 600, curve: Curve.EaseOut })
    }
  }

  // "上次访问"红色分隔线:两侧细线夹居中文字,色值对齐官网 last visit(#e45735 系)。
  @Builder
  private LastVisitedDivider() {
    Row() {
      Divider()
        .strokeWidth(1)
        .color('#E45735')
        .layoutWeight(1)
      Text('上次访问')
        .fontSize(12)
        .fontColor('#E45735')
        .margin({ left: 10, right: 10 })
      Divider()
        .strokeWidth(1)
        .color('#E45735')
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 10 })
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
        // 上报进行中:尺寸不变,opacity 在 1↔0.35 间来回("呼吸"=颜色变浅再变回),由 breatheDim 定时器驱动。
        Circle()
          .width(8)
          .height(8)
          .fill('#66CCFF')
          .margin({ left: 2 })
          .opacity(this.isPostRead() ? 0 : (this.breatheDim ? 0.35 : 1))
          .animation({ duration: this.breathing ? 700 : 1200, curve: Curve.EaseInOut })
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
          // 更多入口:位于火箭与回复之间。展开后换出拷贝链接 + 书签两个按钮。
          this.MoreActions()
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

  // 跳到帖子:点击滚动定位到该回复对应的楼层;目标楼未加载时页面重开窗口,期间箭头换加载图标。
  @Builder
  private JumpToPost(reply: TopicPost) {
    Row({ space: 4 }) {
      if (this.jumpLoadingPostNumber === reply.postNumber) {
        LoadingProgress()
          .width(12)
          .height(12)
          .color('#9CA3AF')
      } else {
        FaIconView({ icon: this.faIcon('arrow-down'), color: '#9CA3AF', iconSize: 12 })
      }
      Text('跳到帖子')
        .fontSize(13)
        .fontColor('#9CA3AF')
    }
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.jumpLoadingPostNumber > 0) {
        return;
      }
      this.jumpLoadingPostNumber = reply.postNumber;
      this.onJumpToPost(reply.postNumber).then(() => {
        this.jumpLoadingPostNumber = 0;
      }).catch(() => {
        this.jumpLoadingPostNumber = 0;
      });
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
        .backgroundColor('#F2F2F2')
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

  // 更多操作:收起态显示 ellipsis;展开态换出「拷贝链接 + 书签」两个按钮(与火箭同款 38 透明按钮)。
  // 对齐官方:展开后不收起,故只需本组件 @State moreExpanded 单向翻真。
  @Builder
  private MoreActions() {
    if (this.moreExpanded) {
      this.CopyLinkButton()
      this.BookmarkButton()
    } else {
      this.MoreButton()
    }
  }

  @Builder
  private MoreButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      FaIconView({ icon: this.faIcon('ellipsis'), color: '#BDBDBD', iconSize: 16 })
    }
    .width(38)
    .height(38)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(10)
    .onClick(() => {
      // 展开带一次淡入位移过渡:换出的两个按钮从右侧滑入。
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.moreExpanded = true;
      });
    })
  }

  @Builder
  private CopyLinkButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      // link 图标居中(Stack 默认 Center);复制成功后右下角叠加"画勾"反馈(勾用 position 独立定位,
      // 不能用 Stack alignContent,否则会把 link 图标也一起推到角上)。对齐 Discourse post-action-feedback。
      Stack() {
        // link 图标居中:用满尺寸 Column 承载并居中。
        Column() {
          FaIconView({ icon: this.faIcon('link'), color: '#BDBDBD', iconSize: 16 })
        }
        .width(38)
        .height(38)
        .justifyContent(FlexAlign.Center)

        // 勾:固定尺寸盒放完整勾,外层揭示容器 clip(true)+宽度 0→W 动画,从左到右逐段显现=画勾过程。
        // 常驻(idle 时宽 0 / opacity 0 隐藏);.position 明确定位到按钮右下角(不靠对齐,避免算错)。
        Stack({ alignContent: Alignment.TopStart }) {
          Path()
            .width(COPY_CHECK_W)
            .height(COPY_CHECK_H)
            .commands(COPY_CHECK_PATH)
            .fill(Color.Transparent)
            .stroke(COPY_CHECK_COLOR)
            .strokeWidth(COPY_CHECK_STROKE)
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
        }
        .width(this.copyCheckReveal)
        .height(COPY_CHECK_H)
        .clip(true)
        .opacity(this.copyCheckOpacity)
        .position({ x: COPY_CHECK_X, y: COPY_CHECK_Y })
        .hitTestBehavior(HitTestMode.None)
      }
      .width(38)
      .height(38)
    }
    .width(38)
    .height(38)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(10)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 12 })))
    .onClick(() => {
      // 保留原有 toast(页面弹「已复制链接」),同时叠加官方同款按钮内画勾动画。
      this.onCopyPostLink(this.post);
      this.playCopyFeedback();
    })
  }

  // 复制成功反馈:淡入(250ms)+ 从左到右揭示画勾(COPY_CHECK_DRAW_MS);淡出后卸载。
  // 勾在显示期间重复点击忽略(对齐官方 recentlyCopied 守卫)。
  private playCopyFeedback(): void {
    if (this.copyCheckVisible) {
      return;
    }
    this.copyCheckVisible = true;
    this.copyCheckOpacity = 0;
    this.copyCheckReveal = 0;
    const ctx: UIContext = this.getUIContext();
    ctx.animateTo({ duration: COPY_FEEDBACK_TRANSITION_MS, curve: Curve.EaseOut }, () => {
      this.copyCheckOpacity = 1;
    });
    ctx.animateTo({ duration: COPY_CHECK_DRAW_MS, curve: Curve.Linear }, () => {
      this.copyCheckReveal = COPY_CHECK_W;
    });
    this.copyFadeTimerId = setTimeout(() => {
      this.getUIContext().animateTo({ duration: COPY_FEEDBACK_TRANSITION_MS, curve: Curve.EaseOut }, () => {
        this.copyCheckOpacity = 0;
      });
    }, COPY_FEEDBACK_TIMEOUT_MS - COPY_FEEDBACK_TRANSITION_MS);
    this.copyHideTimerId = setTimeout(() => {
      this.copyCheckVisible = false;
      this.copyCheckReveal = 0;
    }, COPY_FEEDBACK_TIMEOUT_MS);
  }

  private clearCopyFeedbackTimers(): void {
    if (this.copyFadeTimerId >= 0) {
      clearTimeout(this.copyFadeTimerId);
      this.copyFadeTimerId = -1;
    }
    if (this.copyHideTimerId >= 0) {
      clearTimeout(this.copyHideTimerId);
      this.copyHideTimerId = -1;
    }
  }

  @Builder
  private BookmarkButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      // 请求进行中显示 loading;否则按本地 @State bookmarkedLocal 显示 已收藏(实心蓝)/未收藏(空心灰)。
      // if/else 两个独立 FaIconView 实例(复用同一实例只换 icon 属性不可靠,同 chevron)。
      if (this.bookmarkLoading) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color('#9CA3AF')
      } else if (this.bookmarkedLocal) {
        FaIconView({ icon: this.faIcon('bookmark'), color: '#0088CC', iconSize: 16 })
      } else {
        FaIconView({ icon: this.faIcon('far-bookmark'), color: '#BDBDBD', iconSize: 16 })
      }
    }
    .width(38)
    .height(38)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(10)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 12 })))
    .onClick(() => {
      // 不做乐观更新:点击进入 loading,等网络返回后用页面回传的最终态更新显示。请求中重复点忽略。
      if (this.bookmarkLoading) {
        return;
      }
      this.bookmarkLoading = true;
      console.info(`[ARKDO][Bookmark] tap postId=${this.post.id} bookmarkedLocal=${this.bookmarkedLocal} postBookmarked=${this.post.bookmarked} bookmarkId=${this.post.bookmarkId}`);
      this.onToggleBookmark(this.post).then((finalState: boolean) => {
        this.bookmarkedLocal = finalState;
        this.bookmarkLoading = false;
        console.info(`[ARKDO][Bookmark] reconcile postId=${this.post.id} finalState=${finalState}`);
      });
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

  // 按钮图标:请求中=转圈;未回应=空心灰心;heart=实心红心;其它表情=该表情 PNG。
  @Builder
  private LikeButtonIcon() {
    if (this.reactionLoading) {
      LoadingProgress()
        .width(16)
        .height(16)
        .color(LIKE_GRAY)
    } else if (this.post.currentUserReaction === 'heart') {
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

  // 请求先行(与书签一致):按钮转圈期间禁止再点;成功才改 this.post(触发本楼重渲染)并播 pop,
  // 失败 toast 由服务层负责,本地状态不动,不会出现"图标闪一下又弹回"的观感。
  private async toggleReaction(reaction: string): Promise<void> {
    if (this.reactionLoading) {
      return;
    }
    this.reactionLoading = true;
    const ok: boolean = await this.onToggleReaction(this.post, reaction);
    this.reactionLoading = false;
    if (ok) {
      ReactionMutation.applyToggle(this.post, reaction);
      this.playLikePop();
    }
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
  // 汇总胶囊最多展示前 3 种表情,总人数仍用 reactionUsersCount。
  private getReactionIcons(): ReactionIcon[] {
    const icons: ReactionIcon[] = [];
    const reactions: PostReaction[] = this.post.reactions ? this.post.reactions : [];
    for (let index: number = 0; index < reactions.length && icons.length < 3; index++) {
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

  aboutToAppear(): void {
    this.syncBreathing();
    this.bookmarkedLocal = this.post.bookmarked === true;
    if (this.flashOnAppear) {
      // 先无动画置为高亮底色,停留片刻后翻回触发渐隐(backgroundColor 上的隐式动画)。
      this.flashActive = true;
      this.flashTimerId = setTimeout(() => {
        this.flashActive = false;
      }, 900);
    }
  }

  aboutToDisappear(): void {
    this.stopBreathing();
    this.clearCopyFeedbackTimers();
    if (this.flashTimerId >= 0) {
      clearTimeout(this.flashTimerId);
      this.flashTimerId = -1;
    }
  }

  // post 任一 @Observed 字段变化(含 reporting/read)都会触发:据此开/停"呼吸"定时器。
  private onPostStateChanged(): void {
    this.syncBreathing();
  }

  // 上报进行中且尚未读→启动定时器每 700ms 翻明暗;否则停止并复位。幂等,可反复调用。
  private syncBreathing(): void {
    const shouldBreathe: boolean = this.post.reporting === true && this.post.read !== true;
    if (shouldBreathe && this.breatheTimerId < 0) {
      this.breathing = true;
      this.breatheDim = true; // 先变浅,之后每 700ms 翻转一次
      this.breatheTimerId = setInterval(() => {
        this.breatheDim = !this.breatheDim;
      }, 700);
    } else if (!shouldBreathe && this.breatheTimerId >= 0) {
      this.stopBreathing();
    }
  }

  private stopBreathing(): void {
    if (this.breatheTimerId >= 0) {
      clearInterval(this.breatheTimerId);
      this.breatheTimerId = -1;
    }
    this.breathing = false;
    this.breatheDim = false;
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
