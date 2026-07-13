import { Log } from '../../services/logging/Log';
import { bundleManager, common } from '@kit.AbilityKit';
import { DownloadService } from '../../services/content/DownloadService';
import { FileLogger } from '../../services/logging/FileLogger';
import { ThemeManager, ThemeMode } from '../../common/theme/ThemeManager';
import { DohManager, DohServer } from '../../services/network/DohManager';
import { FeedDef, FeedPrefs } from '../../services/site/FeedPrefs';

const LOG_TAG: string = '[ArkDO][Settings]';

// AppStorage 计数键:RootTabPage 在设置页 NavDestination onShown 时自增,驱动设置页重读
// DoH 摘要(单纯的 @Prop 不会随父 @State 流入已创建的 NavDestination 子树)。
export const SETTINGS_DOH_TICK: string = 'settings_doh_tick';

// 与个人中心同款鸿蒙设置页式卡片分组:灰底 + 无描边圆角卡片。
const PAGE_MARGIN: number = 12;
// 内容入口配置行高:拖动排序按此行高换算跟手位移与让位步长。
const FEED_ROW_H: number = 52;
const CARD_RADIUS: number = 16;
const CARD_PADDING: number = 16;
const CARD_GAP: number = 12;

// 设置与诊断日志:从个人中心页拆出的独立子页,由个人中心右上角齿轮入口 push 进入。
@Component
export struct SettingsPage {
  onBack: () => void = () => {};
  onOpenDoh: () => void = () => {};
  // 主动过盾:通知 RootTabPage 打开交互式 Cloudflare 验证页(唯一能真正拿到新 cf_clearance 的路径)。
  onActiveChallenge: () => void = () => {};
  @StorageLink('themeMode') themeMode: ThemeMode = ThemeMode.SYSTEM;
  // RootTabPage 在本页 NavDestination onShown 时自增此 AppStorage 计数(本页此刻已在前台,
  // @StorageProp 变更能可靠触发重渲染)。被 DoH 配置页覆盖后 pop 回来常驻不重建,靠它
  // @Watch 重读 DoH 摘要——不依赖 @Prop 流入(NavDestination 子树不随父 @State 重建)。
  @StorageProp(SETTINGS_DOH_TICK) @Watch('onSettingsShown') private dohTick: number = 0;
  // DoH 摘要:关闭显示"已关闭",启用显示当前生效服务器名;每次进入/重新可见即从 DohManager 重算。
  @State private dohSummary: string = '已关闭';
  @State private appVersion: string = '';
  // 日志工具:大小标签实时展示,详细日志开关持久化,导出时防重复点击。
  @State private logSizeLabel: string = '';
  @State private verboseLog: boolean = false;
  @State private isExportingLog: boolean = false;
  // 首页内容入口:启用且有序的可选入口 key(不含恒在的最新)。
  @State private enabledFeeds: string[] = [];
  // 拖动排序状态:draggingIndex=被拖行原始下标(-1 为未拖动);dragOffsetY=浮起行跟手位移;
  // hoverIndex=当前落位槽位(邻行据此实时让位)。松手后吸附到 hoverIndex 再提交顺序。
  @State private draggingIndex: number = -1;
  @State private dragOffsetY: number = 0;
  @State private hoverIndex: number = -1;

  aboutToAppear(): void {
    this.readAppVersion();
    this.verboseLog = FileLogger.isVerbose();
    this.refreshLogSize();
    this.refreshDohSummary();
    this.enabledFeeds = FeedPrefs.getEnabledKeys(getContext(this));
  }

  // NavDestination 重新可见(从 DoH 配置页 pop 回)时由 dohTick 变更触发,重读最新 DoH 摘要。
  private onSettingsShown(): void {
    this.refreshDohSummary();
  }

  // 直接从 DohManager 读当前开关与生效服务器,组装摘要文案;不依赖 @StorageProp 的跨页刷新。
  private refreshDohSummary(): void {
    const context: common.Context = getContext(this);
    const enabled: boolean = DohManager.isEnabled(context);
    const active: DohServer = DohManager.getActiveServer(context);
    this.dohSummary = enabled ? active.name : '已关闭';
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
            // 卡片:外观 / DoH / 刷新通行证 / 关于
            Column() {
              this.AppearanceCell()
              this.HairlineInset()
              this.DohCell()
              this.HairlineInset()
              // 主动过盾:打开交互式 CF 验证页(https://linux.do/challenge)手动过 Cloudflare。
              this.SettingCell($r('sys.symbol.checkmark_shield'), '刷新 Cloudflare 通行证', '', () => {
                this.onActiveChallenge();
              })
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

  // DoH 行单独成 Builder:直接读 this.dohSummary(而非当参数传给 SettingCell)。@Builder 的
  // 按值参数不随 @State 变化重渲染,而直接引用组件状态的 @Builder 会——这样切换 DoH pop 回来
  // 摘要文字才会真正刷新(参数式的 SettingCell 只有整页重建才更新)。
  @Builder
  private DohCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.security_shield'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Text('DoH 配置')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 14 })
      if (this.dohSummary.length > 0) {
        Text(this.dohSummary)
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ right: 6 })
      }
      this.ChevronIcon()
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
    .onClick(() => {
      this.onOpenDoh();
    })
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

      // 启用区:长按整行抬起、跟手拖动,邻行实时让位,松手吸附落位(只有启用项参与排序)。
      if (this.enabledFeeds.length > 0) {
        this.HairlineInset()
        Column() {
          ForEach(this.enabledFeeds, (key: string, index: number) => {
            this.EnabledFeedRow(key, index)
          }, (key: string) => key)
        }
        .width('100%')
        .clip(false)
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
  private EnabledFeedRow(key: string, index: number) {
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
    // 被拖行浮起在最上层;其余行按 hoverIndex 上下让位。
    .zIndex(this.draggingIndex === index ? 1 : 0)
    .translate({ y: this.rowTranslateY(index) })
    .scale(this.draggingIndex === index ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
    .shadow(this.draggingIndex === index
      ? { radius: 12, color: '#33000000', offsetY: 4 }
      : { radius: 0, color: Color.Transparent })
    // 长按抬起后转拖动:先长按拿到拖动权,再用竖向 Pan 跟手,避免与外层滚动抢手势。
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, duration: 300 })
          .onAction(() => this.beginDrag(index)),
        PanGesture({ direction: PanDirection.Vertical })
          .onActionUpdate((event: GestureEvent) => this.updateDrag(event.offsetY))
          .onActionEnd(() => this.endDrag())
          .onActionCancel(() => this.endDrag())
      )
    )
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
      .fontSize(18)
      .fontColor([$r('app.color.text_faint')])
  }

  // ==================== 外观 ====================

  private setThemeMode(mode: ThemeMode): void {
    ThemeManager.setMode(getContext(this), mode);
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

  // 被拖行浮起后,其余行让位的位移量:被拖行本身跟手,夹在原位与落位之间的行整体上/下移一格。
  private rowTranslateY(index: number): number {
    if (this.draggingIndex < 0) {
      return 0;
    }
    if (index === this.draggingIndex) {
      return this.dragOffsetY;
    }
    const from: number = this.draggingIndex;
    const to: number = this.hoverIndex;
    if (from < to && index > from && index <= to) {
      return -FEED_ROW_H;
    }
    if (from > to && index >= to && index < from) {
      return FEED_ROW_H;
    }
    return 0;
  }

  // 长按达成:抬起该行(轻微放大+投影),进入拖动。
  private beginDrag(index: number): void {
    this.hoverIndex = index;
    this.dragOffsetY = 0;
    animateTo({ duration: 150, curve: Curve.FastOutSlowIn }, () => {
      this.draggingIndex = index;
    });
  }

  // 拖动中:跟手位移(夹在启用区上下边界内),按半格阈值更新落位槽,邻行动画让位。
  private updateDrag(offsetY: number): void {
    if (this.draggingIndex < 0) {
      return;
    }
    const len: number = this.enabledFeeds.length;
    const maxUp: number = -this.draggingIndex * FEED_ROW_H;
    const maxDown: number = (len - 1 - this.draggingIndex) * FEED_ROW_H;
    let y: number = offsetY;
    if (y < maxUp) {
      y = maxUp;
    }
    if (y > maxDown) {
      y = maxDown;
    }
    this.dragOffsetY = y;
    let hover: number = this.draggingIndex + Math.round(y / FEED_ROW_H);
    if (hover < 0) {
      hover = 0;
    }
    if (hover > len - 1) {
      hover = len - 1;
    }
    if (hover !== this.hoverIndex) {
      animateTo({ duration: 180, curve: Curve.Friction }, () => {
        this.hoverIndex = hover;
      });
    }
  }

  // 松手:浮起行吸附到落位槽,动画结束后提交新顺序并清空拖动态(此刻数组与画面已一致,无跳变)。
  private endDrag(): void {
    if (this.draggingIndex < 0) {
      return;
    }
    const from: number = this.draggingIndex;
    const to: number = this.hoverIndex;
    animateTo({
      duration: 180,
      curve: Curve.FastOutSlowIn,
      onFinish: () => this.commitReorder(from, to)
    }, () => {
      this.dragOffsetY = (to - from) * FEED_ROW_H;
    });
  }

  private commitReorder(from: number, to: number): void {
    if (from >= 0 && to >= 0 && from !== to && from < this.enabledFeeds.length) {
      const next: string[] = this.enabledFeeds.slice();
      const moved: string[] = next.splice(from, 1);
      const target: number = to > next.length ? next.length : to;
      next.splice(target, 0, moved[0]);
      this.persistFeeds(next);
    }
    this.draggingIndex = -1;
    this.hoverIndex = -1;
    this.dragOffsetY = 0;
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
}
