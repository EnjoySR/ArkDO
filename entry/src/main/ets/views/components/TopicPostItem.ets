import { TopicPost } from '../../models/TopicDetail';
import { PostRichContent } from './PostRichContent';
import { UserAvatar } from './UserAvatar';

@Component
export struct TopicPostItem {
  post: TopicPost = {
    id: 0,
    postNumber: 0,
    cookedHtml: '',
    plainText: ''
  };
  lastReadPostNumber: number = -1;

  build() {
    ListItem() {
      Column() {
        this.PostAuthorHeader()

        PostRichContent({
          cookedHtml: this.post.cookedHtml,
          fallbackText: this.post.plainText
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
      UserAvatar({ user: this.post.author, avatarSize: 48 })
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

        if (!this.isPostRead()) {
          Circle()
            .width(8)
            .height(8)
            .fill('#66CCFF')
            .margin({ left: 8 })
        }
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
    const createdAt: string | undefined = this.post.createdAt;
    if (!createdAt || createdAt.length === 0) {
      return '';
    }
    const then: number = this.parseUtcMillis(createdAt);
    if (isNaN(then)) {
      return '';
    }
    let seconds: number = Math.floor((Date.now() - then) / 1000);
    if (seconds < 0) {
      seconds = 0;
    }
    // 分档与取整对齐 Discourse 的 relativeAgeTiny(小时、天都用 Math.round,
    // 否则在小时边界处会比网页少 1,例如 17.5 小时网页显示 18、我们显示 17)。
    const minutes: number = Math.round(seconds / 60);
    if (minutes < 1) {
      return '刚刚';
    }
    if (minutes <= 44) {
      return `${minutes} 分钟`;
    }
    if (minutes <= 89) {
      return '1 小时';
    }
    if (minutes <= 1409) {
      return `${Math.round(minutes / 60)} 小时`;
    }
    if (minutes <= 2519) {
      return '1 天';
    }
    if (minutes <= 20160) {
      return `${Math.round(minutes / 1440)} 天`;
    }
    return this.formatAbsoluteDate(createdAt);
  }

  private formatAbsoluteDate(iso: string): string {
    const match: RegExpMatchArray | null = iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!match) {
      return '';
    }
    const year: number = Number(match[1]);
    const month: number = Number(match[2]);
    const day: number = Number(match[3]);
    if (year === new Date().getFullYear()) {
      return `${month}月${day}日`;
    }
    return `${year}年${month}月${day}日`;
  }

  // Discourse 的 created_at 恒为 UTC(结尾带 Z)。用 Date.UTC 按 UTC 解析,
  // 避免 ArkTS 的 Date.parse 对带时区 ISO 字符串再叠加一次本地偏移(会把时间算到未来)。
  private parseUtcMillis(iso: string): number {
    const match: RegExpMatchArray | null =
      iso.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/);
    if (!match) {
      return NaN;
    }
    return Date.UTC(
      Number(match[1]),
      Number(match[2]) - 1,
      Number(match[3]),
      Number(match[4]),
      Number(match[5]),
      Number(match[6])
    );
  }

}
