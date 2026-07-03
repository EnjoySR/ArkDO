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
      UserAvatar({ user: this.post.author, avatarSize: 38 })
        .margin({ right: 12 })

      Column() {
        Row() {
          Text(this.getAuthorName())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`#${this.post.postNumber}`)
            .fontSize(12)
            .fontColor('#6B7280')
            .margin({ left: 8 })
        }
        .width('100%')

        Text(this.getMetaText())
          .fontSize(12)
          .fontColor('#9CA3AF')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
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

  private getMetaText(): string {
    const createdAt: string = this.getCreatedAtLabel();
    const likeCount: number = this.post.likeCount ? this.post.likeCount : 0;
    const replyCount: number = this.post.replyCount ? this.post.replyCount : 0;
    if (createdAt.length === 0) {
      return `${replyCount} 回复 · ${likeCount} 赞`;
    }
    return `${createdAt} · ${replyCount} 回复 · ${likeCount} 赞`;
  }

  private getCreatedAtLabel(): string {
    if (!this.post.createdAt || this.post.createdAt.length < 16) {
      return '';
    }
    return this.post.createdAt.replace('T', ' ').substring(0, 16);
  }

}
