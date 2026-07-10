import { UserBadgeItem } from '../../models/UserProfile';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';

// 徽章小卡片:个人中心徽章区与「全部徽章」页共用。
// 图片徽章(imageUrl)原图展示;FA 图标徽章按金/银/铜等级色染色。可重复获得的徽章名字后缀 ×N。

// Discourse badge_type_id → 等级色。1=金 2=银 其余=铜。
export function badgeTypeColor(badgeTypeId: number): Resource {
  if (badgeTypeId === 1) {
    return $r('app.color.ld_gold');
  }
  if (badgeTypeId === 2) {
    return $r('app.color.ld_silver');
  }
  return $r('app.color.ld_bronze');
}

export function badgeTileLabel(badge: UserBadgeItem): string {
  return badge.grantCount !== undefined && badge.grantCount > 1
    ? `${badge.name} ×${badge.grantCount}`
    : badge.name;
}

function badgeFaIcon(name: string): FaIconDefinition {
  const def: FaIconDefinition | undefined = getFaIcon(name);
  return def ? def : { id: name, rawfilePath: '' };
}

// 全局 @Builder:内联展开,layoutWeight(1) 与父 Row 的等分列宽逻辑一致。
// onTap 由调用方决定(个人中心传空实现,全部徽章页弹详情)。
@Builder
export function BadgeTile(badge: UserBadgeItem, onTap: (badge: UserBadgeItem) => void) {
  Column() {
    Column() {
      if (badge.imageUrl) {
        Image(badge.imageUrl)
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else {
        FaIconView({
          icon: badgeFaIcon(badge.icon && badge.icon.length > 0 ? badge.icon : 'certificate'),
          iconSize: 26,
          color: badgeTypeColor(badge.badgeTypeId)
        })
      }
    }
    .height(32)
    .justifyContent(FlexAlign.Center)

    Text(badgeTileLabel(badge))
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .textAlign(TextAlign.Center)
      .margin({ top: 7 })
  }
  .layoutWeight(1)
  .padding({ top: 12, bottom: 10, left: 6, right: 6 })
  .borderRadius(12)
  .backgroundColor($r('app.color.surface_band'))
  .alignItems(HorizontalAlign.Center)
  .onClick(() => {
    onTap(badge);
  })
}
