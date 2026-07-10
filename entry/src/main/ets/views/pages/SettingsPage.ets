import { Log } from '../../services/logging/Log';
import { bundleManager, common } from '@kit.AbilityKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { DownloadService } from '../../services/content/DownloadService';
import { FileLogger } from '../../services/logging/FileLogger';
import { ThemeManager, ThemeMode } from '../../common/theme/ThemeManager';
import { DohManager } from '../../services/network/DohManager';
import { FeedDef, FeedPrefs } from '../../services/site/FeedPrefs';

const LOG_TAG: string = '[ArkDO][Settings]';

// 与个人中心同款鸿蒙设置页式卡片分组:灰底 + 无描边圆角卡片。
const PAGE_MARGIN: number = 12;
// 内容入口配置行高(启用区拖动排序 List 需按项数定高,避免与外层 Scroll 抢滚动)。
const FEED_ROW_H: number = 52;
const CARD_RADIUS: number = 16;
const CARD_PADDING: number = 16;
const CARD_GAP: number = 12;

// 设置与诊断日志:从个人中心页拆出的独立子页,由个人中心右上角齿轮入口 push 进入。
@Component
export struct SettingsPage {
  // 账号与安全入口仅登录态可用,用户名用于拼站内偏好页链接。
  isLoggedIn: boolean = false;
  username: string = '';
  onBack: () => void = () => {};
  onOpenWeb: (url: string, title?: string) => void = () => {};
  onOpenDoh: () => void = () => {};
  // 主动过盾:通知 RootTabPage 打开交互式 Cloudflare 验证页(唯一能真正拿到新 cf_clearance 的路径)。
  onActiveChallenge: () => void = () => {};
  @StorageLink('themeMode') themeMode: ThemeMode = ThemeMode.SYSTEM;
  @State private dohSummary: string = '';
  @State private appVersion: string = '';
  // 日志工具:大小标签实时展示,详细日志开关持久化,导出时防重复点击。
  @State private logSizeLabel: string = '';
  @State private verboseLog: boolean = false;
  @State private isExportingLog: boolean = false;
  // 首页内容入口:启用且有序的可选入口 key(不含恒在的最新)。
  @State private enabledFeeds: string[] = [];

  aboutToAppear(): void {
    this.readAppVersion();
    this.verboseLog = FileLogger.isVerbose();
    this.refreshLogSize();
    this.refreshDohSummary();
    this.enabledFeeds = FeedPrefs.getEnabledKeys(getContext(this));
  }

  // 卡片分组容器:无描边,靠灰底衬托。
  @Styles
  cardStyle() {
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(CARD_RADIUS)
    .margin({ top: CARD_GAP })
  }

  build() {
    Stack() {
      // 背景层:灰底延伸进顶部状态栏与底部导航条区域;内容层不扩展,照常避让。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg_gray'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(28)
              .fontColor([$r('app.color.text_primary')])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          }
          .width(40)
          .height(40)
          .backgroundColor($r('app.color.surface_muted'))
          .onClick(() => {
            this.onBack();
          })

          Text('设置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 8 })

        Scroll() {
          Column() {
            // 卡片:外观 / DoH / 账号与安全 / 关于
            Column() {
              this.AppearanceCell()
              this.HairlineInset()
              this.SettingCell($r('sys.symbol.security_shield'), 'DoH 配置', this.dohSummary, () => {
                this.onOpenDoh();
              })
              this.HairlineInset()
              // 主动过盾:打开交互式 CF 验证页(https://linux.do/challenge)手动过 Cloudflare。
              this.SettingCell($r('sys.symbol.checkmark_shield'), '刷新 Cloudflare 通行证', '', () => {
                this.onActiveChallenge();
              })
              if (this.isLoggedIn) {
                this.HairlineInset()
                this.SettingCell($r('sys.symbol.security_shield'), '账号与安全', '', () => {
                  this.openUserWebPage('/preferences/security', '账号与安全');
                })
              }
              this.HairlineInset()
              this.SettingCell($r('sys.symbol.info_circle'), '关于 ArkDO', this.getVersionLabel(), undefined)
            }
            .cardStyle()
            .margin({ top: 0 })

            this.FeedGroup()

            this.LogGroup()

            Row()
              .width('100%')
              .height(40)
          }
          .width('100%')
          .padding({ left: PAGE_MARGIN, right: PAGE_MARGIN })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
  }

  // ==================== Builder ====================

  @Builder
  private AppearanceCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.dark_mode'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Text('外观')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 14 })
      Text(this.getThemeModeLabel())
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .margin({ right: 6 })
      this.ChevronIcon()
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
    .bindMenu([
      {
        value: '跟随系统',
        action: (): void => {
          this.setThemeMode(ThemeMode.SYSTEM);
        }
      },
      {
        value: '浅色',
        action: (): void => {
          this.setThemeMode(ThemeMode.LIGHT);
        }
      },
      {
        value: '深色',
        action: (): void => {
          this.setThemeMode(ThemeMode.DARK);
        }
      }
    ])
  }

  @Builder
  private SettingCell(symbol: Resource, label: string, value: string, onCellClick?: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 14 })
      if (value.length > 0) {
        Text(value)
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ right: 6 })
      }
      if (onCellClick !== undefined) {
        this.ChevronIcon()
      }
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
    .onClick(() => {
      if (onCellClick !== undefined) {
        onCellClick();
      }
    })
  }

  // 诊断日志工具组:导出(带大小)、详细日志开关、清空。用于用户脱机跑一天后导出日志分析。
  @Builder
  private LogGroup() {
    this.GroupLabel('诊断日志')
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.envelope'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
        Text('导出日志')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .margin({ left: 14 })
        if (this.isExportingLog) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.ld_accent'))
            .margin({ right: 6 })
        } else if (this.logSizeLabel.length > 0) {
          Text(this.logSizeLabel)
            .fontSize(13)
            .fontColor($r('app.color.text_faint'))
            .margin({ right: 6 })
        }
        this.ChevronIcon()
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
      .onClick(() => {
        this.exportLog();
      })

      this.HairlineInset()

      Row() {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
        Column() {
          Text('详细日志')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text('完整记录响应内容,排查时开启')
            .fontSize(12)
            .fontColor($r('app.color.text_faint'))
            .width('100%')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .margin({ left: 14 })
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.verboseLog })
          .selectedColor($r('app.color.ld_accent'))
          .onChange((isOn: boolean) => {
            this.setVerboseLog(isOn);
          })
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })

      this.HairlineInset()

      Row() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([$r('app.color.ld_danger')])
        Text('清空日志')
          .fontSize(15)
          .fontColor($r('app.color.ld_danger'))
          .layoutWeight(1)
          .margin({ left: 14 })
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
      .onClick(() => {
        this.confirmClearLog();
      })
    }
    .cardStyle()
    .margin({ top: 0 })
  }

  // 首页内容入口:最新恒在(默认、不可关不可拖);可选入口勾选启用,启用项可拖动排序。
  @Builder
  private FeedGroup() {
    this.GroupLabel('首页内容入口')
    Column() {
      // 最新:默认入口,常驻不可配。
      Row() {
        Text('最新')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('默认')
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
      }
      .width('100%')
      .height(FEED_ROW_H)
      .padding({ left: CARD_PADDING, right: CARD_PADDING })

      // 启用区:长按拖动排序(只有启用项参与排序)。
      if (this.enabledFeeds.length > 0) {
        this.HairlineInset()
        List() {
          ForEach(this.enabledFeeds, (key: string) => {
            ListItem() {
              this.EnabledFeedRow(key)
            }
          }, (key: string) => key)
        }
        .width('100%')
        .height(this.enabledFeeds.length * FEED_ROW_H)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
          return this.FeedDragPreview(this.enabledFeeds[itemIndex]);
        })
        .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
          this.reorderFeed(itemIndex, insertIndex, isSuccess);
        })
      }

      // 未启用区:关闭态,勾选即启用(移入启用区末尾)。
      if (this.disabledFeeds().length > 0) {
        this.HairlineInset()
        ForEach(this.disabledFeeds(), (feed: FeedDef) => {
          this.DisabledFeedRow(feed)
        }, (feed: FeedDef) => feed.key)
      }
    }
    .cardStyle()
    .clip(true)
    .margin({ top: 0 })
  }

  @Builder
  private EnabledFeedRow(key: string) {
    Row() {
      this.DragHandle()
      Text(this.feedLabel(key))
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: true })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          if (!isOn) {
            this.disableFeed(key);
          }
        })
    }
    .width('100%')
    .height(FEED_ROW_H)
    .padding({ left: CARD_PADDING, right: CARD_PADDING })
    .backgroundColor($r('app.color.surface_card'))
  }

  @Builder
  private DisabledFeedRow(feed: FeedDef) {
    Row() {
      Text(feed.label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
      if (feed.requiresLogin) {
        Text('需登录')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .margin({ left: 8 })
      }
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: false })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          if (isOn) {
            this.enableFeed(feed.key);
          }
        })
    }
    .width('100%')
    .height(FEED_ROW_H)
    .padding({ left: CARD_PADDING, right: CARD_PADDING })
  }

  // 拖动手柄:三条短发丝线,提示可拖(实际拖动靠长按整行)。
  @Builder
  private DragHandle() {
    Column({ space: 3 }) {
      Divider().width(14).strokeWidth(1.5).color($r('app.color.text_faint'))
      Divider().width(14).strokeWidth(1.5).color($r('app.color.text_faint'))
      Divider().width(14).strokeWidth(1.5).color($r('app.color.text_faint'))
    }
    .justifyContent(FlexAlign.Center)
    .width(16)
  }

  // 拖动时的浮层预览:显示被拖入口的标签。
  @Builder
  private FeedDragPreview(key: string) {
    Row() {
      Text(this.feedLabel(key))
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
    }
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(10)
  }

  @Builder
  private HairlineInset() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.border'))
      .margin({ left: CARD_PADDING, right: CARD_PADDING })
  }

  @Builder
  private GroupLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.text_faint'))
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 18, bottom: 8 })
  }

  @Builder
  private ChevronIcon() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(14)
      .fontColor([$r('app.color.text_faint')])
  }

  // ==================== 外观 ====================

  private setThemeMode(mode: ThemeMode): void {
    ThemeManager.setMode(getContext(this), mode);
  }

  private refreshDohSummary(): void {
    const context: common.Context = getContext(this);
    if (!DohManager.isEnabled(context)) {
      this.dohSummary = '已关闭';
      return;
    }
    this.dohSummary = DohManager.getActiveServer(context).name;
  }

  private getThemeModeLabel(): string {
    if (this.themeMode === ThemeMode.LIGHT) {
      return '浅色';
    }
    if (this.themeMode === ThemeMode.DARK) {
      return '深色';
    }
    return '跟随系统';
  }

  // ==================== 诊断日志 ====================

  private refreshLogSize(): void {
    this.logSizeLabel = this.formatBytes(FileLogger.getTotalSizeBytes());
  }

  private formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '空';
    }
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  private exportLog(): void {
    if (this.isExportingLog) {
      return;
    }
    this.isExportingLog = true;
    // 合并落盘 + 拉起系统分享面板(复用附件分享链路),用户可选邮件/IM 发出。
    const exportPath: string = FileLogger.exportToFile();
    this.isExportingLog = false;
    this.refreshLogSize();
    if (exportPath.length === 0) {
      this.showToast('日志导出失败,请稍后重试');
      return;
    }
    DownloadService.openWithSystem(getContext(this) as common.UIAbilityContext, exportPath);
  }

  private setVerboseLog(isOn: boolean): void {
    this.verboseLog = isOn;
    FileLogger.setVerbose(getContext(this), isOn);
  }

  private confirmClearLog(): void {
    this.getUIContext().showAlertDialog({
      title: '清空日志',
      message: '确定要清空本机所有日志吗?此操作不可恢复。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.ld_danger'),
        action: () => {
          FileLogger.clear();
          this.refreshLogSize();
          this.showToast('日志已清空');
        }
      }
    });
  }

  // ==================== 首页内容入口 ====================

  private feedLabel(key: string): string {
    const def: FeedDef | undefined = FeedPrefs.feedDef(key);
    return def ? def.label : key;
  }

  // 未启用的可选入口(保持 optionalFeeds 原始顺序)。
  private disabledFeeds(): FeedDef[] {
    const all: FeedDef[] = FeedPrefs.optionalFeeds();
    const result: FeedDef[] = [];
    for (let index: number = 0; index < all.length; index++) {
      if (this.enabledFeeds.indexOf(all[index].key) < 0) {
        result.push(all[index]);
      }
    }
    return result;
  }

  private enableFeed(key: string): void {
    if (this.enabledFeeds.indexOf(key) >= 0) {
      return;
    }
    const next: string[] = this.enabledFeeds.slice();
    next.push(key);
    this.persistFeeds(next);
  }

  private disableFeed(key: string): void {
    const next: string[] = this.enabledFeeds.slice();
    const index: number = next.indexOf(key);
    if (index < 0) {
      return;
    }
    next.splice(index, 1);
    this.persistFeeds(next);
  }

  private reorderFeed(fromIndex: number, insertIndex: number, isSuccess: boolean): void {
    if (!isSuccess || fromIndex < 0 || insertIndex < 0 || fromIndex === insertIndex) {
      return;
    }
    const next: string[] = this.enabledFeeds.slice();
    if (fromIndex >= next.length) {
      return;
    }
    const moved: string[] = next.splice(fromIndex, 1);
    const target: number = insertIndex > next.length ? next.length : insertIndex;
    next.splice(target, 0, moved[0]);
    this.persistFeeds(next);
  }

  private persistFeeds(keys: string[]): void {
    this.enabledFeeds = keys;
    FeedPrefs.setEnabledKeys(getContext(this), keys);
  }

  // ==================== 辅助 ====================

  private readAppVersion(): void {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = info.versionName;
    } catch (err) {
      Log.i(`${LOG_TAG} read app version failed`);
    }
  }

  private getVersionLabel(): string {
    return this.appVersion.length > 0 ? `v${this.appVersion}` : '';
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Log.i(`${LOG_TAG} toast failed: ${message}`);
    }
  }

  private openUserWebPage(subPath: string, title?: string): void {
    if (this.username.length === 0) {
      return;
    }
    this.onOpenWeb(`${AppConstants.BASE_URL}/u/${encodeURIComponent(this.username)}${subPath}`, title);
  }
}
