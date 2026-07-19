import { Log } from '../../services/logging/Log';
import { bundleManager, common } from '@kit.AbilityKit';
import { DownloadService } from '../../services/content/DownloadService';
import { FileLogger } from '../../services/logging/FileLogger';
import { THEME_MODE_STORAGE_KEY, ThemeManager, ThemeMode } from '../../common/theme/ThemeManager';
import { DohManager, DohServer } from '../../services/network/DohManager';
import { FeedDef, FeedPrefs } from '../../services/site/FeedPrefs';
import { ChallengeShortcutPrefs } from '../../services/challenge/ChallengeShortcutPrefs';
import { SitePrefs } from '../../services/site/SitePrefs';
import { User } from '../../models/User';
import { PushRegistrationResult, PushStatusResult } from '../../services/push/PushSubscriptionService';
import { nextPushRefreshStart, PushRefreshStart } from '../../services/push/PushRefreshGate';
import { needsRelayConsent, PushRelayConfig, readCustomBaseUrl, resolvePushRelayConfig, saveCustomBaseUrl, saveRelayConsent } from '../../services/push/PushRelayConfig';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { showToast as promptToast } from '../../common/utils/Toast';
import { SETTINGS_DOH_TICK } from '../../common/constants/StorageKeys';
import { PageHeader } from '../components/PageHeader';
import { CARD_GAP, CARD_PADDING, CARD_RADIUS, PAGE_MARGIN } from '../../common/theme/Metrics';
import { SCRIM } from '../../common/theme/Palette';

const LOG_TAG: string = '[ArkDO][Settings]';

// AppStorage 计数键:RootTabPage 在设置页 NavDestination onShown 时自增,驱动设置页重读
// DoH 摘要(单纯的 @Prop 不会随父 @State 流入已创建的 NavDestination 子树)。

// 与个人中心同款鸿蒙设置页式卡片分组:灰底 + 无描边圆角卡片。
// 内容入口配置行高:拖动排序按此行高换算跟手位移与让位步长。
const FEED_ROW_H: number = 52;
// 测试推送冷却秒数,与中继的 RELAY_TEST_COOLDOWN 默认值对齐。
// 只影响本地按钮的倒计时展示;真正拦截在中继侧(按 subId,换设备重装都绕不过)。
const TEST_PUSH_COOLDOWN_SEC: number = 60;

// 设置与诊断日志:从个人中心页拆出的独立子页,由个人中心右上角齿轮入口 push 进入。
@Component
export struct SettingsPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  onOpenDoh: () => void = () => {};
  // 打开站内 Web 页:关于弹框里"开发者 @JoeyYin"跳 linux.do 个人资料页复用此链路,由 RootTabPage 注入。
  onOpenWeb: (url: string, title?: string) => void = () => {};
  // 主动过盾:通知 RootTabPage 打开交互式 Cloudflare 验证页(唯一能真正拿到新 cf_clearance 的路径)。
  onActiveChallenge: () => void = () => {};
  // 反馈与建议:打开站内反馈帖的原生详情页。本页拿不到 navPathStack,push 由 RootTabPage 注入。
  onOpenFeedback: () => void = () => {};
  // 系统推送:RootTabPage 注入,内部复用 ArkWeb 登录态完成 linux.do subscribe。
  // 必须是 @Prop:普通成员只在构造那一刻按值捕获,冷启动时会话校验还没回来就进本页的话,
  // 登录态会永久停在 false 的快照上,推送项一直显示"请先登录"、退出重进才好。
  // @Watch 在登录态真正落定(或登出/换号)时补刷一次推送状态。
  @Prop @Watch('onPushAccountChanged') currentUser: User = { id: 0, username: '' };
  @Prop @Watch('onPushAccountChanged') isLoggedIn: boolean = false;
  onEnablePush: () => Promise<PushRegistrationResult> = async () => {
    return { success: false, message: '推送服务未就绪' };
  };
  onDisablePush: () => Promise<PushRegistrationResult> = async () => {
    return { success: false, message: '推送服务未就绪' };
  };
  onRefreshPush: () => Promise<PushStatusResult> = async () => {
    return { enabled: false, message: '推送服务未就绪' };
  };
  onSendTestPush: () => Promise<PushStatusResult> = async () => {
    return { enabled: false, message: '推送服务未就绪' };
  };
  @StorageLink(THEME_MODE_STORAGE_KEY) themeMode: ThemeMode = ThemeMode.SYSTEM;
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
  // 帖子页过盾快捷入口开关(默认关),进页时从 preferences 载入。
  @State private challengeShortcutEnabled: boolean = false;
  @State private isExportingLog: boolean = false;
  @State private pushEnabled: boolean = false;
  @State private pushRegistering: boolean = false;
  @State private pushTesting: boolean = false;
  @State private pushStatus: string = '未开启';
  @State private relaySummary: string = '';
  // 测试推送冷却倒计时(秒)。>0 时按钮显示秒数且不可点,与中继侧的按 subId 冷却对齐——
  // 这里只是体验层反馈,真正的防线在中继(换设备/重装都绕不过)。
  @State private testCooldownLeft: number = 0;
  private testCooldownTimer: number = -1;
  private pushRefreshSequence: number = 0;
  // 上次已据以刷新过推送状态的账号身份(未登录为空串)。见 onPushAccountChanged 的去重说明。
  private lastPushAccountKey: string = '';
  // 首页内容入口:启用且有序的可选入口 key(不含恒在的最新)。
  @State private enabledFeeds: string[] = [];
  // 抽屉「我的站点」区总开关。站点不是 feed(点它是 push 页面而非切内容流),故不并入
  // feed_enabled_order 而用独立键:那个结构里空数组=全关,表达不了"默认开"。
  @State private sitesEntryEnabled: boolean = true;
  // 拖动排序状态:draggingIndex=被拖行原始下标(-1 为未拖动);dragOffsetY=浮起行跟手位移;
  // hoverIndex=当前落位槽位(邻行据此实时让位)。松手后吸附到 hoverIndex 再提交顺序。
  @State private draggingIndex: number = -1;
  @State private dragOffsetY: number = 0;
  @State private hoverIndex: number = -1;
  // 关于 ArkDO 弹框:含可点的"开发者 @JoeyYin"链接,纯文本 AlertDialog 做不到,故用 CustomDialog。
  // onOpenDeveloper 闭包内惰性读 this.onOpenWeb——字段初始化此刻父注入的 prop 尚为空壳,须调用时再取。
  // 使用本项目运营的中继前的一次性告知。同意后记住,不再重复打扰。
  private relayConsentDialog: CustomDialogController = new CustomDialogController({
    builder: RelayConsentDialog({
      onAccept: () => {
        this.acceptRelayConsent();
      },
      onDecline: () => {
        this.declineRelayConsent();
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    // 不允许点遮罩关闭:关掉了开关状态会含糊,必须明确选一个。
    autoCancel: false
  });
  // 中继地址输入框。initialUrl 每次打开时由 promptRelayBaseUrl 重新灌入(见其注释)。
  private relayDialog: CustomDialogController = new CustomDialogController({
    builder: RelayBaseUrlDialog({
      // 闭包内惰性读:字段初始化此刻 this 上的方法尚可用,但值须调用时再取。
      onConfirm: (baseUrl: string) => {
        this.applyRelayBaseUrl(baseUrl);
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true
  });
  private aboutDialogController: CustomDialogController = new CustomDialogController({
    builder: AboutDialog({
      onOpenDeveloper: () => {
        this.onOpenWeb('https://linux.do/u/joeyyin/', 'JoeyYin');
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.readAppVersion();
    this.verboseLog = FileLogger.isVerbose();
    this.loadChallengeShortcutEnabled();
    this.refreshLogSize();
    this.refreshDohSummary();
    this.enabledFeeds = FeedPrefs.getEnabledKeys(getContext(this));
    this.sitesEntryEnabled = SitePrefs.isEntryEnabled(getContext(this));
    // 与 onPushAccountChanged 共用去重基准:这里先记下挂载时的身份,避免 @Prop 首次同步
    // (对象换实例但账号没变)时白刷第二次。
    this.lastPushAccountKey = this.isLoggedIn ? `${this.currentUser.id}` : '';
    this.refreshRelaySummary();
    this.refreshPushState();
  }

  // 页面销毁时停掉冷却计时器,否则它会一直跑到 0 并持续触发已卸载组件的 @State 更新。
  aboutToDisappear(): void {
    this.stopTestCooldown();
  }

  // NavDestination 重新可见(从 DoH 配置页 pop 回)时由 dohTick 变更触发,重读最新 DoH 摘要。
  private onSettingsShown(): void {
    this.refreshDohSummary();
    this.refreshPushState();
  }

  // 中继地址摘要:显示当前实际生效的地址,并标明它来自随包配置还是用户自填。
  private refreshRelaySummary(): void {
    const context: common.Context = getContext(this);
    const custom: string = readCustomBaseUrl(context);
    const effective: PushRelayConfig = resolvePushRelayConfig(context);
    if (effective.baseUrl.length === 0) {
      this.relaySummary = '未配置，推送不可用';
      return;
    }
    this.relaySummary = custom.length > 0 ? `${effective.baseUrl}(自填)` : effective.baseUrl;
  }

  // 同意告知:记住选择,然后继续把推送开起来(此时 needsRelayConsent 已为 false,不会再弹)。
  private acceptRelayConsent(): void {
    saveRelayConsent(getContext(this), true);
    this.setPushEnabled(true);
  }

  // 谢绝:开关回到关闭态。这里的赋值有实际作用——弹框弹出前已乐观置 true,不改回来
  // 开关会停在"已开启"的样子,与实际状态不符。
  private declineRelayConsent(): void {
    this.pushEnabled = false;
    this.pushStatus = '未开启';
  }

  // 打开中继地址输入弹框。保存后重建服务实例(下次调用会重新解析配置),并刷新摘要。
  private promptRelayBaseUrl(): void {
    this.relayDialog.open();
  }

  private applyRelayBaseUrl(baseUrl: string): void {
    const context: common.Context = getContext(this);
    if (!saveCustomBaseUrl(context, baseUrl)) {
      this.showToast('中继地址无效，需以 https:// 开头');
      return;
    }
    this.refreshRelaySummary();
    this.showToast(baseUrl.trim().length > 0 ? '已保存中继地址' : '已恢复为默认中继');
    // 地址变了,已有订阅指向的是旧中继:提示用户重开推送以迁移到新地址。
    if (this.pushEnabled) {
      this.showToast('中继已变更，请关闭再重新开启推送');
    }
  }

  // 登录态/账号变化(会话校验落定、登出、换号):本页可能早在校验返回前就已构造,
  // 此时推送项停在"请先登录";登录态到位后据此补刷一次。
  // 必须按"账号身份"去重再刷:currentUser 每次会话轮询都是新对象(RootTabPage 里
  // `this.currentUser = result.data`,未登录时还每次新建匿名对象),@Watch 会被反复触发,
  // 不去重的话每轮轮询都会触发一次完整重注册(取 token → 中继 → linux.do 写请求)。
  private onPushAccountChanged(): void {
    const accountKey: string = this.isLoggedIn ? `${this.currentUser.id}` : '';
    if (accountKey === this.lastPushAccountKey) {
      return;
    }
    this.lastPushAccountKey = accountKey;
    Log.i(`${LOG_TAG} push account changed loggedIn=${this.isLoggedIn} userId=${this.currentUser.id}`);
    this.refreshPushState();
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
        PageHeader({
          title: '设置',
          onBack: () => {
            this.onBack();
          }
        })

        Scroll() {
          Column() {
            // 卡片:外观 / DoH / 刷新通行证
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
              this.ChallengeShortcutCell()
              this.HairlineInset()
              this.PushNotificationCell()
              // 测试推送紧跟开关:刚开完就想验一下是否真能收到,这是最顺的动线。
              // 中继地址属于"配置好就不再动"的项,排在后面。
              if (this.pushEnabled) {
                this.HairlineInset()
                this.TestPushNotificationCell()
              }
              this.HairlineInset()
              this.PushRelayCell()
            }
            .cardStyle()

            this.FeedGroup()

            this.AboutGroup()

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
      .padding({ top: this.sysTopInset })
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

  @Builder
  private PushNotificationCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.bell'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('系统推送通知')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.pushStatus)
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      if (this.pushRegistering) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('app.color.ld_accent'))
      } else {
        Toggle({ type: ToggleType.Switch, isOn: this.pushEnabled })
          .selectedColor($r('app.color.ld_accent'))
          .onChange((isOn: boolean) => {
            this.setPushEnabled(isOn);
          })
      }
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  // 中继地址:随包配置(relay-config.json,不进版本控制)缺失时,自行编译的用户靠这里填自己的中继。
  // 有随包配置时也允许覆盖,方便自建者切到自己的服务器。
  @Builder
  private PushRelayCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.wifi_router'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('推送中继地址')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.relaySummary)
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      this.ChevronIcon()
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
    .onClick(() => {
      this.promptRelayBaseUrl();
    })
  }

  @Builder
  private TestPushNotificationCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.paperplane'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('发送测试推送')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('验证华为推送与点击跳转')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      if (this.pushTesting) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('app.color.ld_accent'))
      } else if (this.testCooldownLeft > 0) {
        // 冷却中显示剩余秒数:让用户知道为什么点不动,而不是默默失败。
        Text(`${this.testCooldownLeft}s`)
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ right: 6 })
      } else {
        Text('发送')
          .fontSize(13)
          .fontColor($r('app.color.ld_accent'))
          .margin({ right: 6 })
        this.ChevronIcon()
      }
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
    .onClick(() => {
      this.sendTestPush();
    })
  }

  // 关于组:反馈入口直开站内反馈帖;关于弹框展示版本号与开发者链接。
  @Builder
  private AboutGroup() {
    this.GroupLabel('关于')
    Column() {
      this.SettingCell($r('sys.symbol.message'), '反馈与建议', '', () => {
        this.onOpenFeedback();
      })
      this.HairlineInset()
      this.SettingCell($r('sys.symbol.info_circle'), '关于 ArkDO', this.getVersionLabel(), () => {
        this.aboutDialogController.open();
      })
    }
    .cardStyle()
    // GroupLabel 自带 18 上内边距,抹平 cardStyle 的 12 上外边距,免得组标题与卡片间空一截。
    .margin({ top: 0 })
  }

  // 帖子页过盾快捷入口开关。默认关:多数人从不撞盾,常驻入口只会碍眼。
  // 打开也不等于常驻——还要真的探测到阅读上报被 CF 拦下才亮(见 ChallengeShortcutEventBus)。
  @Builder
  private ChallengeShortcutCell() {
    Row() {
      SymbolGlyph($r('sys.symbol.lock_shield'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
      Column() {
        Text('帖子页显示过盾入口')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('阅读被 CF 拦截时，帖子右上角出现快捷验证')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.challengeShortcutEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.challengeShortcutEnabled = isOn;
          ChallengeShortcutPrefs.setEnabled(getContext(this), isOn);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
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
          Text('完整记录响应内容，排查时开启')
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

      // 我的站点:独立开关,不参与上面那套启用/排序(站点之间的排序在站点管理页里做)。
      this.HairlineInset()
      this.SitesEntryRow()
    }
    .cardStyle()
    .clip(true)
    .margin({ top: 0 })
  }

  @Builder
  private SitesEntryRow() {
    Row() {
      Column() {
        Text('我的站点')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('在侧边栏显示站点入口')
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.sitesEntryEnabled })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          this.setSitesEntryEnabled(isOn);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
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
      ? { radius: 12, color: SCRIM, offsetY: 4 }
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

  private async loadChallengeShortcutEnabled(): Promise<void> {
    this.challengeShortcutEnabled = await ChallengeShortcutPrefs.load(getContext(this));
  }

  private async setPushEnabled(isOn: boolean): Promise<void> {
    if (this.pushRegistering) {
      return;
    }
    // 乐观跟随用户拨动:失败/取消时再纠正回来。必须先赋值——否则 @State 的值没变化就
    // 不会重渲染,Toggle 会停在用户拨过去的位置,和实际状态对不上。
    this.pushEnabled = isOn;
    if (!this.isLoggedIn || this.currentUser.id <= 0) {
      this.pushEnabled = false;
      this.pushStatus = '请先登录 linux.do';
      this.showToast(this.pushStatus);
      return;
    }

    // 首次用本项目运营的中继开推送前,先把数据流向讲清楚并征得同意。
    // 自建中继的用户不弹(数据只经过他自己的机器);同意过一次就不再打扰。
    if (isOn && needsRelayConsent(getContext(this))) {
      this.relayConsentDialog.open();
      return;
    }

    this.pushRegistering = true;
    this.pushStatus = isOn ? '正在注册' : '正在关闭';
    let result: PushRegistrationResult;
    try {
      result = isOn ? await this.onEnablePush() : await this.onDisablePush();
    } catch (err) {
      Log.i(`${LOG_TAG} push toggle exception target=${isOn} error=${JSON.stringify(err)}`);
      result = {
        success: false,
        message: isOn ? '推送注册异常' : '推送关闭异常'
      };
    }
    Log.i(`${LOG_TAG} push toggle result target=${isOn} success=${result.success} message=${result.message}`);
    this.pushRegistering = false;
    this.pushEnabled = isOn ? result.success : !result.success;
    this.pushStatus = result.success ? (isOn ? '已开启' : '未开启') : result.message;
    this.showToast(result.message);
  }

  private async sendTestPush(): Promise<void> {
    if (this.pushTesting || this.pushRegistering) {
      return;
    }
    if (this.testCooldownLeft > 0) {
      this.showToast(`请 ${this.testCooldownLeft} 秒后再试`);
      return;
    }
    if (!this.isLoggedIn || this.currentUser.id <= 0) {
      this.showToast('请先登录 linux.do');
      return;
    }
    if (!this.pushEnabled) {
      this.showToast('请先开启系统推送通知');
      return;
    }

    this.pushTesting = true;
    let result: PushStatusResult;
    try {
      result = await this.onSendTestPush();
    } catch (err) {
      Log.i(`${LOG_TAG} push test exception error=${JSON.stringify(err)}`);
      result = {
        enabled: false,
        message: '测试推送发送异常'
      };
    }
    this.pushTesting = false;
    this.showToast(result.message);
    // 无论成败都进入冷却:失败多半就是撞上了中继的冷却,此时更不该让用户继续猛点。
    this.startTestCooldown();
  }

  // 本地倒计时,与中继的按 subId 冷却窗口对齐(默认 60s)。
  private startTestCooldown(): void {
    this.stopTestCooldown();
    this.testCooldownLeft = TEST_PUSH_COOLDOWN_SEC;
    this.testCooldownTimer = setInterval(() => {
      this.testCooldownLeft--;
      if (this.testCooldownLeft <= 0) {
        this.stopTestCooldown();
      }
    }, 1000);
  }

  private stopTestCooldown(): void {
    if (this.testCooldownTimer !== -1) {
      clearInterval(this.testCooldownTimer);
      this.testCooldownTimer = -1;
    }
    this.testCooldownLeft = 0;
  }

  private async refreshPushState(): Promise<void> {
    if (!this.isLoggedIn || this.currentUser.id <= 0) {
      this.pushEnabled = false;
      this.pushStatus = '请先登录 linux.do';
      return;
    }
    const start: PushRefreshStart = nextPushRefreshStart(this.pushRefreshSequence, this.pushRegistering);
    if (!start.shouldStart) {
      return;
    }
    const sequence: number = start.sequence;
    this.pushRefreshSequence = sequence;
    this.pushRegistering = true;
    this.pushStatus = '检查中';
    let result: PushStatusResult;
    try {
      result = await this.onRefreshPush();
    } catch (err) {
      Log.i(`${LOG_TAG} push refresh exception error=${JSON.stringify(err)}`);
      result = {
        enabled: false,
        message: '推送状态检查失败'
      };
    }
    if (sequence !== this.pushRefreshSequence) {
      return;
    }
    this.pushRegistering = false;
    this.pushEnabled = result.enabled;
    this.pushStatus = result.message;
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

  // 站点入口开关:首页每次开抽屉都重读 preferences,故写完即生效,无需通知首页。
  private setSitesEntryEnabled(enabled: boolean): void {
    this.sitesEntryEnabled = enabled;
    SitePrefs.setEntryEnabled(getContext(this), enabled);
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
    promptToast(this.getUIContext(), message);
  }
}

// 使用本项目运营的中继前的一次性告知。
// 文案刻意不写"不收集任何数据"——中继解密后确实看得到通知标题与摘要,那是它的工作原理。
// 与其含糊其辞,不如把数据怎么流、我们不做什么讲清楚,并给出自建中继的出路。
// 排版上把大段说明拆成"一句话 + 三条要点",避免堆成一屏像法律条款没人看。
@CustomDialog
struct RelayConsentDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: RelayConsentDialog({}) });
  onAccept: () => void = () => {};
  onDecline: () => void = () => {};

  // 流程节点标签。四个节点要挤进弹框宽度,故字号与内边距都压得较小。
  @Builder
  private FlowChip(label: string) {
    Text(label)
      .fontSize(10.5)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 7, right: 7, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(6)
      .maxLines(1)
  }

  @Builder
  private FlowArrow() {
    SymbolGlyph($r('sys.symbol.arrow_right'))
      .fontSize(9)
      .fontColor([$r('app.color.text_faint')])
      .margin({ left: 3, right: 3 })
  }

  // 单条要点:小图标 + 一句话。图标顶对齐,文案换行时不会与图标错位。
  @Builder
  private PointRow(symbol: Resource, text: string) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(15)
        .fontColor([$r('app.color.text_faint')])
        .margin({ top: 2 })
      Text(text)
        .fontSize(13.5)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .margin({ left: 10 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 10 })
  }

  build() {
    Column() {
      // 顶部图标:给纯文字的告知一个视觉落点,避免一上来就是一屏字。
      Column() {
        SymbolGlyph($r('sys.symbol.bell_fill'))
          .fontSize(26)
          .fontColor([$r('app.color.ld_accent')])
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor($r('app.color.surface_muted'))
      .justifyContent(FlexAlign.Center)
      .margin({ top: 26, bottom: 14 })

      Text('开启推送前')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)

      // 点名 Discourse:通知走的是它的标准 Web Push 机制,不是我们自造的一套。
      // 说清出处比空口承诺更能建立信任,懂行的人也能自行验证。
      Text('LinuxDO 使用 Discourse 论坛程序，通知按其标准的 Web Push 协议加密发出')
        .fontSize(13)
        .lineHeight(19)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ left: 26, right: 26 })
        .margin({ top: 8, bottom: 16 })

      // 数据流向可视化:一眼看清经过谁、到哪去,比一段话更好读。
      Row() {
        this.FlowChip('Discourse')
        this.FlowArrow()
        this.FlowChip('中继')
        this.FlowArrow()
        this.FlowChip('华为推送')
        this.FlowArrow()
        this.FlowChip('你的手机')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 18 })

      // 三条要点:第一条讲清代价(诚实),后两条讲清边界(安心)。
      Column() {
        this.PointRow($r('sys.symbol.paperplane'), '中继需要解密才能转发，因此通知的标题和摘要会经过它')
        this.PointRow($r('sys.symbol.eye_slash'), '不保存这些内容，也不用作其他用途')
        this.PointRow($r('sys.symbol.lock_fill'), '中继上没有你的账号密码或登录凭证')
      }
      .width('100%')
      .padding({ left: 24, right: 24 })

      // 「已开源」这句是前面三条承诺的兑现凭据:不必信我们的说法,代码可自行查验。
      Text('想让数据只经过自己的机器？可在「推送中继地址」填入自建中继。中继代码已开源')
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
        .margin({ top: 16, bottom: 20 })

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))

      Row() {
        Button('暂不开启')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.onDecline();
            this.controller.close();
          })

        Divider()
          .vertical(true)
          .strokeWidth(0.5)
          .height(24)
          .color($r('app.color.border'))

        Button('明白了，开启')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
          .onClick(() => {
            this.onAccept();
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width('86%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('sys.float.ohos_id_corner_radius_dialog'))
    .clip(true)
  }
}

// 自建中继地址输入框。样式对齐同仓 AddDohDialog(原生鸿蒙 AlertDialog 风格)。
@CustomDialog
struct RelayBaseUrlDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: RelayBaseUrlDialog({}) });
  onConfirm: (baseUrl: string) => void = () => {};
  @State private url: string = '';

  // 自己读当前值,不由父页注入:CustomDialogController 在字段初始化时就固定了 builder 参数,
  // 外部注入的值会停在构造那一刻,改完再打开会显示旧值。
  aboutToAppear(): void {
    this.url = readCustomBaseUrl(getContext(this));
  }

  build() {
    Column() {
      Text('推送中继地址')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 22, bottom: 10 })

      Text('填写自建中继的地址。留空则使用应用自带配置。\n部署方法见项目仓库 server/ 目录。')
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
        .margin({ bottom: 16 })

      Column() {
        TextInput({ placeholder: 'https://push.example.com', text: this.url })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .onChange((value: string) => {
            this.url = value;
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .margin({ bottom: 20 })

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.border'))

      Row() {
        Button('取消')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.controller.close();
          })

        Divider()
          .vertical(true)
          .strokeWidth(0.5)
          .height(24)
          .color($r('app.color.border'))

        Button('保存')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
          .onClick(() => {
            // 校验交给调用方(saveCustomBaseUrl 统一做 https 校验),这里只负责回传。
            this.onConfirm(this.url);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width('86%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('sys.float.ohos_id_corner_radius_dialog'))
    .clip(true)
  }
}

// 关于 ArkDO 信息框:应用名 + 简介 + 版本(运行时读 bundleManager)+ 可点开发者链接 + 关闭。
// 版本自读而非由父按值传入,规避 CustomDialogController 字段初始化按值捕获空版本号。
@CustomDialog
struct AboutDialog {
  controller?: CustomDialogController;
  onOpenDeveloper: () => void = () => {};
  @State private version: string = '';

  aboutToAppear(): void {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.version = info.versionName;
    } catch (err) {
      Log.i(`${LOG_TAG} about dialog read version failed`);
    }
  }

  build() {
    Column() {
      Text('ArkDO')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text('Linux.do 第三方鸿蒙客户端')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })

      Text(this.version.length > 0 ? `版本 v${this.version}` : '版本 —')
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .margin({ top: 14 })

      Row() {
        Text('开发者 ')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        Text('@JoeyYin')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
          .onClick(() => {
            this.controller?.close();
            this.onOpenDeveloper();
          })
      }
      .margin({ top: 6 })

      Button('关闭')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .width('100%')
        .height(44)
        .borderRadius(22)
        .margin({ top: 24 })
        .onClick(() => {
          this.controller?.close();
        })
    }
    .width('82%')
    .padding({ left: 24, right: 24, top: 28, bottom: 20 })
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(20)
    .alignItems(HorizontalAlign.Center)
  }
}
