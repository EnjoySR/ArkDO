import { Log } from '../../services/logging/Log';
import { common } from '@kit.AbilityKit';
import { DohManager, DohResolveMode, DohServer } from '../../services/network/DohManager';
import { DohSpeedTester, DohTestResult } from '../../services/network/DohSpeedTester';

const LOG_TAG: string = '[ArkDO][DohPage]';

// 与设置页同款鸿蒙卡片分组:灰底 + 无描边圆角卡片。
const PAGE_MARGIN: number = 12;
const CARD_RADIUS: number = 16;
const CARD_PADDING: number = 16;
const CARD_GAP: number = 12;

// 测速状态机:每行独立驱动显示(用自身 @State 数组重建而非依赖深层字段变更)。
enum RowTestState {
  IDLE = 0,
  TESTING = 1,
  OK = 2,
  FAIL = 3
}

interface DohRow {
  server: DohServer;
  state: RowTestState;
  latencyMs: number;
  message: string;
}

// 添加自定义 DoH 弹窗:名称可留空(留空用域名兜底),URL 必须 https。
@CustomDialog
struct AddDohDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: AddDohDialog({}) });
  onConfirm: (name: string, url: string) => void = () => {};
  onInvalid: (reason: string) => void = () => {};
  @State private name: string = '';
  @State private url: string = '';

  build() {
    // 原生鸿蒙 AlertDialog 风格:大圆角卡片、标题居中、内容区、底部两枚文字按钮由发丝线分隔。
    Column() {
      Text('添加 DoH')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 22, bottom: 18 })

      Column() {
        TextInput({ placeholder: '名称(可留空,默认取域名)', text: this.name })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .onChange((value: string) => {
            this.name = value;
          })
        TextInput({ placeholder: 'https://.../dns-query', text: this.url })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .margin({ top: 12 })
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

        Button('添加')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
          .onClick(() => {
            const trimmedUrl: string = this.url.trim();
            if (!trimmedUrl.startsWith('https://') || trimmedUrl.length < 12) {
              this.onInvalid('请填写有效的 https DoH 地址');
              return;
            }
            const finalName: string = this.name.trim().length > 0 ? this.name.trim() : this.hostOf(trimmedUrl);
            this.onConfirm(finalName, trimmedUrl);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width('86%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(32)
    .clip(true)
  }

  private hostOf(url: string): string {
    const withoutScheme: string = url.replace(/^https:\/\//, '');
    const slash: number = withoutScheme.indexOf('/');
    return slash >= 0 ? withoutScheme.substring(0, slash) : withoutScheme;
  }
}

/**
 * DoH 配置页:总开关、服务器列表(单选生效 + 逐条/一键测速 + 删除)、解析模式。
 * 右上角「＋」添加自定义 DoH。任何生效变更后经 onDohApplied 通知宿主 webview 重载。
 */
@Component
export struct DohSettingsPage {
  onBack: () => void = () => {};
  // 切换/开关/删除导致生效变更后回调:由上层重载宿主 webview,让新 DNS 立即用于解析。
  onDohApplied: () => void = () => {};

  @State private rows: DohRow[] = [];
  @State private dohEnabled: boolean = true;
  @State private activeId: string = '';
  @State private mode: DohResolveMode = DohResolveMode.AUTO;

  private addDialog: CustomDialogController = new CustomDialogController({
    builder: AddDohDialog({
      onConfirm: (name: string, url: string): void => {
        this.handleAdd(name, url);
      },
      onInvalid: (reason: string): void => {
        this.showToast(reason);
      }
    }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.reload();
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg_gray'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        this.TitleBar()

        Scroll() {
          Column() {
            this.EnableCard()
            this.ServerListCard()

            Button('一键测速全部')
              .width('100%')
              .height(44)
              .margin({ top: CARD_GAP })
              .backgroundColor($r('app.color.surface_card'))
              .fontColor($r('app.color.ld_accent'))
              .fontSize(15)
              .onClick(() => {
                this.testAll();
              })

            this.ModeCard()

            Text('DoH 用加密的 HTTPS 通道解析域名,绕过被污染的本地 DNS。仅对内置浏览器内核生效。')
              .fontSize(12)
              .fontColor($r('app.color.text_faint'))
              .width('100%')
              .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14 })

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

      Text('DoH 配置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([$r('app.color.text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.surface_muted'))
      .onClick(() => {
        this.addDialog.open();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
  }

  @Builder
  private EnableCard() {
    Column() {
      Row() {
        Column() {
          Text('启用 DoH')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text('关闭后走系统 DNS(可能被污染)')
            .fontSize(12)
            .fontColor($r('app.color.text_faint'))
            .width('100%')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.dohEnabled })
          .selectedColor($r('app.color.ld_accent'))
          .onChange((isOn: boolean) => {
            this.toggleEnabled(isOn);
          })
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
    }
    .cardStyle()
    .margin({ top: 0 })
  }

  @Builder
  private ServerListCard() {
    Column() {
      ForEach(this.rows, (row: DohRow, index: number) => {
        if (index > 0) {
          this.HairlineInset()
        }
        this.ServerRow(row)
        // key 必须包含会变的字段(测速状态/延迟/是否选中),否则 ForEach 认为条目未变而不重建,
        // 导致点击测速后 TESTING/转圈渲染不出来。
      }, (row: DohRow) => `${row.server.id}|${row.state}|${row.latencyMs}|${row.server.id === this.activeId ? 1 : 0}`)
    }
    .cardStyle()
  }

  @Builder
  private ServerRow(row: DohRow) {
    Row() {
      // 左侧:选中圆点 + 名称 + 地址,点击即选为当前生效。
      Row() {
        Circle({ width: 18, height: 18 })
          .fill(row.server.id === this.activeId ? $r('app.color.ld_accent') : Color.Transparent)
          .stroke(row.server.id === this.activeId ? $r('app.color.ld_accent') : $r('app.color.text_faint'))
          .strokeWidth(1.5)
        Column() {
          Text(row.server.name)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.shortUrl(row.server.url))
            .fontSize(12)
            .fontColor($r('app.color.text_faint'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .layoutWeight(1)
      .onClick(() => {
        this.selectServer(row.server.id);
      })

      // 右侧:测速状态 / 触发测速。
      this.LatencyBadge(row)

      // 删除(仅自定义项)。
      if (!row.server.builtin) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([$r('app.color.ld_danger')])
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .margin({ left: 4 })
        .onClick(() => {
          this.confirmDelete(row.server);
        })
      }
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 12 })
  }

  @Builder
  private LatencyBadge(row: DohRow) {
    if (row.state === RowTestState.TESTING) {
      LoadingProgress()
        .width(22)
        .height(22)
        .color($r('app.color.ld_accent'))
        .margin({ right: 4 })
    } else {
      // 实体药丸按钮:点击热区足够大,不再是裸文字的小热区。
      Button({ type: ButtonType.Normal }) {
        Text(this.badgeLabel(row))
          .fontSize(13)
          .fontColor(this.badgeColor(row))
      }
      .height(30)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(8)
      .onClick(() => {
        this.testOne(row.server.id);
      })
    }
  }

  private badgeLabel(row: DohRow): string {
    if (row.state === RowTestState.OK) {
      return `${row.latencyMs}ms`;
    }
    if (row.state === RowTestState.FAIL) {
      return row.message.length > 0 ? row.message : '重试';
    }
    return '测速';
  }

  private badgeColor(row: DohRow): ResourceColor {
    if (row.state === RowTestState.OK) {
      return this.latencyColor(row.latencyMs);
    }
    if (row.state === RowTestState.FAIL) {
      return $r('app.color.text_faint');
    }
    return $r('app.color.ld_accent');
  }

  @Builder
  private ModeCard() {
    this.GroupLabel('解析模式')
    Column() {
      Row() {
        Column() {
          Text('DNS 解析模式')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text(this.modeHint())
            .fontSize(12)
            .fontColor($r('app.color.text_faint'))
            .width('100%')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.modeLabel())
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ right: 6 })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.text_faint')])
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 14 })
      .bindMenu([
        {
          value: '自动(推荐)',
          action: (): void => {
            this.setMode(DohResolveMode.AUTO);
          }
        },
        {
          value: '仅 DoH',
          action: (): void => {
            this.setMode(DohResolveMode.SECURE_ONLY);
          }
        }
      ])
    }
    .cardStyle()
    .margin({ top: 0 })
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

  @Styles
  cardStyle() {
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(CARD_RADIUS)
    .margin({ top: CARD_GAP })
  }

  // ==================== 数据与交互 ====================

  private reload(): void {
    const context: common.Context = getContext(this);
    const servers: DohServer[] = DohManager.getServers(context);
    // 保留已有测速结果:按 id 归并旧行状态,新增项为 IDLE。
    const previous: Map<string, DohRow> = new Map<string, DohRow>();
    for (const row of this.rows) {
      previous.set(row.server.id, row);
    }
    const nextRows: DohRow[] = servers.map((server: DohServer) => {
      const old: DohRow | undefined = previous.get(server.id);
      return {
        server: server,
        state: old !== undefined ? old.state : RowTestState.IDLE,
        latencyMs: old !== undefined ? old.latencyMs : -1,
        message: old !== undefined ? old.message : ''
      } as DohRow;
    });
    this.rows = nextRows;
    this.dohEnabled = DohManager.isEnabled(context);
    this.activeId = DohManager.getActiveId(context);
    this.mode = DohManager.getMode(context);
  }

  private toggleEnabled(isOn: boolean): void {
    this.dohEnabled = isOn;
    DohManager.setEnabled(getContext(this), isOn);
    this.onDohApplied();
    this.showToast(isOn ? 'DoH 已启用' : 'DoH 已关闭');
  }

  private selectServer(id: string): void {
    if (this.activeId === id) {
      return;
    }
    this.activeId = id;
    // 换新数组引用,促使 ForEach 按新 key(含选中位)重新比对,选中圆点才会更新。
    this.rows = this.rows.slice();
    DohManager.setActive(getContext(this), id);
    this.onDohApplied();
    this.showToast('已切换 DoH,正在重载');
  }

  private setMode(mode: DohResolveMode): void {
    this.mode = mode;
    DohManager.setMode(getContext(this), mode);
    this.onDohApplied();
  }

  private handleAdd(name: string, url: string): void {
    const created: DohServer | undefined = DohManager.addServer(getContext(this), name, url);
    if (created === undefined) {
      this.showToast('添加失败');
      return;
    }
    this.reload();
    this.showToast('已添加');
  }

  private confirmDelete(server: DohServer): void {
    this.getUIContext().showAlertDialog({
      title: '删除 DoH',
      message: `确定删除「${server.name}」吗?`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.ld_danger'),
        action: () => {
          const wasActive: boolean = this.activeId === server.id;
          DohManager.removeServer(getContext(this), server.id);
          this.reload();
          if (wasActive) {
            // 删的是当前项,已回退内置默认并重新下发,需重载宿主。
            this.onDohApplied();
          }
          this.showToast('已删除');
        }
      }
    });
  }

  private testOne(id: string): void {
    let target: DohRow | undefined = undefined;
    for (const row of this.rows) {
      if (row.server.id === id) {
        target = row;
        break;
      }
    }
    if (target === undefined || target.state === RowTestState.TESTING) {
      return;
    }
    Log.i(`${LOG_TAG} test start id=${id} url=${target.server.url}`);
    this.updateRow(id, RowTestState.TESTING, -1, '');
    const url: string = target.server.url;
    DohSpeedTester.test(url).then((result: DohTestResult) => {
      if (result.ok) {
        this.updateRow(id, RowTestState.OK, result.latencyMs, result.message);
      } else {
        this.updateRow(id, RowTestState.FAIL, -1, result.message);
      }
    }).catch((err: Object) => {
      Log.i(`${LOG_TAG} test error: ${JSON.stringify(err)}`);
      this.updateRow(id, RowTestState.FAIL, -1, '失败');
    });
  }

  private testAll(): void {
    for (const row of this.rows) {
      this.testOne(row.server.id);
    }
  }

  // 重建整个数组以驱动 ForEach 重渲染(深层字段就地改在 ArkUI 下不可靠)。
  private updateRow(id: string, state: RowTestState, latencyMs: number, message: string): void {
    this.rows = this.rows.map((row: DohRow) => {
      if (row.server.id !== id) {
        return row;
      }
      return {
        server: row.server,
        state: state,
        latencyMs: latencyMs,
        message: message
      } as DohRow;
    });
  }

  // ==================== 辅助 ====================

  private shortUrl(url: string): string {
    return url.replace(/^https:\/\//, '');
  }

  private latencyColor(ms: number): ResourceColor {
    if (ms < 150) {
      return '#22a06b';
    }
    if (ms < 400) {
      return '#d99400';
    }
    return '#d1622b';
  }

  private modeLabel(): string {
    return this.mode === DohResolveMode.SECURE_ONLY ? '仅 DoH' : '自动';
  }

  private modeHint(): string {
    return this.mode === DohResolveMode.SECURE_ONLY
      ? '只用 DoH,解析失败即加载失败'
      : 'DoH 失败时回退系统 DNS';
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Log.i(`${LOG_TAG} toast failed: ${message}`);
    }
  }
}
