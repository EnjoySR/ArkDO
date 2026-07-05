import { PostReaction, TopicPost } from '../../models/TopicDetail';
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
  // 表情回应切换:本组件就地乐观更新 this.post(@ObjectLink 自身变更→精准重渲染),
  // 页面只负责发 PUT + 失败时用 snapshot 回滚。
  onToggleReaction: (post: TopicPost, reaction: string, snapshot: ReactionSnapshot) => void = () => {};
  @State private showReactionPicker: boolean = false;

  build() {
    ListItem() {
      Column() {
        this.PostAuthorHeader()

        PostRichContent({
          cookedHtml: this.post.cookedHtml,
          fallbackText: this.post.plainText,
          onOpenImages: this.onOpenImages
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
        // 左:表情回应汇总(图标组 + 回应人数),仅有回应时渲染内容。
        Row() {
          if (this.hasReactions()) {
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
        }
        .alignItems(VerticalAlign.Center)

        // 右:操作入口 —— 点赞/回应按钮(短按 heart、长按选表情),回复入口 TODO
        Row() {
          this.LikeButton()
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      // TODO: boost 相关界面
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  // 点赞/回应按钮:38x38。短按=切换 heart;长按=弹出 10 表情面板。
  @Builder
  private LikeButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      this.LikeButtonIcon()
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
    this.onToggleReaction(this.post, reaction, snapshot);
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

}
