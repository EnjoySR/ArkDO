import { TopicCategory } from '../../models/Topic';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';
import { getCategoryColor, getCategoryIcon, getCategoryLogo, resolveBadgeAssetUrl } from './TopicBadgeUtils';

const CATEGORY_ICON_SIZE: number = 10;
const CATEGORY_LOGO_SIZE: number = 10;
const RESTRICTED_CATEGORY_ICON_SIZE: number = 10;
const CATEGORY_COLOR_DOT_SIZE: number = 10;

@Component
export struct TopicCategoryBadge {
  category: TopicCategory = {
    id: 0,
    name: '',
    color: '6B7280',
    textColor: 'FFFFFF'
  };
  parentCategory?: TopicCategory;

  build() {
    Row() {
      if (this.getIcon()) {
        FaIconView({
          icon: this.getIcon() as FaIconDefinition,
          color: getCategoryColor(this.category),
          iconSize: CATEGORY_ICON_SIZE
        })
          .margin({ right: 3 })
      } else if (this.getLogoUrl().length > 0) {
        Image(resolveBadgeAssetUrl(this.getLogoUrl()))
          .width(CATEGORY_LOGO_SIZE)
          .height(CATEGORY_LOGO_SIZE)
          .objectFit(ImageFit.Contain)
          .margin({ right: 3 })
      } else if (this.category.readRestricted && this.getLockIcon()) {
        FaIconView({
          icon: this.getLockIcon() as FaIconDefinition,
          color: getCategoryColor(this.category),
          iconSize: RESTRICTED_CATEGORY_ICON_SIZE
        })
          .margin({ right: 3 })
      } else {
        Circle()
          .width(CATEGORY_COLOR_DOT_SIZE)
          .height(CATEGORY_COLOR_DOT_SIZE)
          .fill(getCategoryColor(this.category))
          .margin({ right: 5 })
      }

      Text(this.category.name)
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
    }
    .height(16)
    .alignItems(VerticalAlign.Center)
    .margin({ right: 8, bottom: 4 })
  }

  private getIcon(): FaIconDefinition | undefined {
    return getCategoryIcon(this.category, this.parentCategory);
  }

  private getLockIcon(): FaIconDefinition | undefined {
    return getFaIcon('lock');
  }

  private getLogoUrl(): string {
    return getCategoryLogo(this.category, this.parentCategory);
  }
}
