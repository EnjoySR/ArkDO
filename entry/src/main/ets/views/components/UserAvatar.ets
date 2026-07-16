import { image } from '@kit.ImageKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { User } from '../../models/User';
import { AvatarImageCache } from '../../services/network/AvatarImageCache';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';

@Component
export struct UserAvatar {
  user?: User;
  avatarSize: number = 38;
  private readonly avatarImageSize: string = '96';
  private readonly avatarBorderColor: string = '#4D00AEFF';
  // 经 host webview 取回并解码的静态头像。主站 avatar_template 走系统栈会被 SNI 封锁,只能喂 PixelMap(单帧)。
  @State private avatarPixelMap: image.PixelMap | undefined = undefined;
  // 动图头像(animated_avatar,在未被封的 CDN 上)原生 Image 直载即可自动播 GIF;
  // 过桥解码成 PixelMap 只会取到首帧变静态,故动图不过桥。原生加载失败才置真回退桥取静态。
  @State private animatedFailed: boolean = false;
  // 图片型 flair(gif/png,跨源 CDN)同头像走桥取 PixelMap;图标型 flair(FA 名)不用。
  // flair 角标只在稍大的头像上显示,避免 20px 的回复/boost 小头像被角标糊住。
  private readonly flairMinAvatarSize: number = 32;

  aboutToAppear(): void {
    // 有动图头像时走原生 Image(自动播 GIF),不预取;仅无动图时经桥取静态头像。
    if (!this.shouldUseNativeAnimated()) {
      this.loadStaticAvatar();
    }
  }

  build() {
    // 外层 Stack:头像本体铺满,flair 角标对齐右下角。
    Stack() {
      Stack() {
        if (this.shouldUseNativeAnimated()) {
          // 动图头像:跨源 CDN(s3.ldstatic.com,非被封主站),原生 Image 直载且自动播 GIF。
          // 若该 URL 意外不可直载(如被封/失效),onError 置真回退到桥取的静态头像。
          Image(this.animatedAvatarUrl())
            .width(this.avatarSize)
            .height(this.avatarSize)
            .borderRadius(this.avatarBorderRadius())
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.surface_muted'))
            .draggable(false)
            .onError(() => {
              this.animatedFailed = true;
              this.loadStaticAvatar();
            })
        } else if (this.avatarPixelMap) {
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

      if (this.hasFlair()) {
        this.FlairBadge()
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .alignContent(Alignment.BottomEnd)
  }

  // flair 角标:形状由 flair_bg_color 决定 —— 有底色=圆(底色铺满,图标/透明PNG居中露出底环);无底色=方(整幅图铺满)。
  @Builder
  FlairBadge() {
    Stack() {
      if (this.isImageFlair()) {
        // 跨源 CDN 图(cdn3/s3.ldstatic.com,非被封的 linux.do 主站),原生 Image 直载且自动播 gif。
        // 有底色的多是透明 PNG(如信任等级):Contain + 内缩让底色露成圆环;无底色是整幅图:Cover 铺满方块。
        Image(this.flairImageUrl())
          .width('100%')
          .height('100%')
          .objectFit(this.hasFlairBg() ? ImageFit.Contain : ImageFit.Cover)
          .padding(this.hasFlairBg() ? Math.round(this.flairBadgeSize() * 0.16) : 0)
          .borderRadius(this.flairBadgeRadius())
          .draggable(false)
      } else {
        FaIconView({
          icon: this.flairFaIcon(),
          color: this.flairIconColor(),
          iconSize: this.flairIconSize()
        })
      }
    }
    .width(this.flairBadgeSize())
    .height(this.flairBadgeSize())
    .borderRadius(this.flairBadgeRadius())
    .backgroundColor(this.flairBadgeBg())
    .alignContent(Alignment.Center)
    // 轻微探出头像右下角(约角标 1/4),贴近原站观感;外层不裁切故不会被切。
    .offset({ x: this.flairOverhang(), y: this.flairOverhang() })
  }

  // 经 host webview 取静态头像(主站 avatar_template,被 SNI 封需过盾)并解码成 PixelMap。
  // 命中缓存直接显示;取不到则保持首字母占位。动图头像不走此路(见 build 原生分支)。
  private async loadStaticAvatar(): Promise<void> {
    const url: string = this.staticAvatarUrl();
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
    }
  }

  // 是否展示 flair 角标:头像够大 + 有 flairUrl;图片型直接展示(原生 Image 异步加载),图标型需字库里有该图标。
  private hasFlair(): boolean {
    const url: string | undefined = this.user?.flairUrl;
    if (!url || url.length === 0 || this.avatarSize < this.flairMinAvatarSize) {
      return false;
    }
    if (this.isImageFlair()) {
      return true;
    }
    return getFaIcon(url) !== undefined;
  }

  // flairUrl 是 URL(图片型)还是 FA 图标名(图标型)。
  private isImageFlair(): boolean {
    const url: string = this.user?.flairUrl ?? '';
    return url.startsWith('http://') || url.startsWith('https://') || url.startsWith('//');
  }

  private flairImageUrl(): string {
    return this.resolveFlairUrl(this.user?.flairUrl ?? '');
  }

  private flairFaIcon(): FaIconDefinition {
    const url: string = this.user?.flairUrl ?? '';
    const def: FaIconDefinition | undefined = getFaIcon(url);
    return def ? def : { id: url, rawfilePath: '' };
  }

  private flairBadgeSize(): number {
    return Math.max(14, Math.round(this.avatarSize * 0.42));
  }

  private flairIconSize(): number {
    return Math.round(this.flairBadgeSize() * 0.58);
  }

  private flairOverhang(): number {
    return Math.round(this.flairBadgeSize() * 0.24);
  }

  // flair 是否有底色:有=圆形彩底徽章,无=方形整图。
  private hasFlairBg(): boolean {
    const bg: string | undefined = this.user?.flairBgColor;
    return bg !== undefined && bg.length > 0;
  }

  private flairBadgeBg(): ResourceColor {
    return this.hasFlairBg() ? this.normalizeHexColor(this.user?.flairBgColor, '#BE123C') : Color.Transparent;
  }

  private flairBadgeRadius(): number {
    return this.hasFlairBg() ? this.flairBadgeSize() / 2 : Math.round(this.flairBadgeSize() * 0.18);
  }

  private flairIconColor(): string {
    return this.normalizeHexColor(this.user?.flairColor, '#FFFFFF');
  }

  private normalizeHexColor(value: string | undefined, fallback: string): string {
    if (!value || value.length === 0) {
      return fallback;
    }
    return value.startsWith('#') ? value : `#${value}`;
  }

  private resolveFlairUrl(rawUrl: string): string {
    if (rawUrl.startsWith('//')) {
      return `https:${rawUrl}`;
    }
    return rawUrl;
  }

  // ID=1 的用户使用方形圆角(10%),其余用户使用圆形头像(50%)。
  private avatarBorderRadius(): number {
    if (this.user?.id === 1) {
      return this.avatarSize * 0.1;
    }
    return this.avatarSize / 2;
  }

  // 是否走原生动图分支:有 animated_avatar 且原生尚未失败。
  private shouldUseNativeAnimated(): boolean {
    return !this.animatedFailed && this.animatedAvatarUrl().length > 0;
  }

  // 动图头像 URL(animated_avatar,通常已是 //cdn 绝对地址,无 {size} 占位)。
  private animatedAvatarUrl(): string {
    const animatedAvatar: string | undefined = this.user?.animatedAvatar;
    if (animatedAvatar && animatedAvatar.length > 0) {
      return this.resolveAvatarUrl(animatedAvatar);
    }
    return '';
  }

  // 静态头像 URL(avatar_template,主站被 SNI 封,须过桥)。
  private staticAvatarUrl(): string {
    const avatarTemplate: string | undefined = this.user?.avatarTemplate;
    if (avatarTemplate && avatarTemplate.length > 0) {
      return this.resolveAvatarUrl(avatarTemplate);
    }
    return '';
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
