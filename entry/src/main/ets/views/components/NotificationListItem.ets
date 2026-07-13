import { NotificationItem } from '../../models/Notification';
import { User } from '../../models/User';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { UserAvatar } from './UserAvatar';

const AVATAR_SIZE: number = 42;
// 头像右下角角标配色:未读=品牌蓝底白图标;已读=白底深灰图标(对齐站点)。
const BADGE_BG_UNREAD: string = '#08C';
const BADGE_BG_READ: string = '#FFFFFF';
const BADGE_FG_UNREAD: string = '#FFFFFF';
const BADGE_FG_READ: string = '#222222';

// 通知列表单行:有发起人 → 头像 + 右下角类型角标;系统类 → 纯色类型图标圈。
// 右侧动作文案(发起人加粗)+ 帖子标题两行、相对时间;未读整行淡蓝底 + 蓝点。
@Component
export struct NotificationListItem {
  item: NotificationItem = {
    id: 0, type: 0, read: true, createdAt: '', actorName: '', actorUsername: '',
    actionText: '', title: '', iconId: 'bell', iconColor: '#9CA3AF'
  };
  onItemClick: (item: NotificationItem) => void = () => {};

  build() {
    Row({ space: 12 }) {
      this.Avatar()

      Column() {
        Text() {
          if (this.item.actorName.length > 0) {
            Span(this.item.actorName)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Span(` ${this.item.actionText}`)
              .fontColor($r('app.color.text_secondary'))
          } else {
            Span(this.item.actionText)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
        }
        .fontSize(15)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.item.title.length > 0) {
          Text(this.item.title)
            .fontSize(13.5)
            .fontColor(this.item.read ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text(RelativeTime.fromNow(this.item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        if (!this.item.read) {
          Circle({ width: 9, height: 9 }).fill($r('app.color.brand'))
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.item.read ? $r('app.color.page_bg') : $r('app.color.info_soft_bg'))
    .onClick(() => {
      this.onItemClick(this.item);
    })
  }

  @Builder
  private Avatar() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.item.avatarTemplate !== undefined) {
        // 有发起人:真实头像 + 右下角类型角标。
        UserAvatar({
          user: this.buildActorUser(),
          avatarSize: AVATAR_SIZE
        })
        Stack() {
          FaIconView({
            icon: this.faIcon(this.item.iconId),
            color: this.item.read ? BADGE_FG_READ : BADGE_FG_UNREAD,
            iconSize: 11
          })
        }
        .width(20)
        .height(20)
        .borderRadius(10)
        .backgroundColor(this.item.read ? BADGE_BG_READ : BADGE_BG_UNREAD)
        .alignContent(Alignment.Center)
        .margin({ right: -3, bottom: -3 })
      } else {
        // 系统类:纯色类型图标圈,无角标。
        Stack() {
          FaIconView({ icon: this.faIcon(this.item.iconId), color: '#FFFFFF', iconSize: 18 })
        }
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(AVATAR_SIZE / 2)
        .backgroundColor(this.item.iconColor)
        .alignContent(Alignment.Center)
      }
    }
    .width(AVATAR_SIZE)
    .height(AVATAR_SIZE)
  }

  private buildActorUser(): User {
    return {
      id: 0,
      username: this.item.actorUsername.length > 0 ? this.item.actorUsername : '?',
      avatarTemplate: this.item.avatarTemplate
    };
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }
}
