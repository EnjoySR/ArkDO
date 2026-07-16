import { Log } from '../../services/logging/Log';
import { SiteDef, SitePrefs } from '../../services/site/SitePrefs';
import { SiteIconStore } from '../../services/site/SiteIconStore';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';

const LOG_TAG: string = '[ArkDO][SitesPage]';

// AppStorage 计数键:RootTabPage 在本页 NavDestination onShown 时自增,驱动本页重读站点。
// 打开站点后 favicon 才落盘,而 NavDestination 常驻不重建(aboutToAppear 不会再跑),
// 从 WEB 页 pop 回来必须靠它把新图标读进来。同 SETTINGS_DOH_TICK 的处境。
export const SITES_TICK: string = 'sites_tick';

// 与设置页同款鸿蒙卡片分组:灰底 + 无描边圆角卡片。
const PAGE_MARGIN: number = 12;
const CARD_RADIUS: number = 16;
const CARD_PADDING: number = 16;
const CARD_GAP: number = 12;
// 站点行高(名称 + 域名两行);拖动排序按此行高换算跟手位移与让位步长。
const SITE_ROW_H: number = 64;

// 添加/编辑站点弹窗。名称可留空(留空取域名);URL 裸域名自动补 https://。
// 编辑态多一枚删除入口——底部只有取消/保存两枚按钮,删除塞不进去,放内容区末尾。
@CustomDialog
struct SiteEditDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: SiteEditDialog({}) });
  isEdit: boolean = false;
  initialName: string = '';
  initialUrl: string = '';
  initialShow: boolean = true;
  onConfirm: (name: string, url: string, showInDrawer: boolean) => void = () => {};
  onInvalid: (reason: string) => void = () => {};
  // 删除:先关弹窗再由页面弹二次确认(两层弹窗叠加在鸿蒙上会打架)。
  onDelete: () => void = () => {};
  @State private name: string = '';
  @State private url: string = '';
  @State private showInDrawer: boolean = true;

  aboutToAppear(): void {
    this.name = this.initialName;
    this.url = this.initialUrl;
    this.showInDrawer = this.initialShow;
  }

  build() {
    // 原生鸿蒙 AlertDialog 风格:大圆角卡片、标题居中、内容区、底部两枚文字按钮由发丝线分隔。
    Column() {
      Text(this.isEdit ? '编辑站点' : '添加站点')
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

        TextInput({ placeholder: '站点地址,如 example.com', text: this.url })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .margin({ top: 12 })
          .onChange((value: string) => {
            this.url = value;
          })

        Row() {
          Column() {
            Text('在侧边栏显示')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text('关闭后仍可在站点列表里打开')
              .fontSize(12)
              .fontColor($r('app.color.text_faint'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.showInDrawer })
            .selectedColor($r('app.color.ld_accent'))
            .onChange((isOn: boolean) => {
              this.showInDrawer = isOn;
            })
        }
        .width('100%')
        .margin({ top: 16 })

        if (this.isEdit) {
          Text('删除站点')
            .fontSize(15)
            .fontColor($r('app.color.ld_danger'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 18 })
            .onClick(() => {
              this.controller.close();
              this.onDelete();
            })
        }
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

        Button(this.isEdit ? '保存' : '添加')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(52)
          .backgroundColor(Color.Transparent)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ld_accent'))
          .onClick(() => {
            const finalUrl: string = SitePrefs.normalizeUrl(this.url);
            if (!SitePrefs.isValidUrl(finalUrl)) {
              this.onInvalid('请填写有效的站点地址');
              return;
            }
            const trimmedName: string = this.name.trim();
            const finalName: string = trimmedName.length > 0 ? trimmedName : SitePrefs.hostOf(finalUrl);
            this.onConfirm(finalName, finalUrl, this.showInDrawer);
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
}

/**
 * 站点管理页:用户自维护的站点列表。已显示区可拖动排序(排序直接生效于首页抽屉),
 * 未显示区为关掉侧边栏显示的站点。右上角「＋」添加,点行编辑/删除。
 *
 * 空态是这个功能的说明书——不预置任何站点,新用户第一次进来只能靠空态理解它是干什么的。
 */
@Component
export struct SitesPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  onBack: () => void = () => {};
  // 打开站点:交给 RootTabPage push 通用 WebView 页(与帖子外链同一条链路)。siteId 用于缓存该站 favicon。
  onOpenSite: (url: string, title: string, siteId: string) => void = () => {};
  // 全量站点,已显示段在前、未显示段在后(persist 时由 partition 保证)。
  @State private sites: SiteDef[] = [];
  // 拖动排序状态:draggingIndex=被拖行在已显示段的原始下标(-1 为未拖动);
  // dragOffsetY=浮起行跟手位移;hoverIndex=当前落位槽位(邻行据此实时让位)。
  @State private draggingIndex: number = -1;
  @State private dragOffsetY: number = 0;
  @State private hoverIndex: number = -1;
  // 编辑/添加弹窗每次打开都新建:CustomDialogController 的 builder 参数在构造时按值求值,
  // 复用同一个 controller 会永远拿到第一次捕获的站点。
  private editDialog: CustomDialogController | undefined = undefined;
  // 从 WEB 页 pop 回来(本页重新可见)时由 RootTabPage 自增,触发重读——favicon 此刻可能刚落盘。
  @StorageProp(SITES_TICK) @Watch('onPageShown') private sitesTick: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  private onPageShown(): void {
    this.reload();
  }

  // 拖动中不重读:此刻 sites 顺序正被手势改写,冲掉会让拖动的行跳回原位。
  private reload(): void {
    if (this.draggingIndex >= 0) {
      return;
    }
    this.sites = SitePrefs.getSites(getContext(this));
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
        this.TitleBar()

        Scroll() {
          Column() {
            if (this.sites.length === 0) {
              this.EmptyCard()
            } else {
              this.SiteListCard()
            }

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

      Text('我的站点')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(22)
          .fontColor([$r('app.color.text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.surface_muted'))
      .onClick(() => {
        this.openAddDialog();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
  }

  // 空态:这个功能的说明书。讲清「是什么 / 凭什么比浏览器强 / 现在该干嘛」三件事。
  @Builder
  private EmptyCard() {
    Column() {
      // 与首页空态同款:彩色 logo 直接用,不染色不套圈。
      Image($r('app.media.linuxdo_logo'))
        .width(64)
        .height(64)

      Text('还没有添加站点')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })

      Text('Linux.do 生态里的不少站点要用论坛账号授权登录，域名也常常解析不出来。加到这里，ArkDO 会用 DoH 解析域名、并复用你已有的登录态。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
        .padding({ left: CARD_PADDING, right: CARD_PADDING })

      Button('添加站点')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.ld_accent'))
        .height(42)
        .padding({ left: 44, right: 44 })
        .borderRadius(21)
        .margin({ top: 22 })
        .onClick(() => {
          this.openAddDialog();
        })

      Column() {
        Text('DoH 解析域名,免代理直连')
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
        Text('复用论坛登录态,授权一键通过')
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ top: 6 })
        Text('站点由你自己添加，随时可删')
          .fontSize(13)
          .fontColor($r('app.color.text_faint'))
          .margin({ top: 6 })
      }
      .margin({ top: 16 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 32, bottom: 26 })
    .cardStyle()
  }

  @Builder
  private SiteListCard() {
    Column() {
      // 已显示区:长按整行抬起、跟手拖动,邻行实时让位,松手吸附落位。顺序直接生效于抽屉。
      if (this.shownSites().length > 0) {
        Column() {
          ForEach(this.shownSites(), (site: SiteDef, index: number) => {
            this.ShownSiteRow(site, index)
          }, (site: SiteDef) => `${site.id}_${site.name}_${site.url}_${site.iconUri}`)
        }
        .width('100%')
        .clip(false)
      }

      // 未显示区:开关关掉的站点,不参与排序。
      if (this.hiddenSites().length > 0) {
        if (this.shownSites().length > 0) {
          this.HairlineInset()
        }
        ForEach(this.hiddenSites(), (site: SiteDef) => {
          this.HiddenSiteRow(site)
        }, (site: SiteDef) => `h${site.id}_${site.name}_${site.url}_${site.iconUri}`)
      }
    }
    .cardStyle()
    .clip(true)
  }

  @Builder
  private ShownSiteRow(site: SiteDef, index: number) {
    Row() {
      this.DragHandle()

      this.SiteIcon(site)

      Column() {
        Text(site.name)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(SitePrefs.hostOf(site.url))
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      this.OpenButton(site)

      Toggle({ type: ToggleType.Switch, isOn: true })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          if (!isOn) {
            this.setShowInDrawer(site.id, false);
          }
        })
    }
    .width('100%')
    .height(SITE_ROW_H)
    .padding({ left: CARD_PADDING, right: CARD_PADDING })
    .backgroundColor($r('app.color.surface_card'))
    // 被拖行浮起在最上层;其余行按 hoverIndex 上下让位。
    .zIndex(this.draggingIndex === index ? 1 : 0)
    .translate({ y: this.rowTranslateY(index) })
    .scale(this.draggingIndex === index ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
    .shadow(this.draggingIndex === index
      ? { radius: 12, color: '#33000000', offsetY: 4 }
      : { radius: 0, color: Color.Transparent })
    .onClick(() => {
      this.openEditDialog(site);
    })
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
  private HiddenSiteRow(site: SiteDef) {
    Row() {
      // 与已显示行的图标左对齐:那边行首是 16 宽拖动手柄,这边用等宽空位顶掉(间距由图标自带)。
      Row()
        .width(16)

      this.SiteIcon(site)

      Column() {
        Text(site.name)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(SitePrefs.hostOf(site.url))
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      this.OpenButton(site)

      Toggle({ type: ToggleType.Switch, isOn: false })
        .selectedColor($r('app.color.ld_accent'))
        .onChange((isOn: boolean) => {
          if (isOn) {
            this.setShowInDrawer(site.id, true);
          }
        })
    }
    .width('100%')
    .height(SITE_ROW_H)
    .padding({ left: CARD_PADDING, right: CARD_PADDING })
    .onClick(() => {
      this.openEditDialog(site);
    })
  }

  // 打开站点:独立热区,点它直接进站,不触发整行的编辑(同版块行展开箭头的做法)。
  // 关掉侧边栏显示的站点只能从这里进,故两段列表都挂。
  @Builder
  private OpenButton(site: SiteDef) {
    Row() {
      SymbolGlyph($r('sys.symbol.arrow_right_up_and_square'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])
    }
    .height('100%')
    .width(40)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onOpenSite(site.url, site.name, site.id);
    })
  }

  // 站点图标:抓到 favicon 就用真图标(不染色,站点 logo 多是彩色的);否则回退 FA link 图标。
  @Builder
  private SiteIcon(site: SiteDef) {
    Row() {
      if (site.iconUri.length > 0) {
        Image(site.iconUri)
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
          .borderRadius(4)
      } else if (this.getLinkIcon()) {
        FaIconView({
          icon: this.getLinkIcon() as FaIconDefinition,
          color: $r('app.color.text_faint'),
          iconSize: 16
        })
      }
    }
    .width(20)
    .justifyContent(FlexAlign.Center)
    // 间距收在图标自己身上,两段列表(带手柄/带占位)因此天然对齐。
    .margin({ left: 12 })
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

  // ==================== 弹窗 ====================

  private openAddDialog(): void {
    this.editDialog = new CustomDialogController({
      builder: SiteEditDialog({
        isEdit: false,
        initialName: '',
        initialUrl: '',
        initialShow: true,
        onConfirm: (name: string, url: string, showInDrawer: boolean): void => {
          this.handleAdd(name, url, showInDrawer);
        },
        onInvalid: (reason: string): void => {
          this.showToast(reason);
        }
      }),
      customStyle: true,
      alignment: DialogAlignment.Center,
      autoCancel: true
    });
    this.editDialog.open();
  }

  private openEditDialog(site: SiteDef): void {
    this.editDialog = new CustomDialogController({
      builder: SiteEditDialog({
        isEdit: true,
        initialName: site.name,
        initialUrl: site.url,
        initialShow: site.showInDrawer,
        onConfirm: (name: string, url: string, showInDrawer: boolean): void => {
          this.handleUpdate(site.id, name, url, showInDrawer);
        },
        onInvalid: (reason: string): void => {
          this.showToast(reason);
        },
        onDelete: (): void => {
          this.confirmDelete(site);
        }
      }),
      customStyle: true,
      alignment: DialogAlignment.Center,
      autoCancel: true
    });
    this.editDialog.open();
  }

  private confirmDelete(site: SiteDef): void {
    this.getUIContext().showAlertDialog({
      title: '删除站点',
      message: `确定要删除「${site.name}」吗?`,
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
          this.handleDelete(site.id);
        }
      }
    });
  }

  // ==================== 数据 ====================

  private shownSites(): SiteDef[] {
    const result: SiteDef[] = [];
    for (let index: number = 0; index < this.sites.length; index++) {
      if (this.sites[index].showInDrawer) {
        result.push(this.sites[index]);
      }
    }
    return result;
  }

  private hiddenSites(): SiteDef[] {
    const result: SiteDef[] = [];
    for (let index: number = 0; index < this.sites.length; index++) {
      if (!this.sites[index].showInDrawer) {
        result.push(this.sites[index]);
      }
    }
    return result;
  }

  // 已显示段在前、未显示段在后,段内保持相对顺序。新开启显示的站点因此自然落到已显示段末尾。
  private partition(sites: SiteDef[]): SiteDef[] {
    const shown: SiteDef[] = [];
    const hidden: SiteDef[] = [];
    for (let index: number = 0; index < sites.length; index++) {
      if (sites[index].showInDrawer) {
        shown.push(sites[index]);
      } else {
        hidden.push(sites[index]);
      }
    }
    return shown.concat(hidden);
  }

  // 新站点没有图标——favicon 要等用户第一次打开该站点时才由引擎交出来。
  private handleAdd(name: string, url: string, showInDrawer: boolean): void {
    const next: SiteDef[] = this.sites.slice();
    next.push({ id: SitePrefs.newId(), name: name, url: url, showInDrawer: showInDrawer, iconUri: '' });
    this.persist(this.partition(next));
  }

  // 改地址后旧图标就不对了:清掉,下次打开该站点会重新抓。
  private handleUpdate(id: string, name: string, url: string, showInDrawer: boolean): void {
    const next: SiteDef[] = [];
    for (let index: number = 0; index < this.sites.length; index++) {
      const site: SiteDef = this.sites[index];
      if (site.id === id) {
        const urlChanged: boolean = site.url !== url;
        if (urlChanged) {
          SiteIconStore.remove(getContext(this), id);
        }
        next.push({
          id: id,
          name: name,
          url: url,
          showInDrawer: showInDrawer,
          iconUri: urlChanged ? '' : site.iconUri
        });
      } else {
        next.push(site);
      }
    }
    this.persist(this.partition(next));
  }

  private handleDelete(id: string): void {
    // 先清图标文件再落列表,免得留下没人认领的孤儿文件。
    SiteIconStore.remove(getContext(this), id);
    const next: SiteDef[] = [];
    for (let index: number = 0; index < this.sites.length; index++) {
      if (this.sites[index].id !== id) {
        next.push(this.sites[index]);
      }
    }
    this.persist(next);
  }

  private setShowInDrawer(id: string, show: boolean): void {
    const next: SiteDef[] = [];
    for (let index: number = 0; index < this.sites.length; index++) {
      const site: SiteDef = this.sites[index];
      if (site.id === id) {
        next.push({ id: site.id, name: site.name, url: site.url, showInDrawer: show, iconUri: site.iconUri });
      } else {
        next.push(site);
      }
    }
    this.persist(this.partition(next));
  }

  private persist(sites: SiteDef[]): void {
    this.sites = sites;
    SitePrefs.setSites(getContext(this), sites);
  }

  // ==================== 拖动排序 ====================

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
      return -SITE_ROW_H;
    }
    if (from > to && index >= to && index < from) {
      return SITE_ROW_H;
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

  // 拖动中:跟手位移(夹在已显示区上下边界内),按半格阈值更新落位槽,邻行动画让位。
  private updateDrag(offsetY: number): void {
    if (this.draggingIndex < 0) {
      return;
    }
    const len: number = this.shownSites().length;
    const maxUp: number = -this.draggingIndex * SITE_ROW_H;
    const maxDown: number = (len - 1 - this.draggingIndex) * SITE_ROW_H;
    let y: number = offsetY;
    if (y < maxUp) {
      y = maxUp;
    }
    if (y > maxDown) {
      y = maxDown;
    }
    this.dragOffsetY = y;
    let hover: number = this.draggingIndex + Math.round(y / SITE_ROW_H);
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
      this.dragOffsetY = (to - from) * SITE_ROW_H;
    });
  }

  // 重排只作用于已显示段,写回时拼上未显示段(段边界由 partition 的不变式保证)。
  private commitReorder(from: number, to: number): void {
    const shown: SiteDef[] = this.shownSites();
    if (from >= 0 && to >= 0 && from !== to && from < shown.length) {
      const moved: SiteDef[] = shown.splice(from, 1);
      const target: number = to > shown.length ? shown.length : to;
      shown.splice(target, 0, moved[0]);
      this.persist(shown.concat(this.hiddenSites()));
    }
    this.draggingIndex = -1;
    this.hoverIndex = -1;
    this.dragOffsetY = 0;
  }

  // ==================== 辅助 ====================

  private getLinkIcon(): FaIconDefinition | undefined {
    return getFaIcon('link');
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Log.i(`${LOG_TAG} toast failed: ${message}`);
    }
  }
}
