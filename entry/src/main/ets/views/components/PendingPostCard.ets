import { PendingPost } from '../../models/TopicDetail';
import { User } from '../../models/User';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { FONT_BODY, FONT_CAPTION, FONT_FOOTNOTE } from '../../common/theme/Metrics';
import { UserAvatar } from './UserAvatar';
import { FaIconView } from './FaIcon';
// 红底上的白字白图标是固定的:红底不随深浅色翻转,故用非资源色 token 而非 $r。
import { ON_DARK_FG } from '../../common/theme/Palette';

// 待审核帖子卡片。对齐官方 templates/topic.gjs 的 .pending-posts > .reviewable-item:
// 「待审核」标签 + 相对时间 / 当前用户头像昵称 / 正文 / 删除按钮。
//
// 三个来自服务端契约的约束,改动前先看清楚:
// 1. TopicPendingPostSerializer 只下发 id/raw/created_at,没有作者字段——按定义只有本人能看到
//    自己的待审帖,故作者一律取当前登录用户(官方前端同样直接用 currentUser 画头像昵称)。
// 2. raw 是 Markdown 原文,服务端不给 cooked。官方在前端 cook 一遍,我们没有本地 Markdown
//    渲染器,故按纯文本直出——待审内容基本都是刚发出去的短回复,这个取舍成本极低。
// 3. 它不是楼层:不占楼号、不进 post_stream、不参与已读上报与 scrubber 计数。
@Component
export struct PendingPostCard {
  @ObjectLink pending: PendingPost;
  // 待审帖只有本人可见,作者即当前登录用户;未登录态拿不到待审帖,故此处必有值。
  @Prop currentUser: User;
  onDelete: (pending: PendingPost) => void = () => {};

  build() {
    Column() {
      // 元信息行:「待审核」标签 + 相对时间,对齐官方 .reviewable-meta-data。
      Row() {
        // 文案与配色对齐官网 .reviewable-type(i18n review.awaiting_approval):中性灰底灰字的
        // 胶囊标签。这里刻意不用 warning 橙——官方不把"排队待审"当告警,它只是个状态说明。
        Text('需要审批')
          .fontSize(FONT_FOOTNOTE)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.fill_subtle'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)

        Text(RelativeTime.fromNow(this.pending.createdAt))
          .fontSize(FONT_FOOTNOTE)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 10 })
      }
      .width('100%')

      Row() {
        UserAvatar({ user: this.currentUser, avatarSize: 40 })
          .margin({ right: 12 })

        Column() {
          Text(this.getAuthorName())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // raw 直出:不 trim 掉换行,Markdown 原文里的分段对作者自己是有意义的。
          Text(this.pending.raw)
            .fontSize(FONT_BODY)
            .fontColor($r('app.color.text_body'))
            .width('100%')
            .margin({ top: 6 })
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: 12 })

      // 删除(撤回)按钮:对齐官方 .reviewable-actions 的 btn-danger —— 实心红底、白字、带垃圾桶图标。
      Row() {
        Row() {
          // 白色图标靠 FaIconView 的 renderMode(Template)+fillColor 染色(单色 SVG 才成立)。
          FaIconView({
            icon: { id: 'trash-can', rawfilePath: 'fa_icons/trash-can.svg' },
            color: ON_DARK_FG,
            iconSize: 14
          })
            .margin({ right: 6 })

          Text('删除')
            .fontSize(FONT_CAPTION)
            .fontColor(ON_DARK_FG)
        }
        .padding({ left: 14, right: 16, top: 8, bottom: 8 })
        .borderRadius(6)
        .backgroundColor($r('app.color.ld_danger'))
        .onClick(() => {
          this.onDelete(this.pending);
        })
      }
      .width('100%')
      // 左对齐:对齐官网(按钮左边缘与头像左边缘齐平)。右对齐会被右下角的蓝色回复 FAB 压住一角。
      .justifyContent(FlexAlign.Start)
      .margin({ top: 12 })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  // 昵称优先 displayName,回退 username(与楼层作者头一致的取法)。
  private getAuthorName(): string {
    const displayName: string | undefined = this.currentUser.displayName;
    if (displayName !== undefined && displayName.length > 0) {
      return displayName;
    }
    return this.currentUser.username;
  }
}
