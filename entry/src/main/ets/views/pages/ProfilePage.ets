import { Log } from '../../services/logging/Log';
import { bundleManager, common } from '@kit.AbilityKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { DownloadService } from '../../services/content/DownloadService';
import { FileLogger } from '../../services/logging/FileLogger';
import { ThemeManager, ThemeMode } from '../../common/theme/ThemeManager';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { TopicCategory } from '../../models/Topic';
import { User } from '../../models/User';
import {
  UserActionType,
  UserActivityItem,
  UserBadgeItem,
  UserProfileDetail,
  UserSummary,
  UserSummaryStats
} from '../../models/UserProfile';
import { AuthService } from '../../services/auth/AuthService';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { SessionEventBus } from '../../services/session/SessionEventBus';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { UserProfileCache } from '../../services/user/UserProfileCache';
import { UserProfileService } from '../../services/user/UserProfileService';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { UserAvatar } from '../components/UserAvatar';

const LOG_TAG: string = '[ArkDO][Profile]';

// Discourse 信任等级中文名(0-4),user.title 缺省时的兜底展示。
const TRUST_LEVEL_NAMES: string[] = ['新用户', '基本用户', '成员', '活跃用户', '领导者'];

// 鸿蒙设置页式卡片分组:灰底 + 无描边圆角卡片。
// 页面两侧留白 12,卡片圆角 16,卡片内部留白 16,卡片间距 12。
const PAGE_MARGIN: number = 12;
const CARD_RADIUS: number = 16;
const CARD_PADDING: number = 16;
const CARD_GAP: number = 12;
// 统计区固定高度:加载占位与 4×2 数据网格同高,避免数据回来后卡片长高跳动。
const STATS_AREA_HEIGHT: number = 126;
// 用户卡 meta 行(加入天数/最近发帖/浏览量)固定高度,同理防跳动。
const USER_META_HEIGHT: number = 26;

@Component
export struct ProfilePage {
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  // 登录态由 RootTabPage 统一维护(会话事件 + 前台轮询),本页只接收,不再自己查
  // /session/current.json——否则每次 push 进来都闪一次「检查登录状态」。
  @Prop @Watch('handleAccountChanged') accountUser: User = { id: 0, username: '' };
  @Prop @Watch('handleAccountChanged') isLoggedIn: boolean = false;
  @Prop isCheckingSession: boolean = false;
  @Prop hasCheckedSession: boolean = false;
  onLoginClick: () => void = () => {};
  // 打开站内 Web 页(私信/草稿等归档入口)与原生帖子详情,由 RootTabPage 注入。
  onOpenWeb: (url: string, title?: string) => void = () => {};
  onOpenTopic: (topicId: number, title: string, postNumber?: number) => void = () => {};
  // 书签已原生化:进原生书签页而非 Web。
  onOpenBookmarks: (username: string) => void = () => {};
  @StorageLink('themeMode') themeMode: ThemeMode = ThemeMode.SYSTEM;
  @State private profileDetail?: UserProfileDetail = undefined;
  @State private summaryStats?: UserSummaryStats = undefined;
  @State private topBadges: UserBadgeItem[] = [];
  @State private recentActivity: UserActivityItem[] = [];
  @State private categories: TopicCategory[] = [];
  @State private isLoggingOut: boolean = false;
  @State private appVersion: string = '';
  // 日志工具:大小标签实时展示,详细日志开关持久化,导出时防重复点击。
  @State private logSizeLabel: string = '';
  @State private verboseLog: boolean = false;
  @State private isExportingLog: boolean = false;
  // 已加载资料的用户名:切换账号后重新加载,同账号重进不重复拉取。
  private loadedProfileUsername: string = '';
  private categoryIndex: CategoryIndex = new CategoryIndex();

  aboutToAppear(): void {
    this.readAppVersion();
    this.handleAccountChanged();
    this.verboseLog = FileLogger.isVerbose();
    this.refreshLogSize();
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
        Text('我的')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding({ left: PAGE_MARGIN + CARD_PADDING, right: PAGE_MARGIN + CARD_PADDING, top: 20, bottom: 2 })

        Scroll() {
          Column() {
            if (this.isLoggedIn) {
              this.LoggedInContent()
            } else {
              this.AnonymousContent()
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
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
  }

  // ==================== 登录态 ====================

  @Builder
  private LoggedInContent() {
    Column() {
      // 卡片 1:身份 + 论坛数据
      Column() {
        Row() {
          UserAvatar({ user: this.accountUser, avatarSize: 56 })
          Column() {
            Text(this.getDisplayName())
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row() {
              Text(this.getUsernameLabel())
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              if (this.getTrustLabel().length > 0) {
                Text(' · ')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Text(this.getTrustLabel())
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ld_accent'))
              }
            }
            .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 14 })
          this.ChevronIcon()
        }
        .width('100%')
        .padding({ left: CARD_PADDING, right: CARD_PADDING, top: CARD_PADDING, bottom: 6 })
        .onClick(() => {
          this.openUserWebPage('', this.getDisplayName());
        })

        // meta 行固定高度:资料回来前后卡片不跳动。
        Text(this.getUserMetaLine())
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .height(USER_META_HEIGHT)
          .padding({ left: CARD_PADDING, right: CARD_PADDING })

        this.HairlineInset()

        // 统计区固定高度:加载占位与数据网格同高。
        if (this.summaryStats) {
          this.StatsGrid(this.summaryStats)
        } else {
          Row() {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.ld_accent'))
            Text('正在加载论坛数据')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .height(STATS_AREA_HEIGHT)
          .justifyContent(FlexAlign.Center)
        }
      }
      .cardStyle()

      // 卡片 2:快捷入口
      Row() {
        this.QuickEntry($r('sys.symbol.envelope'), '私信', this.getUnreadMessageCount(), true, false,
          `/u/${this.getUsername()}/messages`)
        this.QuickEntryNative($r('sys.symbol.bookmark'), '书签', () => {
          if (this.getUsername().length > 0) {
            this.onOpenBookmarks(this.getUsername());
          }
        })
        this.QuickEntry($r('sys.symbol.heart'), '我的点赞', 0, false, true,
          `/u/${this.getUsername()}/activity/likes-given`)
        this.QuickEntry($r('sys.symbol.square_and_pencil'), '草稿', this.getDraftCount(), false, false,
          `/u/${this.getUsername()}/activity/drafts`)
      }
      .padding({ top: CARD_PADDING, bottom: 14 })
      .cardStyle()

      // 卡片 3:徽章
      Column() {
        this.SectionHead(this.getBadgeHeadLabel(), '全部 ›', `/u/${this.getUsername()}/badges`)
        if (this.topBadges.length > 0) {
          // 摘要接口最多返回 6 枚,固定 3 列网格等分展示,不做横滑。
          Column() {
            ForEach(this.getBadgeRows(), (row: UserBadgeItem[], rowIndex: number) => {
              Row({ space: 8 }) {
                ForEach(row, (badge: UserBadgeItem) => {
                  this.BadgeTile(badge)
                }, (badge: UserBadgeItem) => badge.id.toString())
                // 不满 3 枚的行用透明占位补齐,保持等分列宽。
                ForEach(this.getBadgeRowFillers(row), (filler: number) => {
                  Column()
                    .layoutWeight(1)
                }, (filler: number) => `filler_${filler}`)
              }
              .width('100%')
              .margin({ top: rowIndex > 0 ? 8 : 0 })
            }, (row: UserBadgeItem[], rowIndex: number) => `row_${rowIndex}_${row.length}`)
          }
          .width('100%')
          .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 10, bottom: CARD_PADDING })
        } else {
          Text('暂无徽章')
            .fontSize(13)
            .fontColor($r('app.color.text_faint'))
            .width('100%')
            .padding({ left: CARD_PADDING, top: 10, bottom: CARD_PADDING })
        }
      }
      .cardStyle()

      // 卡片 4:最近活动
      Column() {
        this.SectionHead('最近活动', '全部 ›', `/u/${this.getUsername()}/activity`)
        if (this.recentActivity.length > 0) {
          ForEach(this.recentActivity, (item: UserActivityItem, index: number) => {
            Column() {
              if (index > 0) {
                this.HairlineInset()
              }
              this.ActivityRow(item)
            }
            .width('100%')
          }, (item: UserActivityItem, index: number) => `${item.topicId}_${item.postNumber ?? 0}_${index}`)
          this.ActivityFooterLinks()
        } else {
          Text('最近没有发帖')
            .fontSize(13)
            .fontColor($r('app.color.text_faint'))
            .width('100%')
            .padding({ left: CARD_PADDING, top: 10, bottom: CARD_PADDING })
        }
      }
      .cardStyle()

      // 卡片 5:设置
      this.GroupLabel('设置')
      Column() {
        this.AppearanceCell()
        this.HairlineInset()
        this.SettingCell($r('sys.symbol.security_shield'), '账号与安全', '', () => {
          this.openUserWebPage('/preferences/security', '账号与安全');
        })
        this.HairlineInset()
        this.SettingCell($r('sys.symbol.info_circle'), '关于 ArkDO', this.getVersionLabel(), undefined)
      }
      .cardStyle()
      .margin({ top: 0 })

      this.LogGroup()

      // 卡片 6:退出登录
      Row() {
        if (this.isLoggingOut) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.ld_danger'))
            .margin({ right: 8 })
        }
        Text('退出登录')
          .fontSize(15)
          .fontColor($r('app.color.ld_danger'))
      }
      .justifyContent(FlexAlign.Center)
      .padding({ top: 14, bottom: 14 })
      .cardStyle()
      .onClick(() => {
        this.confirmLogout();
      })

      Row()
        .width('100%')
        .height(40)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private StatsGrid(stats: UserSummaryStats) {
    Column() {
      Row() {
        this.StatCell(this.formatCount(stats.daysVisited), '访问天数')
        this.StatCell(this.formatTimeRead(stats.timeReadSeconds), '阅读时长')
        this.StatCell(this.formatCount(stats.likesReceived), '收到的赞')
        this.StatCell(this.formatCount(stats.likesGiven), '送出的赞')
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 14 })

      Row() {
        this.StatCell(this.formatCount(stats.topicCount), '创建话题')
        this.StatCell(this.formatCount(stats.postCount), '回复')
        this.StatCell(this.formatCount(stats.topicsEntered), '浏览话题')
        this.StatCell(stats.solvedCount !== undefined ? this.formatCount(stats.solvedCount) : '—', '解决方案')
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 16, bottom: CARD_PADDING })
    }
    .width('100%')
    .height(STATS_AREA_HEIGHT)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private StatCell(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_faint'))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
  }

  @Builder
  private QuickEntry(symbol: Resource, label: string, badgeCount: number, highPriority: boolean, love: boolean, path: string) {
    Column() {
      Badge({
        count: badgeCount,
        maxCount: 99,
        position: BadgePosition.RightTop,
        style: {
          badgeSize: 16,
          fontSize: 10,
          badgeColor: highPriority ? $r('app.color.ld_danger') : $r('app.color.ld_accent'),
          // BadgeStyle 的描边默认红色,不与底色同色会在角标外露一圈红边。
          borderColor: highPriority ? $r('app.color.ld_danger') : $r('app.color.ld_accent'),
          borderWidth: 0
        }
      }) {
        SymbolGlyph(symbol)
          .fontSize(24)
          .fontColor([love ? $r('app.color.ld_love') : $r('app.color.text_primary')])
      }
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 7 })
    }
    .layoutWeight(1)
    .onClick(() => {
      this.openWebPath(path, label);
    })
  }

  // 无角标、走自定义点击的快捷入口(书签等已原生化的入口)。
  @Builder
  private QuickEntryNative(symbol: Resource, label: string, onEntryClick: () => void) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 7 })
    }
    .layoutWeight(1)
    .onClick(() => {
      onEntryClick();
    })
  }

  // 徽章小卡片:图片徽章(image_url)原图展示;FA 图标徽章按金/银/铜等级色染色。
  // 可重复获得的徽章在名字后缀 ×N。
  @Builder
  private BadgeTile(badge: UserBadgeItem) {
    Column() {
      Column() {
        if (badge.imageUrl) {
          Image(badge.imageUrl)
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        } else {
          FaIconView({
            icon: this.faIcon(badge.icon && badge.icon.length > 0 ? badge.icon : 'certificate'),
            iconSize: 26,
            color: this.getBadgeTypeColor(badge.badgeTypeId)
          })
        }
      }
      .height(32)
      .justifyContent(FlexAlign.Center)

      Text(this.getBadgeTileLabel(badge))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 7 })
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 10, left: 6, right: 6 })
    .borderRadius(12)
    .backgroundColor($r('app.color.surface_band'))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ActivityRow(item: UserActivityItem) {
    Column() {
      Row() {
        if (item.actionType === UserActionType.REPLY) {
          FaIconView({
            icon: this.faIcon('reply'),
            iconSize: 13,
            color: $r('app.color.text_faint')
          })
            .margin({ top: 3 })
        }
        Text(item.title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: item.actionType === UserActionType.REPLY ? 6 : 0 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        if (this.getCategoryFor(item.categoryId)) {
          Row() {
            Rect({ width: 9, height: 9 })
              .fill(this.getCategoryColor(item.categoryId))
            Text(this.getCategoryName(item.categoryId))
              .fontSize(12)
              .fontColor($r('app.color.text_faint'))
              .margin({ left: 5 })
          }
        }
        Blank()
        Text(RelativeTime.fromNow(item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
      }
      .width('100%')
      .margin({ top: 5 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpenTopic(item.topicId, item.title, item.postNumber);
    })
  }

  @Builder
  private ActivityFooterLinks() {
    Row() {
      Text(this.getTopicsLinkLabel())
        .fontSize(13)
        .fontColor($r('app.color.ld_accent'))
        .onClick(() => {
          this.openUserWebPage('/activity/topics', '我的话题');
        })
      Text('·')
        .fontSize(13)
        .fontColor($r('app.color.text_faint'))
        .margin({ left: 10, right: 10 })
      Text(this.getRepliesLinkLabel())
        .fontSize(13)
        .fontColor($r('app.color.ld_accent'))
        .onClick(() => {
          this.openUserWebPage('/activity/replies', '我的回复');
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 8, bottom: 14 })
  }

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

  // ==================== 未登录态 ====================

  @Builder
  private AnonymousContent() {
    Column() {
      Column() {
        Column() {
          if (this.isCheckingSession && !this.hasCheckedSession) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color($r('app.color.ld_accent'))
          } else {
            SymbolGlyph($r('sys.symbol.person'))
              .fontSize(32)
              .fontColor([$r('app.color.text_faint')])
          }
        }
        .width(68)
        .height(68)
        .justifyContent(FlexAlign.Center)
        .borderRadius(34)
        .border({ width: 1, color: $r('app.color.border') })

        Text(this.hasCheckedSession ? '登录 Linux.do' : '检查登录状态')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })

        Text(this.getAnonymousSubtitle())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
          .padding({ left: CARD_PADDING, right: CARD_PADDING })

        if (!this.isCheckingSession || this.hasCheckedSession) {
          Button('立即登录')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.ld_accent'))
            .height(42)
            .padding({ left: 44, right: 44 })
            .borderRadius(21)
            .margin({ top: 22 })
            .onClick(() => {
              this.onLoginClick();
            })

          Column() {
            Text('参与回帖、点赞与投票')
              .fontSize(13)
              .fontColor($r('app.color.text_faint'))
            Text('私信与实时通知提醒')
              .fontSize(13)
              .fontColor($r('app.color.text_faint'))
              .margin({ top: 6 })
            Text('跨设备同步阅读进度')
              .fontSize(13)
              .fontColor($r('app.color.text_faint'))
              .margin({ top: 6 })
          }
          .margin({ top: 16 })
        }
      }
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 32, bottom: 26 })
      .cardStyle()

      this.GroupLabel('设置')
      Column() {
        this.AppearanceCell()
        this.HairlineInset()
        this.SettingCell($r('sys.symbol.info_circle'), '关于 ArkDO', this.getVersionLabel(), undefined)
      }
      .cardStyle()
      .margin({ top: 0 })

      this.LogGroup()

      Row()
        .width('100%')
        .height(40)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 通用 Builder ====================

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
  private SectionHead(title: string, more: string, morePath: string) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(more)
        .fontSize(12)
        .fontColor($r('app.color.ld_accent'))
        .onClick(() => {
          this.openWebPath(morePath, title);
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 4 })
  }

  @Builder
  private ChevronIcon() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(14)
      .fontColor([$r('app.color.text_faint')])
  }

  // ==================== 数据加载 ====================

  // 资料/摘要/活动/分类并行加载,各自落地各自的 @State;
  // 完成时校验用户未切换(loadedProfileUsername),避免登出/换号后旧响应污染界面。
  // stale-while-revalidate:先用内存缓存秒出上次数据(无转圈),后台请求回来再原地更新。
  private loadProfileData(username: string): void {
    if (this.loadedProfileUsername === username) {
      return;
    }
    this.loadedProfileUsername = username;

    const cachedDetail: UserProfileDetail | undefined = UserProfileCache.getDetail(username);
    const cachedSummary: UserSummary | undefined = UserProfileCache.getSummary(username);
    const cachedActivity: UserActivityItem[] | undefined = UserProfileCache.getActivity(username);
    this.profileDetail = cachedDetail;
    this.summaryStats = cachedSummary ? cachedSummary.stats : undefined;
    this.topBadges = cachedSummary ? cachedSummary.topBadges : [];
    this.recentActivity = cachedActivity ? cachedActivity : [];

    const service: UserProfileService = new UserProfileService(this.bridge);
    this.loadDetail(service, username);
    this.loadSummary(service, username);
    this.loadActivity(service, username);
    this.loadCategories();
  }

  private resetProfileData(): void {
    this.loadedProfileUsername = '';
    this.profileDetail = undefined;
    this.summaryStats = undefined;
    this.topBadges = [];
    this.recentActivity = [];
  }

  private async loadDetail(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserProfileDetail> = await service.getProfileDetail(username);
    if (this.loadedProfileUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.profileDetail = result.data;
      UserProfileCache.setDetail(username, result.data);
      Log.i(`${LOG_TAG} profile detail loaded trustLevel=${result.data.trustLevel ?? -1}`);
    } else {
      Log.i(`${LOG_TAG} profile detail load failed status=${result.statusCode}`);
    }
  }

  private async loadSummary(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserSummary> = await service.getSummary(username);
    if (this.loadedProfileUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.summaryStats = result.data.stats;
      this.topBadges = result.data.topBadges;
      UserProfileCache.setSummary(username, result.data);
      Log.i(`${LOG_TAG} summary loaded badges=${result.data.topBadges.length}`);
    } else {
      Log.i(`${LOG_TAG} summary load failed status=${result.statusCode}`);
    }
  }

  private async loadActivity(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserActivityItem[]> = await service.getRecentActivity(username);
    if (this.loadedProfileUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.recentActivity = result.data;
      UserProfileCache.setActivity(username, result.data);
      Log.i(`${LOG_TAG} recent activity loaded count=${result.data.length}`);
    } else {
      Log.i(`${LOG_TAG} recent activity load failed status=${result.statusCode}`);
    }
  }

  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  // ==================== 退出登录 ====================

  private confirmLogout(): void {
    if (this.isLoggingOut) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '退出登录',
      message: '确定要退出当前账号吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: $r('app.color.ld_danger'),
        action: () => {
          this.performLogout();
        }
      }
    });
  }

  private async performLogout(): Promise<void> {
    const username: string = this.getUsername();
    if (username.length === 0 || this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    const result: NetworkResult<boolean> = await new AuthService(this.bridge).logout(username);
    this.isLoggingOut = false;
    if (!result.success) {
      this.showToast(result.error?.message ? result.error.message : '退出登录失败，请稍后再试');
      Log.i(`${LOG_TAG} logout failed status=${result.statusCode}`);
      return;
    }
    Log.i(`${LOG_TAG} logout success`);
    this.showToast('已退出登录');
    // 会话变化会触发 host webview 重载,先关闭就绪门闩,与登录成功走同一条刷新链路。
    this.bridge.markHostReloading();
    SessionEventBus.notifySessionChanged();
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Log.i(`${LOG_TAG} toast failed: ${message}`);
    }
  }

  // ==================== 事件 ====================

  // 登录态/账号变化(含登录、登出、切号):按当前 props 重新对齐本页数据。
  private handleAccountChanged(): void {
    if (this.isLoggedIn && this.accountUser.username.length > 0) {
      this.loadProfileData(this.accountUser.username);
      return;
    }
    this.resetProfileData();
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady) {
      this.handleAccountChanged();
    }
  }

  private setThemeMode(mode: ThemeMode): void {
    ThemeManager.setMode(getContext(this), mode);
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

  private readAppVersion(): void {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = info.versionName;
    } catch (err) {
      Log.i(`${LOG_TAG} read app version failed`);
    }
  }

  // ==================== 展示辅助 ====================

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }

  private getDisplayName(): string {
    if (!this.isLoggedIn) {
      return '';
    }
    return this.accountUser.displayName && this.accountUser.displayName.length > 0
      ? this.accountUser.displayName
      : this.accountUser.username;
  }

  private getUsername(): string {
    return this.isLoggedIn ? this.accountUser.username : '';
  }

  private getUsernameLabel(): string {
    const username: string = this.getUsername();
    return username.length > 0 ? `@${username}` : '';
  }

  // 信任等级标签:优先站点头衔(user.title),否则用 TL 默认名;资料未加载完为空。
  private getTrustLabel(): string {
    const detail: UserProfileDetail | undefined = this.profileDetail;
    if (!detail || detail.trustLevel === undefined) {
      return '';
    }
    const levelName: string = detail.title && detail.title.length > 0
      ? detail.title
      : (detail.trustLevel >= 0 && detail.trustLevel < TRUST_LEVEL_NAMES.length
        ? TRUST_LEVEL_NAMES[detail.trustLevel]
        : '');
    return levelName.length > 0 ? `TL${detail.trustLevel} ${levelName}` : `TL${detail.trustLevel}`;
  }

  private getUserMetaLine(): string {
    const detail: UserProfileDetail | undefined = this.profileDetail;
    if (!detail) {
      return '';
    }
    const parts: string[] = [];
    const joinedDays: number = this.daysSince(detail.createdAt);
    if (joinedDays > 0) {
      parts.push(`加入 ${joinedDays} 天`);
    }
    const lastPosted: string = RelativeTime.fromNow(detail.lastPostedAt);
    if (lastPosted.length > 0) {
      parts.push(`最近发帖 ${lastPosted}`);
    }
    if (detail.profileViewCount !== undefined && detail.profileViewCount > 0) {
      parts.push(`浏览量 ${this.formatCount(detail.profileViewCount)}`);
    }
    return parts.join(' · ');
  }

  // 徽章按 3 枚一行分组。
  private getBadgeRows(): UserBadgeItem[][] {
    const rows: UserBadgeItem[][] = [];
    for (let index: number = 0; index < this.topBadges.length; index += 3) {
      rows.push(this.topBadges.slice(index, index + 3));
    }
    return rows;
  }

  // 末行不足 3 枚时需要的占位数量([1]、[1,2] 之类,仅用于 ForEach 生成透明格)。
  private getBadgeRowFillers(row: UserBadgeItem[]): number[] {
    const fillers: number[] = [];
    for (let index: number = row.length; index < 3; index++) {
      fillers.push(index);
    }
    return fillers;
  }

  private getBadgeTileLabel(badge: UserBadgeItem): string {
    return badge.grantCount !== undefined && badge.grantCount > 1
      ? `${badge.name} ×${badge.grantCount}`
      : badge.name;
  }

  private getBadgeHeadLabel(): string {
    const badgeCount: number | undefined = this.profileDetail?.badgeCount;
    return badgeCount !== undefined && badgeCount > 0 ? `徽章 · ${badgeCount}` : '徽章';
  }

  private getTopicsLinkLabel(): string {
    const count: number | undefined = this.summaryStats?.topicCount;
    return count !== undefined ? `我的话题 ${this.formatCount(count)} ›` : '我的话题 ›';
  }

  private getRepliesLinkLabel(): string {
    const count: number | undefined = this.summaryStats?.postCount;
    return count !== undefined ? `我的回复 ${this.formatCount(count)} ›` : '我的回复 ›';
  }

  private getUnreadMessageCount(): number {
    const count: number | undefined = this.accountUser.unreadHighPriorityNotifications;
    return count !== undefined ? count : 0;
  }

  private getDraftCount(): number {
    const count: number | undefined = this.accountUser.draftCount;
    return count !== undefined ? count : 0;
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

  private getVersionLabel(): string {
    return this.appVersion.length > 0 ? `v${this.appVersion}` : '';
  }

  private getAnonymousSubtitle(): string {
    if (this.hasCheckedSession) {
      return '真诚、友善、团结、专业，共建你我引以为荣之社区';
    }
    return '正在检查登录状态';
  }

  private getBadgeTypeColor(badgeTypeId: number): Resource {
    if (badgeTypeId === 1) {
      return $r('app.color.ld_gold');
    }
    if (badgeTypeId === 2) {
      return $r('app.color.ld_silver');
    }
    return $r('app.color.ld_bronze');
  }

  private getCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.find(this.categories, categoryId);
  }

  private getCategoryColor(categoryId?: number): string {
    const category: TopicCategory | undefined = this.getCategoryFor(categoryId);
    return category ? `#${category.color}` : '#6B7280';
  }

  private getCategoryName(categoryId?: number): string {
    const category: TopicCategory | undefined = this.getCategoryFor(categoryId);
    return category ? category.name : '';
  }

  // 千位缩写:与 Discourse 列表一致(1.2k / 12k)。纯整数运算避免浮点尾差。
  private formatCount(value: number): string {
    if (value < 1000) {
      return `${value}`;
    }
    if (value < 10000) {
      const tenths: number = Math.floor(value / 100);
      const whole: number = Math.floor(tenths / 10);
      const frac: number = tenths % 10;
      return frac === 0 ? `${whole}k` : `${whole}.${frac}k`;
    }
    return `${Math.floor(value / 1000)}k`;
  }

  private formatTimeRead(seconds: number): string {
    if (seconds < 3600) {
      return `${Math.max(1, Math.round(seconds / 60))}m`;
    }
    return `${Math.round(seconds / 3600)}h`;
  }

  private daysSince(iso?: string): number {
    if (!iso || iso.length === 0) {
      return 0;
    }
    const match: RegExpMatchArray | null = iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!match) {
      return 0;
    }
    const thenMillis: number = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    const days: number = Math.floor((Date.now() - thenMillis) / 86400000);
    return days > 0 ? days : 1;
  }

  private openUserWebPage(subPath: string, title?: string): void {
    const username: string = this.getUsername();
    if (username.length === 0) {
      return;
    }
    this.onOpenWeb(`${AppConstants.BASE_URL}/u/${encodeURIComponent(username)}${subPath}`, title);
  }

  private openWebPath(path: string, title?: string): void {
    if (path.length === 0) {
      return;
    }
    this.onOpenWeb(`${AppConstants.BASE_URL}${path}`, title);
  }
}
