import { image } from '@kit.ImageKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { User } from '../../models/User';
import { AvatarImageCache } from '../../services/network/AvatarImageCache';

@Component
export struct UserAvatar {
  user?: User;
  avatarSize: number = 38;
  private readonly avatarImageSize: string = '96';
  private readonly avatarBorderColor: string = '#4D00AEFF';
  // 当前使用的头像候选下标:动图(0)加载失败 → 静态(1)→ 都失败(>=候选数)回退首字母。
  @State private avatarSourceIndex: number = 0;
  // 经 host webview 取回并解码的头像。原生 Image 走系统栈会被 SNI 封锁,只能喂 PixelMap。
  @State private avatarPixelMap: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    this.loadCurrent();
  }

  build() {
    Stack() {
      if (this.avatarPixelMap) {
        Image(this.avatarPixelMap)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.avatarBorderRadius())
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.surface_muted'))
      } else {
        Text(this.getInitial())
          .fontSize(Math.max(12, Math.floor(this.avatarSize * 0.4)))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.avatar_fg'))
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.avatarBorderRadius())
    .border({
      width: 1,
      color: this.avatarBorderColor
    })
    .backgroundColor($r('app.color.surface_muted'))
    .alignContent(Alignment.Center)
  }

  // 取当前候选头像:命中缓存直接显示;否则异步经 host webview 取。当前候选失败则退到下一候选,
  // 全部候选失败则维持首字母占位。
  private async loadCurrent(): Promise<void> {
    const url: string = this.currentAvatarUrl();
    if (url.length === 0) {
      this.avatarPixelMap = undefined;
      return;
    }
    const cache: AvatarImageCache = AvatarImageCache.getInstance();
    const cached: image.PixelMap | undefined = cache.getCached(url);
    if (cached) {
      this.avatarPixelMap = cached;
      return;
    }
    const pixelMap: image.PixelMap | undefined = await cache.load(url);
    if (pixelMap) {
      this.avatarPixelMap = pixelMap;
      return;
    }
    // 当前候选取不到 → 尝试下一候选(动图失败退静态);无更多候选则保持首字母。
    if (this.avatarSourceIndex + 1 < this.avatarCandidates().length) {
      this.avatarSourceIndex += 1;
      await this.loadCurrent();
    }
  }

  // ID=1 的用户使用方形圆角(10%),其余用户使用圆形头像(50%)。
  private avatarBorderRadius(): number {
    if (this.user?.id === 1) {
      return this.avatarSize * 0.1;
    }
    return this.avatarSize / 2;
  }

  private currentAvatarUrl(): string {
    const candidates: string[] = this.avatarCandidates();
    if (this.avatarSourceIndex < candidates.length) {
      return candidates[this.avatarSourceIndex];
    }
    return '';
  }

  // 优先动图(animated_avatar),失败回退静态(avatar_template)。
  private avatarCandidates(): string[] {
    const candidates: string[] = [];
    const animatedAvatar: string | undefined = this.user?.animatedAvatar;
    if (animatedAvatar && animatedAvatar.length > 0) {
      candidates.push(this.resolveAvatarUrl(animatedAvatar));
    }
    const avatarTemplate: string | undefined = this.user?.avatarTemplate;
    if (avatarTemplate && avatarTemplate.length > 0) {
      candidates.push(this.resolveAvatarUrl(avatarTemplate));
    }
    return candidates;
  }

  private resolveAvatarUrl(rawAvatar: string): string {
    const sizedAvatar: string = rawAvatar.replace('{size}', this.avatarImageSize);
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
