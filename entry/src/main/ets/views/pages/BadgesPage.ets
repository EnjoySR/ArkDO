import { Log } from '../../services/logging/Log';
import { UserBadgeGroup, UserBadgeItem } from '../../models/UserProfile';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { JsonNetworkClient, NetworkResult } from '../../services/network/NetworkTypes';
import { UserProfileService } from '../../services/user/UserProfileService';
import { BadgeTile, badgeTypeColor } from '../components/BadgeTile';
import { LoadStateView } from '../components/LoadStateView';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { PageHeader } from '../components/PageHeader';

const LOG_TAG: string = '[ArkDO][BadgesPage]';
const PAGE_PADDING: number = 16;
// 每行 3 枚,与个人中心徽章区一致。
const BADGES_PER_ROW: number = 3;

// 「全部徽章」页:原生化官方 /u/{username}/badges。数据源 /user-badges/{username}.json?grouped=true,
// 与摘要接口同源,走同一 bridge 过盾。按金/银/铜分组,点击单枚弹出说明。
@Component
export struct BadgesPage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: JsonNetworkClient | undefined = undefined;
  isArkWebReady: boolean = false;
  username: string = '';
  badgeCount: number = 0;
  onBack: () => void = () => {};

  @State private groups: UserBadgeGroup[] = [];
  @State private isLoading: boolean = false;
  @State private loadFailed: boolean = false;
  @State private message: string = '';
  @State private selectedBadge?: UserBadgeItem = undefined;
  @State private showDetail: boolean = false;
  private service?: UserProfileService = undefined;
  private loading: boolean = false;

  aboutToAppear(): void {
    if (this.bridge) {
      this.service = new UserProfileService(this.bridge);
    }
    this.loadBadges();
  }

  build() {
    Stack() {
      // 背景层:铺进顶部状态栏与底部导航条,避免暗黑模式下顶栏露出系统黑底。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 内容层:照常避让状态栏,不扩展。
      Column() {
        PageHeader({
          title: this.getPageTitle(),
          onBack: () => {
            this.onBack();
          }
        })

        this.Content()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.sysTopInset })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .bindSheet(this.showDetail, this.DetailSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      showClose: true,
      onDisappear: () => {
        this.showDetail = false;
      }
    })
  }

  @Builder
  private Content() {
    if (this.groups.length === 0) {
      LoadStateView({
        isLoading: this.isLoading,
        loadingText: '加载中…',
        message: this.message.length > 0 ? this.message : '加载失败',
        showRetry: this.loadFailed,
        emptyTitle: '暂无徽章',
        onRetry: () => {
          this.loadBadges();
        }
      })
    } else {
      Scroll() {
        Column() {
          ForEach(this.groups, (group: UserBadgeGroup) => {
            this.BadgeGroup(group)
          }, (group: UserBadgeGroup) => group.typeId.toString())

          Row()
            .width('100%')
            .height(24)
        }
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  private BadgeGroup(group: UserBadgeGroup) {
    Column() {
      // 分组标题:等级色圆点 + 名称 + 数量。
      Row() {
        Circle()
          .width(8)
          .height(8)
          .fill(badgeTypeColor(group.typeId))
        Text(`${group.typeName} · ${group.badges.length}`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ top: 18, bottom: 4 })

      ForEach(this.chunkRows(group.badges), (row: UserBadgeItem[], rowIndex: number) => {
        Row({ space: 8 }) {
          ForEach(row, (badge: UserBadgeItem) => {
            BadgeTile(badge, (tapped: UserBadgeItem) => {
              this.openDetail(tapped);
            })
          }, (badge: UserBadgeItem) => badge.id.toString())
          ForEach(this.rowFillers(row), (filler: number) => {
            Column()
              .layoutWeight(1)
          }, (filler: number) => `filler_${filler}`)
        }
        .width('100%')
        .margin({ top: rowIndex > 0 ? 8 : 6 })
      }, (row: UserBadgeItem[], rowIndex: number) => `row_${group.typeId}_${rowIndex}_${row.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DetailSheet() {
    Column() {
      if (this.selectedBadge) {
        Column() {
          if (this.selectedBadge.imageUrl) {
            Image(this.selectedBadge.imageUrl)
              .width(48)
              .height(48)
              .objectFit(ImageFit.Contain)
              .draggable(false)
          } else {
            FaIconView({
              icon: this.faIcon(this.selectedBadge.icon && this.selectedBadge.icon.length > 0
                ? this.selectedBadge.icon : 'certificate'),
              iconSize: 40,
              color: badgeTypeColor(this.selectedBadge.badgeTypeId)
            })
          }
        }
        .height(48)
        .justifyContent(FlexAlign.Center)

        Text(this.selectedBadge.name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 14 })

        if (this.getDetailMeta().length > 0) {
          Text(this.getDetailMeta())
            .fontSize(12)
            .fontColor($r('app.color.text_faint'))
            .margin({ top: 6 })
        }

        if (this.selectedBadge.description && this.selectedBadge.description.length > 0) {
          Text(this.selectedBadge.description)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(21)
            .textAlign(TextAlign.Center)
            .margin({ top: 14 })
        }
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 12, bottom: 32 })
    .alignItems(HorizontalAlign.Center)
  }

  // ==================== 数据加载 ====================

  private async loadBadges(): Promise<void> {
    if (!this.service || this.loading) {
      if (!this.service) {
        this.loadFailed = true;
        this.message = '正在准备请求环境';
      }
      return;
    }
    if (this.username.length === 0) {
      this.loadFailed = true;
      this.message = '缺少用户信息';
      return;
    }
    this.loading = true;
    this.isLoading = this.groups.length === 0;
    this.loadFailed = false;

    const result: NetworkResult<UserBadgeGroup[]> = await this.service.getUserBadges(this.username);
    this.loading = false;
    this.isLoading = false;

    if (!result.success || result.data === undefined) {
      this.loadFailed = true;
      this.message = result.error?.message ? result.error.message : '加载失败，请重试';
      Log.i(`${LOG_TAG} load failed status=${result.statusCode}`);
      return;
    }

    this.groups = result.data;
    this.message = '';
    let total: number = 0;
    for (let index: number = 0; index < result.data.length; index++) {
      total += result.data[index].badges.length;
    }
    Log.i(`${LOG_TAG} loaded groups=${result.data.length} badges=${total}`);
  }

  // ==================== 展示辅助 ====================

  private openDetail(badge: UserBadgeItem): void {
    this.selectedBadge = badge;
    this.showDetail = true;
  }

  private getPageTitle(): string {
    return this.badgeCount > 0 ? `徽章 · ${this.badgeCount}` : '徽章';
  }

  // 详情弹层的副信息行:重复次数 · 获得时间。
  private getDetailMeta(): string {
    const badge: UserBadgeItem | undefined = this.selectedBadge;
    if (!badge) {
      return '';
    }
    const parts: string[] = [];
    if (badge.grantCount !== undefined && badge.grantCount > 1) {
      parts.push(`获得 ${badge.grantCount} 次`);
    }
    const granted: string = RelativeTime.fromNow(badge.grantedAt);
    if (granted.length > 0) {
      parts.push(`授予于 ${granted}`);
    }
    return parts.join(' · ');
  }

  private chunkRows(badges: UserBadgeItem[]): UserBadgeItem[][] {
    const rows: UserBadgeItem[][] = [];
    for (let index: number = 0; index < badges.length; index += BADGES_PER_ROW) {
      rows.push(badges.slice(index, index + BADGES_PER_ROW));
    }
    return rows;
  }

  private rowFillers(row: UserBadgeItem[]): number[] {
    const fillers: number[] = [];
    for (let index: number = row.length; index < BADGES_PER_ROW; index++) {
      fillers.push(index);
    }
    return fillers;
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }
}
