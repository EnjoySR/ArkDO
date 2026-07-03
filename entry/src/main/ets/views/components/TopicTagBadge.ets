import { TopicTag } from '../../models/Topic';
import { FaIconDefinition, FaIconView } from './FaIcon';
import { getTagColor, getTagIcon } from './TopicBadgeUtils';

const TAG_ICON_SIZE: number = 10;

@Component
export struct TopicTagBadge {
  tag: TopicTag = {
    name: ''
  };

  build() {
    Row() {
      if (this.getIcon()) {
        FaIconView({
          icon: this.getIcon() as FaIconDefinition,
          color: getTagColor(this.tag.name),
          iconSize: TAG_ICON_SIZE
        })
          .margin({ right: 4 })
      }

      Text(this.tag.name)
        .fontSize(10)
        .fontColor('#6B7280')
        .fontWeight(FontWeight.Medium)
    }
    .height(16)
    .padding({ left: 4, right: 4 })
    .backgroundColor('#E5E7EB')
    .borderRadius(2)
    .alignItems(VerticalAlign.Center)
    .margin({ right: 7, bottom: 4 })
  }

  private getIcon(): FaIconDefinition | undefined {
    return getTagIcon(this.tag.name);
  }
}
