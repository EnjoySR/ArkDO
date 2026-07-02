import { AppConstants } from '../../common/constants/AppConstants';
import { User } from '../../models/User';

@Component
export struct UserAvatar {
  user?: User;
  avatarSize: number = 38;
  private readonly avatarImageSize: string = '96';
  private readonly avatarBorderColor: string = '#4D00AEFF';

  build() {
    Stack() {
      if (this.hasAvatar()) {
        Image(this.getAvatarUrl())
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.avatarSize / 2)
          .objectFit(ImageFit.Cover)
          .backgroundColor('#E5E7EB')
      } else {
        Text(this.getInitial())
          .fontSize(Math.max(12, Math.floor(this.avatarSize * 0.4)))
          .fontWeight(FontWeight.Medium)
          .fontColor('#4B5563')
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
    .border({
      width: 1,
      color: this.avatarBorderColor
    })
    .backgroundColor('#E5E7EB')
    .alignContent(Alignment.Center)
  }

  private hasAvatar(): boolean {
    return this.getAvatarUrl().length > 0;
  }

  private getAvatarUrl(): string {
    const avatarTemplate: string | undefined = this.user?.avatarTemplate;
    if (!avatarTemplate) {
      return '';
    }

    const sizedAvatar: string = avatarTemplate.replace('{size}', this.avatarImageSize);
    if (sizedAvatar.startsWith('http://') || sizedAvatar.startsWith('https://')) {
      return sizedAvatar;
    }

    if (sizedAvatar.startsWith('//')) {
      return `https:${sizedAvatar}`;
    }

    if (sizedAvatar.startsWith('/')) {
      return `${AppConstants.BASE_URL}${sizedAvatar}`;
    }

    return `${AppConstants.BASE_URL}/${sizedAvatar}`;
  }

  private getInitial(): string {
    const username: string | undefined = this.user?.username;
    if (!username || username.length === 0) {
      return '?';
    }
    return username.substring(0, 1).toUpperCase();
  }
}
