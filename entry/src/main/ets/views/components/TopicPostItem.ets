import { TopicPost } from '../../models/TopicDetail';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { PostRichContent } from './PostRichContent';
import { ViewerImage } from './ImageViewer';
import { UserAvatar } from './UserAvatar';

@Component
export struct TopicPostItem {
  // @ObjectLink 绑定 @Observed 的 TopicPost:楼层 read 翻真时精准触发本组件重渲染,
  // 蓝点 opacity 过渡才会播放。由父组件 ForEach 传入,不能有默认值。
  @ObjectLink post: TopicPost;
  lastReadPostNumber: number = -1;
  // 图片浏览器在页面级渲染，这里把 PostRichContent 的「打开」请求继续上抛给页面
  onOpenImages: (images: ViewerImage[], startIndex: number) => void = () => {};

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
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })
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
