import { Log } from '../../services/logging/Log';
import webview from '@ohos.web.webview';
import { AppConstants } from '../../common/constants/AppConstants';
import { WebSessionManager } from '../../services/web/WebSessionManager';
import { CONNECT_EXTRACT_SCRIPT, ConnectLevelParser } from '../../services/connect/ConnectLevelParser';
import {
  ConnectBarItem,
  ConnectLevelData,
  ConnectQuotaItem,
  ConnectRingItem,
  ConnectVetoItem
} from '../../models/ConnectLevel';

const LOG_TAG: string = '[ArkDO][LevelProgress]';

// 页面布局:两侧留白 12,卡片圆角/内距对齐 connect(--radius-lg 16 / --sp-4 16)。
const PAGE_MARGIN: number = 12;
const CARD_RADIUS: number = 16;
const CARD_PADDING: number = 16;
const SECTION_TOP: number = 20;
const SECTION_BOTTOM: number = 16;

// connect 的半透明描边/图标底(rgba → #AARRGGBB)。0.2≈0x33,0.15≈0x26。
const BORDER_SUCCESS: string = '#3322C55E';
const BORDER_DANGER: string = '#33EF4444';
const ICONBG_SUCCESS: string = '#2622C55E';
const ICONBG_DANGER: string = '#26EF4444';

// connect 进度条填充渐变(met 绿 #22c55e→#4ade80 / unmet 橙 #f59e0b→#fbbf24)。
const BAR_GRADIENT_MET: Array<[ResourceColor, number]> = [['#22C55E', 0.0], ['#4ADE80', 1.0]];
const BAR_GRADIENT_UNMET: Array<[ResourceColor, number]> = [['#F59E0B', 0.0], ['#FBBF24', 1.0]];

// 就绪超时:SSO 跳转/挑战页始终不出「升级要求」卡片时,兜底进错误态而非永久转圈。
const READY_TIMEOUT_MS: number = 20000;

enum LoadPhase {
  LOADING = 0,
  READY = 1,
  ERROR = 2,
  ANON = 3
}

/**
 * 等级进度页:从个人中心信任等级标进入。
 * connect.linux.do 与 linux.do 不同源,host webview 跨域 fetch 会被 CORS 挡;
 * 故本页自持一个隐藏 Web 真加载 connect.linux.do(经 SSO 复用会话自动登录),
 * onPageEnd 后注入脚本把服务端渲染的数值抠成 JSON,再用 ArkUI 原生按 connect 配色重画。
 */
@Component
export struct LevelProgressPage {
  @Prop isLoggedIn: boolean = false;
  onBack: () => void = () => {};
  // 兜底:解析失败时可在内置浏览器直接打开 connect.linux.do。
  onOpenWeb: (url: string, title?: string) => void = () => {};

  private controller: webview.WebviewController = new webview.WebviewController();
  @State private phase: LoadPhase = LoadPhase.LOADING;
  @State private data?: ConnectLevelData = undefined;
  private settled: boolean = false;
  private timers: number[] = [];
  // 主框架加载失败(DoH 偶发解析失败/连接被 RST)时自动重载的已用次数,超上限才提示失败。
  private reloadCount: number = 0;

  aboutToAppear(): void {
    WebSessionManager.configureCookieAccess('LevelProgress');
    if (!this.isLoggedIn) {
      this.phase = LoadPhase.ANON;
      return;
    }
    this.startTimeout();
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  build() {
    Stack() {
      // 隐藏 Web:满视口 + 近透明,被上层不透明内容完全遮挡;满视口给 CF/SSO 一个真实浏览器环境。
      if (this.isLoggedIn) {
        Web({ src: AppConstants.CONNECT_URL, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .databaseAccess(true)
          .imageAccess(true)
          .onlineImageAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.Default)
          .onControllerAttached(() => {
            WebSessionManager.applyUserAgent(this.controller, 'LevelProgress');
          })
          .onPageBegin((event: OnPageBeginEvent) => {
            Log.i(`${LOG_TAG} pageBegin url=${event.url}`);
          })
          .onPageEnd((event: OnPageEndEvent) => {
            Log.i(`${LOG_TAG} pageEnd url=${event.url}`);
            this.onConnectPageEnd();
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            // 主框架加载失败会给出网络错误码(ERR_NAME_NOT_RESOLVED / ERR_CONNECTION_RESET
            // / ERR_TIMED_OUT 等):DNS 没解析、TLS 被 RST(需 ECH)或纯超时。DoH 偶发抽风时
            // 重连一次多能成,故主框架错误自动重载兜底,超上限才快速进错误态(不必干等 20s)。
            const isMainFrame: boolean = event.request.isMainFrame();
            Log.i(`${LOG_TAG} errorReceive isMainFrame=${isMainFrame} url=${event.request.getRequestUrl()} code=${event.error.getErrorCode()} info=${event.error.getErrorInfo()}`);
            this.onMainFrameError(isMainFrame);
          })
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
            Log.i(`${LOG_TAG} httpError url=${event.request.getRequestUrl()} status=${event.response.getResponseCode()}`);
          })
          .width('100%')
          .height('100%')
          .opacity(0.01)
      }

      Column() {
        this.TitleBar()

        Scroll() {
          Column() {
            if (this.phase === LoadPhase.READY && this.data) {
              this.LevelCard(this.data)
              this.PoweredByFooter()
            } else if (this.phase === LoadPhase.LOADING) {
              this.LoadingState()
            } else if (this.phase === LoadPhase.ANON) {
              this.MessageState('请先登录', '登录 Linux.do 后即可查看等级升级进度', false)
            } else {
              this.MessageState('暂时无法获取', '可能是网络问题或需要在浏览器完成验证', true)
            }
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
      .backgroundColor($r('app.color.page_bg_gray'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
  }

  // ==================== 顶栏 ====================

  @Builder
  private TitleBar() {
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

      Text('等级进度')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
  }

  // ==================== 主卡片 ====================

  @Builder
  private LevelCard(data: ConnectLevelData) {
    Column() {
      // 头部:标题 + 达标状态药丸
      Row() {
        Text(data.title.length > 0 ? data.title : '信任级别要求')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.connect_text_primary'))
          .layoutWeight(1)
        if (data.statusLabel.length > 0) {
          Text(data.statusLabel)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(data.statusIsMet ? $r('app.color.connect_success') : $r('app.color.connect_danger'))
            .backgroundColor(data.statusIsMet ? $r('app.color.connect_success_bg') : $r('app.color.connect_danger_bg'))
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .borderRadius(999)
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (data.subtitle.length > 0) {
        Text(data.subtitle)
          .fontSize(13)
          .fontColor($r('app.color.connect_text_tertiary'))
          .width('100%')
          .margin({ top: 6 })
      }

      // 活跃程度(环形)
      if (data.rings.length > 0) {
        this.SectionTitle('活跃程度', true)
        Row() {
          ForEach(data.rings, (ring: ConnectRingItem) => {
            this.RingItem(ring)
          }, (ring: ConnectRingItem, index: number) => `ring_${index}_${ring.label}`)
        }
        .width('100%')
        .margin({ bottom: SECTION_BOTTOM })
      }

      // 互动参与(进度条)
      if (data.bars.length > 0) {
        this.SectionTitle('互动参与', data.rings.length === 0)
        ForEach(data.bars, (bar: ConnectBarItem, index: number) => {
          this.BarItem(bar, index > 0)
        }, (bar: ConnectBarItem, index: number) => `bar_${index}_${bar.label}`)
      }

      // 合规记录(配额卡 + 否决项)
      if (data.quotas.length > 0 || data.vetos.length > 0) {
        this.SectionTitle('合规记录', data.rings.length === 0 && data.bars.length === 0)
        ForEach(data.quotas, (quota: ConnectQuotaItem, index: number) => {
          this.QuotaCard(quota, index > 0)
        }, (quota: ConnectQuotaItem, index: number) => `quota_${index}_${quota.label}`)
        ForEach(data.vetos, (veto: ConnectVetoItem, index: number) => {
          this.VetoCard(veto, index > 0 || data.quotas.length > 0)
        }, (veto: ConnectVetoItem, index: number) => `veto_${index}_${veto.label}`)
      }

      // 结论区
      Divider()
        .strokeWidth(1)
        .color($r('app.color.connect_border'))
        .margin({ top: SECTION_TOP, bottom: 14 })
      if (data.hint.length > 0) {
        Text(data.hint)
          .fontSize(12)
          .fontColor($r('app.color.connect_text_tertiary'))
          .width('100%')
      }
      if (data.conclusion.length > 0) {
        Text(data.conclusion)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(data.conclusionIsMet ? $r('app.color.connect_success') : $r('app.color.connect_danger'))
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(CARD_PADDING)
    .backgroundColor($r('app.color.connect_card'))
    .borderRadius(CARD_RADIUS)
    .border({ width: 1, color: $r('app.color.connect_border') })
    .margin({ top: PAGE_MARGIN })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SectionTitle(title: string, first: boolean) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.connect_text_tertiary'))
      .letterSpacing(0.5)
      .width('100%')
      .margin({ top: first ? SECTION_BOTTOM : SECTION_TOP, bottom: SECTION_BOTTOM })
  }

  // 活跃程度环:Progress 环 + 中心当前值/目标值 + 底部标签。met 绿 / unmet 橙。
  @Builder
  private RingItem(ring: ConnectRingItem) {
    Column() {
      Stack() {
        Progress({ value: this.ringPercent(ring), total: 100, type: ProgressType.Ring })
          .width(74)
          .height(74)
          .color(ring.met ? $r('app.color.connect_success') : $r('app.color.connect_warning'))
          .backgroundColor($r('app.color.connect_track'))
          .style({ strokeWidth: 6, enableSmoothEffect: true })
        Column() {
          Text(ring.current)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(ring.met ? $r('app.color.connect_success') : $r('app.color.connect_warning'))
          Text(ring.target)
            .fontSize(10)
            .fontColor($r('app.color.connect_text_tertiary'))
        }
      }
      .width(74)
      .height(74)

      Text(ring.label)
        .fontSize(12)
        .fontColor($r('app.color.connect_text_secondary'))
        .margin({ top: 8 })
    }
    .layoutWeight(1)
  }

  // 互动参与进度条:标签 + 数值(met 绿/unmet 橙) + 轨道/渐变填充。
  @Builder
  private BarItem(bar: ConnectBarItem, spaced: boolean) {
    Column() {
      Row() {
        Text(bar.label)
          .fontSize(13)
          .fontColor($r('app.color.connect_text_secondary'))
          .layoutWeight(1)
        Text(bar.nums)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(bar.met ? $r('app.color.connect_success') : $r('app.color.connect_warning'))
      }
      .width('100%')

      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(8)
          .borderRadius(4)
          .backgroundColor($r('app.color.connect_track'))
        Column()
          .width(this.barWidth(bar))
          .height(8)
          .borderRadius(4)
          .linearGradient({
            angle: 90,
            colors: bar.met ? BAR_GRADIENT_MET : BAR_GRADIENT_UNMET
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .margin({ top: spaced ? 14 : 0 })
  }

  // 合规配额卡:标签 + N/总 + 分段格(前 used 段红,其余淡绿)。unmet 时卡片红底红边。
  @Builder
  private QuotaCard(quota: ConnectQuotaItem, spaced: boolean) {
    Column() {
      Row() {
        Text(quota.label)
          .fontSize(13)
          .fontColor($r('app.color.connect_text_secondary'))
          .layoutWeight(1)
        Text(quota.nums)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(quota.met ? $r('app.color.connect_text_tertiary') : $r('app.color.connect_danger'))
      }
      .width('100%')

      Row({ space: 5 }) {
        ForEach(this.range(quota.slots), (slot: number) => {
          Column()
            .layoutWeight(1)
            .height(6)
            .borderRadius(3)
            .backgroundColor(slot < quota.used ? $r('app.color.connect_danger') : $r('app.color.connect_success'))
            .opacity(slot < quota.used ? 0.8 : 0.25)
        }, (slot: number) => `slot_${slot}`)
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
    .borderRadius(10)
    .backgroundColor(quota.met ? $r('app.color.connect_card') : $r('app.color.connect_danger_bg'))
    .border({ width: 1, color: quota.met ? $r('app.color.connect_border') : BORDER_DANGER })
    .margin({ top: spaced ? 12 : 0 })
  }

  // 否决项卡:圆形勾/叉图标 + 标签/说明 + 次数。met 绿底绿字勾 / unmet 红底红字叉。
  @Builder
  private VetoCard(veto: ConnectVetoItem, spaced: boolean) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph(veto.met ? $r('sys.symbol.checkmark') : $r('sys.symbol.xmark'))
          .fontSize(15)
          .fontColor([veto.met ? $r('app.color.connect_success') : $r('app.color.connect_danger')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(veto.met ? ICONBG_SUCCESS : ICONBG_DANGER)

      Column() {
        Text(veto.label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.connect_text_primary'))
          .width('100%')
        if (veto.desc.length > 0) {
          Text(veto.desc)
            .fontSize(12)
            .fontColor($r('app.color.connect_text_secondary'))
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(veto.value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(veto.met ? $r('app.color.connect_success') : $r('app.color.connect_danger'))
    }
    .width('100%')
    .height(64)
    .padding({ left: CARD_PADDING, right: CARD_PADDING })
    .borderRadius(10)
    .backgroundColor(veto.met ? $r('app.color.connect_success_bg') : $r('app.color.connect_danger_bg'))
    .border({ width: 1, color: veto.met ? BORDER_SUCCESS : BORDER_DANGER })
    .margin({ top: spaced ? 12 : 0 })
  }

  @Builder
  private PoweredByFooter() {
    Row() {
      Text('Powered by ')
        .fontSize(12)
        .fontColor($r('app.color.connect_text_tertiary'))
      Text('LINUX DO')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.connect_text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 18, bottom: 30 })
  }

  // ==================== 加载 / 消息态 ====================

  @Builder
  private LoadingState() {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color($r('app.color.ld_accent'))
      Text('正在加载等级数据')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 14 })
    }
    .width('100%')
    .height(280)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private MessageState(title: string, subtitle: string, retryable: boolean) {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(40)
        .fontColor([$r('app.color.text_faint')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })
      Text(subtitle)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
        .padding({ left: 24, right: 24 })
      if (retryable) {
        Row({ space: 10 }) {
          Button('重试')
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.ld_accent'))
            .height(42)
            .padding({ left: 28, right: 28 })
            .borderRadius(21)
            .onClick(() => {
              this.retry();
            })
          Button('浏览器打开')
            .fontSize(15)
            .fontColor($r('app.color.ld_accent'))
            .backgroundColor($r('app.color.surface_card'))
            .height(42)
            .padding({ left: 20, right: 20 })
            .borderRadius(21)
            .onClick(() => {
              this.onOpenWeb(AppConstants.CONNECT_URL, '等级进度');
            })
        }
        .margin({ top: 22 })
      }
    }
    .width('100%')
    .height(320)
    .justifyContent(FlexAlign.Center)
  }

  // ==================== 数据加载 ====================

  private onConnectPageEnd(): void {
    if (this.settled) {
      return;
    }
    // 服务端渲染,onPageEnd 时数值多已在 DOM;SSO/挑战跳转会各自再触发 onPageEnd。
    // 立即尝试一次,再补两次延迟兜底(应对偶发晚到)。
    this.attemptExtract();
    this.timers.push(setTimeout(() => {
      this.attemptExtract();
    }, 600));
    this.timers.push(setTimeout(() => {
      this.attemptExtract();
    }, 1500));
  }

  private attemptExtract(): void {
    if (this.settled) {
      return;
    }
    this.controller.runJavaScript(CONNECT_EXTRACT_SCRIPT)
      .then((raw: string) => {
        if (this.settled) {
          return;
        }
        const parsed: ConnectLevelData | null = ConnectLevelParser.parse(raw);
        if (parsed) {
          this.settled = true;
          this.data = parsed;
          this.phase = LoadPhase.READY;
          this.clearTimers();
          Log.i(`${LOG_TAG} parsed rings=${parsed.rings.length} bars=${parsed.bars.length}`);
        } else {
          // 未解析出卡片:抓当前文档快照(在哪个页面/有没有卡片/正文多大),判定是 SSO/CF/空白/被拦。
          Log.i(`${LOG_TAG} extract not ready rawLen=${raw ? raw.length : 0}`);
          this.logDiag('afterExtract');
        }
      })
      .catch((error: Object) => {
        Log.i(`${LOG_TAG} runJavaScript failed: ${JSON.stringify(error)}`);
      });
  }

  // 文档快照诊断:href/title/是否有升级要求卡/正文长度/是否像 CF 挑战页。定位隐藏 Web 卡在哪一步。
  private logDiag(tag: string): void {
    const script: string = `(function(){try{
      var b=document.body?document.body.innerText:'';
      return JSON.stringify({
        href: location.href,
        title: document.title||'',
        hasCard: !!document.querySelector('.tl3-rings'),
        bodyLen: b.length,
        cf: /just a moment|checking your browser|cloudflare|attention required/i.test(b),
        head: b.slice(0,120)
      });
    }catch(e){return '';}})();`;
    this.controller.runJavaScript(script)
      .then((raw: string) => {
        Log.i(`${LOG_TAG} diag(${tag}) ${raw}`);
      })
      .catch(() => {
        Log.i(`${LOG_TAG} diag(${tag}) runJavaScript failed`);
      });
  }

  // 主框架加载失败:自动重载兜底。上限内延迟重载(给 DoH/网络一个恢复窗口);超上限则立即进
  // 错误态(避免干等 20s 超时)。子资源失败忽略。settled 后一律不动。
  private onMainFrameError(isMainFrame: boolean): void {
    if (this.settled || !isMainFrame) {
      return;
    }
    if (this.reloadCount >= 2) {
      if (!this.settled) {
        this.phase = LoadPhase.ERROR;
        this.clearTimers();
        Log.i(`${LOG_TAG} main frame error, auto-reload exhausted`);
      }
      return;
    }
    this.reloadCount++;
    const attempt: number = this.reloadCount;
    this.timers.push(setTimeout(() => {
      if (this.settled) {
        return;
      }
      Log.i(`${LOG_TAG} auto-reload attempt=${attempt}`);
      try {
        this.controller.loadUrl(AppConstants.CONNECT_URL);
      } catch (error) {
        Log.i(`${LOG_TAG} auto-reload loadUrl failed: ${JSON.stringify(error)}`);
      }
    }, 1200));
  }

  private startTimeout(): void {
    this.timers.push(setTimeout(() => {
      if (!this.settled) {
        this.phase = LoadPhase.ERROR;
        Log.i(`${LOG_TAG} ready timeout`);
        this.logDiag('timeout');
      }
    }, READY_TIMEOUT_MS));
  }

  private retry(): void {
    this.settled = false;
    this.data = undefined;
    this.phase = LoadPhase.LOADING;
    this.reloadCount = 0;
    this.clearTimers();
    this.startTimeout();
    try {
      this.controller.loadUrl(AppConstants.CONNECT_URL);
    } catch (error) {
      Log.i(`${LOG_TAG} retry loadUrl failed: ${JSON.stringify(error)}`);
    }
  }

  private clearTimers(): void {
    for (let index: number = 0; index < this.timers.length; index++) {
      clearTimeout(this.timers[index]);
    }
    this.timers = [];
  }

  // ==================== 计算辅助 ====================

  private ringPercent(ring: ConnectRingItem): number {
    if (ring.max > 0) {
      const pct: number = (ring.val / ring.max) * 100;
      return pct > 100 ? 100 : pct;
    }
    return ring.met ? 100 : 0;
  }

  private barWidth(bar: ConnectBarItem): string {
    let pct: number = 0;
    if (bar.max > 0) {
      pct = (bar.val / bar.max) * 100;
      if (pct > 100) {
        pct = 100;
      }
    } else if (bar.met) {
      pct = 100;
    }
    return `${Math.round(pct * 10) / 10}%`;
  }

  private range(count: number): number[] {
    const result: number[] = [];
    const safe: number = count > 0 ? count : 0;
    for (let index: number = 0; index < safe; index++) {
      result.push(index);
    }
    return result;
  }
}
