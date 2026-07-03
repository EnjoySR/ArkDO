import { User } from '../../models/User';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { AuthService } from '../../services/auth/AuthService';
import { UserAvatar } from '../components/UserAvatar';
import { ThemeManager, ThemeMode } from '../../common/theme/ThemeManager';

const LOG_TAG: string = '[ArkDO][Profile]';

@Component
export struct ProfilePage {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  onLoginClick: () => void = () => {};
  @StorageLink('themeMode') themeMode: ThemeMode = ThemeMode.SYSTEM;
  @State private currentUser?: User = undefined;
  @State private isCheckingSession: boolean = false;
  @State private hasCheckedSession: boolean = false;
  @State private sessionMessage: string = '正在准备登录状态检查';
  @State private requiresChallenge: boolean = false;
  private requestSequence: number = 0;
  private handledSessionVersion: number = SessionEventBus.getCurrentVersion();
  private unsubscribeSessionChanged?: () => void = undefined;

  aboutToAppear(): void {
    if (!this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged = SessionEventBus.subscribe((version: number) => {
        this.handleSessionChanged(version);
      });
    }
    this.syncSessionVersion();
    if (this.isArkWebReady) {
      this.checkCurrentUser();
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribeSessionChanged) {
      this.unsubscribeSessionChanged();
      this.unsubscribeSessionChanged = undefined;
    }
  }

  build() {
    Column() {
      Text('我的')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 12 })

      this.AppearanceSection()

      if (this.currentUser) {
        this.LoggedInContent()
      } else {
        this.AnonymousContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private AppearanceSection() {
    Column() {
      Text('外观')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      Row() {
        this.ThemeOption('跟随系统', ThemeMode.SYSTEM)
        this.ThemeOption('浅色', ThemeMode.LIGHT)
        this.ThemeOption('深色', ThemeMode.DARK)
      }
      .width('100%')
      .padding(4)
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(10)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ThemeOption(label: string, mode: ThemeMode) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.themeMode === mode ? Color.White : $r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(36)
      .margin(2)
      .borderRadius(8)
      .backgroundColor(this.themeMode === mode ? $r('app.color.brand') : Color.Transparent)
      .onClick(() => {
        ThemeManager.setMode(getContext(this), mode);
      })
  }

  @Builder
  private LoggedInContent() {
    Column() {
      Column() {
        UserAvatar({
          user: this.currentUser,
          avatarSize: 72
        })

        Text(this.getDisplayName())
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .margin({ top: 16 })

        Text(this.getUsernameLabel())
          .fontSize(14)
          .fontColor('#6B7280')
          .margin({ top: 6 })

        Row() {
          Text('已登录')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#047857')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#D1FAE5')
            .borderRadius(8)
        }
        .margin({ top: 14 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 34, bottom: 30 })

      Column() {
        this.InfoRow('用户名', this.getUsernameLabel())
        Divider()
          .color('#E5E7EB')
        this.InfoRow('Linux.do ID', this.getUserIdLabel())
      }
      .width('100%')
      .backgroundColor('#F9FAFB')
      .borderRadius(8)
      .padding({ left: 16, right: 16 })

      if (this.isCheckingSession) {
        Row() {
          LoadingProgress()
            .width(16)
            .height(16)
            .color('#2563EB')
            .margin({ right: 8 })
          Text('正在更新登录状态')
            .fontSize(13)
            .fontColor('#6B7280')
        }
        .margin({ top: 18 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 20, right: 20, bottom: 112 })
  }

  @Builder
  private AnonymousContent() {
    Column() {
      Column() {
        if (this.isCheckingSession && !this.hasCheckedSession) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color('#2563EB')
            .margin({ bottom: 20 })
        } else {
          UserAvatar({
            user: {
              id: 0,
              username: '未登录'
            },
            avatarSize: 64
          })
        }

        Text(this.hasCheckedSession ? '未登录' : '检查登录状态')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .margin({ top: this.isCheckingSession && !this.hasCheckedSession ? 0 : 16 })

        Text(this.sessionMessage)
          .fontSize(14)
          .fontColor(this.requiresChallenge ? '#B45309' : '#6B7280')
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })

        if (!this.isCheckingSession || this.hasCheckedSession) {
          Button('登录 Linux.do')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor('#2563EB')
            .height(44)
            .padding({ left: 24, right: 24 })
            .borderRadius(8)
            .margin({ top: 24 })
            .onClick(() => {
              this.onLoginClick();
            })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 20, right: 20, bottom: 48 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor('#6B7280')
      Blank()
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(52)
  }

  private async checkCurrentUser(): Promise<void> {
    if (!this.isArkWebReady) {
      this.sessionMessage = '正在准备登录状态检查';
      return;
    }

    const requestId: number = this.requestSequence + 1;
    this.requestSequence = requestId;
    this.isCheckingSession = true;
    this.requiresChallenge = false;
    if (!this.hasCheckedSession) {
      this.sessionMessage = '正在检查登录状态';
    }

    const result: NetworkResult<User | undefined> = await new AuthService(this.bridge).getCurrentUser();
    if (requestId !== this.requestSequence) {
      return;
    }

    this.isCheckingSession = false;
    this.hasCheckedSession = true;

    if (result.success) {
      this.currentUser = result.data;
      this.sessionMessage = this.currentUser ? '当前账号已登录' : '当前没有登录账号';
      console.info(`${LOG_TAG} current user checked loggedIn=${this.currentUser !== undefined}`);
      return;
    }

    this.currentUser = undefined;
    this.requiresChallenge = result.error?.requiresChallenge === true;
    this.sessionMessage = result.error?.message ? result.error.message : '登录状态检查失败';
    console.info(`${LOG_TAG} current user check failed status=${result.statusCode} challenge=${result.challengeState}`);
  }

  private handleSessionChanged(version: number): void {
    if (version <= this.handledSessionVersion) {
      return;
    }

    this.handledSessionVersion = version;
    console.info(`${LOG_TAG} session changed version=${version}, check current user`);
    this.checkCurrentUser();
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady && !this.hasCheckedSession) {
      this.checkCurrentUser();
    }
  }

  private syncSessionVersion(): void {
    this.handleSessionChanged(SessionEventBus.getCurrentVersion());
  }

  private getDisplayName(): string {
    if (!this.currentUser) {
      return '';
    }
    return this.currentUser.displayName && this.currentUser.displayName.length > 0
      ? this.currentUser.displayName
      : this.currentUser.username;
  }

  private getUsernameLabel(): string {
    if (!this.currentUser) {
      return '';
    }
    return `@${this.currentUser.username}`;
  }

  private getUserIdLabel(): string {
    if (!this.currentUser) {
      return '';
    }
    return this.currentUser.id.toString();
  }
}
