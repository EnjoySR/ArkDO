import { Log } from '../../services/logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { RelativeTime } from '../../common/utils/RelativeTime';
import { TopicCategory } from '../../models/Topic';
import { TopicMetadataBadges } from '../components/TopicBadges';
import { User } from '../../models/User';
import {
  EndorsableCategoriesResult,
  EndorsableCategory,
  toAvatarUser,
  UserActionType,
  UserActivityItem,
  UserBadgeItem,
  UserInteraction,
  UserProfileDetail,
  UserSummary,
  UserSummaryStats,
  UserTopReply,
  UserTopTopic
} from '../../models/UserProfile';
import { ArkWebNetworkBridge } from '../../services/network/ArkWebNetworkBridge';
import { NetworkResult } from '../../services/network/NetworkTypes';
import { CategoryIndex } from '../../services/site/CategoryIndex';
import { UserProfileCache } from '../../services/user/UserProfileCache';
import { UserProfileService } from '../../services/user/UserProfileService';
import { UserRelationService } from '../../services/user/UserRelationService';
import { FaIconDefinition, FaIconView, getFaIcon } from '../components/FaIcon';
import { getEmojiUrl } from '../components/EmojiUrlRegistry';
import { HolographicText } from '../components/HolographicText';
import { BadgeTile } from '../components/BadgeTile';
import { UserAvatar } from '../components/UserAvatar';
import { SYS_TOP_INSET_KEY } from '../../common/utils/ImmersiveWindow';
import { showToast as promptToast } from '../../common/utils/Toast';

const LOG_TAG: string = '[ArkDO][UserProfile]';

// Discourse 信任等级中文名(0-4),user.title 缺省时的兜底展示。与「我的」页同源。
const TRUST_LEVEL_NAMES: string[] = ['新用户', '基本用户', '成员', '活跃用户', '领导者'];

// 带全息闪动特效的称号(与 TopicPostItem 的 HOLOGRAPHIC_TITLES 保持一致)。
const HOLOGRAPHIC_TITLES: Set<string> = new Set<string>(['Premium', '种子用户', '破界者']);
// 点赞心形红,与帖子详情楼层的实心 heart 一致(TopicPostItem 的 LIKE_RED)。
const LIKE_HEART_RED: string = '#EF4444';

// 与「我的」页(ProfilePage)完全同一套卡片度量:两页是孪生页面,视觉必须对称。
const PAGE_MARGIN: number = 12;
const CARD_RADIUS: number = 16;
const CARD_PADDING: number = 16;
const CARD_GAP: number = 12;
// 统计区固定高度:加载占位与 4×2 数据网格同高,避免数据回来后卡片长高跳动。
const STATS_AREA_HEIGHT: number = 126;
// meta 行(加入天数/最近发帖/浏览量)固定高度,同理防跳动。
const USER_META_HEIGHT: number = 26;
// 标题栏名字浮现的滚动阈值:身份区大名字划出视野后,标题栏才接管。
const TITLE_REVEAL_OFFSET: number = 64;

// 内容区分段。三者都是「话题行」列表,平铺会读起来像同一段重复三遍,故共用一块区域。
const SEGMENT_TOP_TOPICS: number = 0;
const SEGMENT_TOP_REPLIES: number = 1;
const SEGMENT_RECENT: number = 2;

// 他人主页:点任意头像进来。只回答四件事——他是谁 / 靠不靠谱 / 说过什么 / 怎么找他。
// 不做的:等级进度(connect 只认当前登录者)、已读(/read.json 固定返回自己)、
// 书签(私有 403)、草稿/设置/登出(他人视角无意义)。故不复用「我的」页而单独成页。
@Component
export struct UserProfilePage {
  // 窗口常驻全屏布局:内容层自行避让状态栏(背景层已天然铺满整屏,含状态栏条)。
  @StorageProp(SYS_TOP_INSET_KEY) private sysTopInset: number = 0;
  bridge: ArkWebNetworkBridge = new ArkWebNetworkBridge();
  @Prop @Watch('handleArkWebReadyChanged') isArkWebReady: boolean = false;
  username: string = '';
  // 点击来源(帖子作者、互动圈头像等)顺手透传的名字与头像:资料请求回来前先拿它渲染,
  // 避免首屏从空白跳到有内容。资料回来后以 profileDetail 为准(它才有 flair)。
  seedDisplayName: string = '';
  seedAvatarTemplate: string = '';
  // 点击来源的 user id:头像形状按 id 决定(id===1 方形),种子缺 id 会先圆后方闪一下。
  seedUserId: number = 0;
  onBack: () => void = () => {};
  onOpenTopic: (topicId: number, title: string, postNumber?: number) => void = () => {};
  onOpenActivity: (username: string, filter: string, title: string) => void = () => {};
  onOpenBadges: (username: string, badgeCount: number) => void = () => {};
  // 被采纳的答案列表:四个插件页里唯一保留的,因为它是「靠不靠谱」的硬证据。
  onOpenSolved: (username: string, solvedCount: number) => void = () => {};
  // 互动圈头像可点:递归进目标用户的本页(带上 id 以免头像形状先圆后方闪)。
  onOpenUser: (username: string, displayName: string, avatarTemplate: string, userId: number) => void = () => {};
  onOpenWeb: (url: string, title?: string) => void = () => {};

  @State private profileDetail?: UserProfileDetail = undefined;
  @State private summary?: UserSummary = undefined;
  @State private recentActivity: UserActivityItem[] = [];
  @State private categories: TopicCategory[] = [];
  @State private selectedSegment: number = SEGMENT_TOP_TOPICS;
  @State private isTitleShown: boolean = false;
  // 关注态:先取 detail.isFollowed,乐观切换时本地翻转,请求失败回滚。
  // 用独立 @State 而非直接读 detail:detail 是整体替换的对象,细粒度翻转它不可靠(投票撤销 BUG 同因)。
  @State private isFollowing: boolean = false;
  @State private followPending: boolean = false;
  // 已认可 TA 的分类数(决定「认可」还是「在 N 个类别中得到认可」)。
  @State private endorsedCount: number = 0;
  // 认可弹窗。
  @State private showEndorseSheet: boolean = false;
  @State private endorsableCategories: EndorsableCategory[] = [];
  @State private remainingEndorsements: number = 0;
  @State private endorseLoading: boolean = false;
  @State private endorseSubmitting: boolean = false;
  @State private endorseSelectedIds: number[] = [];
  // 已加载的用户名:同一用户重进不重复拉取(缓存已按 username 分键)。
  private loadedUsername: string = '';
  private categoryIndex: CategoryIndex = new CategoryIndex();
  private scroller: Scroller = new Scroller();
  private relationService?: UserRelationService = undefined;

  aboutToAppear(): void {
    this.loadProfileData();
  }

  // 卡片分组容器:与「我的」页同款,灰底衬白卡,无描边。
  @Styles
  cardStyle() {
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(CARD_RADIUS)
    .margin({ top: CARD_GAP })
  }

  build() {
    Stack() {
      // 背景层:灰底延伸进顶部状态栏与底部导航条;内容层不扩展,照常避让。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg_gray'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        this.TitleBar()

        Scroll(this.scroller) {
          Column() {
            // 顺序:身份 → 徽章 → 互动圈 → 内容(热门话题/回复/最近)。内容区列表最长,放最后。
            this.IdentityCard()
            this.BadgesCard()
            this.CircleCard()
            this.ContentCard()
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
        .onDidScroll(() => {
          this.updateTitleVisibility();
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.sysTopInset })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .bindSheet($$this.showEndorseSheet, this.EndorseSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true,
      title: { title: '认可用户' }
    })
  }

  // ==================== 操作按钮 ====================

  // 认可 + 关注 同一行,各半宽。私信已移到头像行右侧。两者都按插件字段条件显示;
  // 只有一个可用时它独占整行,都不可用则整行不渲染。
  // 两个子按钮做成无参 @Builder、内部直接读 @State——不能像旧 GhostButton 那样把
  // isFollowing/endorsedCount 当参数传:值参 @Builder 捕获初值不随 @State 重绘,
  // 会出现「toast 已关注但按钮不变」(与之前「一直正在加载」同一病根)。
  @Builder
  private ActionButtons() {
    if (this.hasEndorse() || this.hasFollow()) {
      Row({ space: 10 }) {
        if (this.hasEndorse()) {
          this.EndorseButton()
        }
        if (this.hasFollow()) {
          this.FollowButton()
        }
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 2, bottom: 14 })
    } else {
      // 无操作可显示时留一点底部间距,避免统计区贴着 meta 行。
      Row()
        .width('100%')
        .height(8)
    }
  }

  // 关注按钮:请求中显示 loading,完成后按 isFollowing 切「关注/已关注」+ 图标。
  // 文字/图标用 text_body(明≈官网 #434343,暗 #C9CED7 可见);已关注用主题蓝 ld_accent。
  @Builder
  private FollowButton() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row() {
        if (this.followPending) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.isFollowing ? $r('app.color.ld_accent') : $r('app.color.text_body'))
            .margin({ right: 7 })
        } else {
          FaIconView({
            icon: this.faIcon(this.isFollowing ? 'user-check' : 'user-plus'),
            iconSize: 15,
            color: this.isFollowing ? $r('app.color.ld_accent') : $r('app.color.text_body')
          })
            .margin({ right: 7 })
        }
        Text(this.isFollowing ? '已关注' : '关注')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isFollowing ? $r('app.color.ld_accent') : $r('app.color.text_body'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(38)
    .backgroundColor($r('app.color.surface_card'))
    .borderWidth(1)
    .borderColor($r('app.color.border'))
    .onClick(() => {
      this.toggleFollow();
    })
  }

  // 认可按钮:已认可显示「已认可 · N」+ 勾图标(主题蓝),否则普通「认可」;点开弹窗。
  @Builder
  private EndorseButton() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row() {
        if (this.endorsedCount > 0) {
          FaIconView({
            icon: this.faIcon('circle-check'),
            iconSize: 15,
            color: $r('app.color.ld_accent')
          })
            .margin({ right: 7 })
        }
        Text(this.endorsedCount > 0 ? `已认可 · ${this.endorsedCount}` : '认可')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.endorsedCount > 0 ? $r('app.color.ld_accent') : $r('app.color.text_body'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(38)
    .backgroundColor($r('app.color.surface_card'))
    .borderWidth(1)
    .borderColor($r('app.color.border'))
    .onClick(() => {
      this.openEndorseSheet();
    })
  }

  // 认可弹窗:「kevin 的优点是什么?」+ 分类多选 + 今天还剩 N 个认可 + 认可按钮。
  @Builder
  private EndorseSheet() {
    Column() {
      Text(`${this.getDisplayName()} 的优点是什么？`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 8 })

      if (this.endorseLoading) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.ld_accent'))
          Text('加载可认可的类别')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
      } else if (this.endorsableCategories.length === 0) {
        Text('暂无可认可的类别')
          .fontSize(14)
          .fontColor($r('app.color.text_faint'))
          .width('100%')
          .height(120)
          .textAlign(TextAlign.Center)
      } else {
        Column() {
          ForEach(this.endorsableCategories, (category: EndorsableCategory) => {
            Row() {
              Checkbox()
                .select(this.endorseSelectedIds.includes(category.id))
                .selectedColor($r('app.color.ld_accent'))
                .onChange((checked: boolean) => {
                  this.toggleEndorseSelection(category.id, checked);
                })
              Text(category.name)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .margin({ left: 4 })
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.toggleEndorseSelection(category.id, !this.endorseSelectedIds.includes(category.id));
            })
          }, (category: EndorsableCategory) => `endorse_${category.id}`)
        }
        .width('100%')

        Row() {
          Button('认可', { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.ld_accent'))
            .enabled(this.endorseSelectedIds.length > 0 && !this.endorseSubmitting)
            .opacity(this.endorseSelectedIds.length > 0 && !this.endorseSubmitting ? 1 : 0.5)
            .padding({ left: 28, right: 28 })
            .onClick(() => {
              this.submitEndorse();
            })
          Text(`今天还剩 ${this.remainingEndorsements} 个认可`)
            .fontSize(13)
            .fontColor($r('app.color.text_faint'))
            .margin({ left: 14 })
        }
        .width('100%')
        .margin({ top: 14 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 标题栏 ====================

  @Builder
  private TitleBar() {
    Row() {
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

      // 双层标题(同帖子详情):两层始终挂载、叠层,靠 opacity+translate 随 isTitleShown 交叉切换。
      // A 层「个人资料」淡出上滑,B 层「昵称 + 状态表情」从下方(y:+8)滑上来淡入 → 从下往上浮现。
      Stack({ alignContent: Alignment.Start }) {
        // A 层:未滚动时的静态标题。
        Text('个人资料')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .opacity(this.isTitleShown ? 0 : 1)
          .translate({ y: this.isTitleShown ? -8 : 0 })
          .hitTestBehavior(this.isTitleShown ? HitTestMode.None : HitTestMode.Default)
          .animation({ duration: 250, curve: Curve.EaseInOut })

        // B 层:滚动后的昵称 + 状态表情(棒棒糖),与身份卡一致。
        Row() {
          Text(this.getDisplayName())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (this.getStatusEmojiUrl().length > 0) {
            Image(this.getStatusEmojiUrl())
              .width(17)
              .height(17)
              .objectFit(ImageFit.Contain)
              .draggable(false)
              .margin({ left: 5 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .opacity(this.isTitleShown ? 1 : 0)
        .translate({ y: this.isTitleShown ? 0 : 8 })
        .hitTestBehavior(this.isTitleShown ? HitTestMode.Default : HitTestMode.None)
        .animation({ duration: 250, curve: Curve.EaseInOut })
      }
      .layoutWeight(1)
      .margin({ left: 8 })
      .alignContent(Alignment.Start)

      // 逃生口:原生页没覆盖的东西(作品集、关注列表等)去网页版看。
      // 图标用 arrow_right_up_and_square 而非 ellipsis——后者在 sysResource.js 里不存在(只有
      // ellipsis_bubble/ellipsis_circle 等变体),且「在外部打开」的语义本就比三个点准确。
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.arrow_right_up_and_square'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.openUserWebPage();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 8 })
  }

  // ==================== 卡片 1:身份 + 操作 + 统计 ====================

  @Builder
  private IdentityCard() {
    Column() {
      // 头像行:头像 + 名字/昵称列 + 右侧私信小按钮(与头像垂直居中平齐)。
      Row() {
        // 用 if 分支强制重建 UserAvatar:它的 user 是普通属性,构造后不随父更新
        // (无 @Prop/@Watch)。种子 user 只有静态 avatarTemplate、无动图无 flair;
        // detail 回来后分支翻转 → 销毁旧头像、以完整 user 重新挂载 → 动图与 flair 才出现。
        if (this.profileDetail !== undefined) {
          UserAvatar({ user: toAvatarUser(this.profileDetail), avatarSize: 64 })
        } else {
          UserAvatar({ user: this.getAvatarUser(), avatarSize: 64 })
        }
        Column() {
          // 昵称行:名字 + 状态表情 + 精选徽章图标(与帖子详情楼层作者头一致)。
          Row() {
            Text(this.getDisplayName())
              .fontSize(21)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)

            // 状态表情(user.status.emoji):与帖子详情同源,保留。
            // 昵称后的徽章图标不显示——个人页接口只给「精选徽章」,与帖子头的
            // show_in_post_header 徽章是两套数据,凑不到一致,索性不做(见对话记录)。
            if (this.getStatusEmojiUrl().length > 0) {
              Image(this.getStatusEmojiUrl())
                .width(18)
                .height(18)
                .objectFit(ImageFit.Contain)
                .draggable(false)
                .margin({ left: 6 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // @username + 称号(命中全息名单用闪动渐变,否则灰字),与帖子详情一致。
          Row() {
            Text(`@${this.username}`)
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .flexShrink(0)
            if (this.getUserTitle().length > 0) {
              if (this.isHolographicTitle()) {
                HolographicText({ text: this.getUserTitle(), fontSize: 13 })
                  .margin({ left: 6 })
              } else {
                Text(this.getUserTitle())
                  .fontSize(13)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ left: 6 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .flexShrink(1)
              }
            }
          }
          .width('100%')
          .margin({ top: 3 })
          .alignItems(VerticalAlign.Center)

          // 信任等级单独一行(他人页只是标签,不可点)。
          if (this.getTrustLabel().length > 0) {
            Text(this.getTrustLabel())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius(4)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .margin({ top: 6 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14, right: 10 })

        // 私信小按钮:与头像垂直居中。图标 + 文字胶囊,右对齐。
        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Row() {
            FaIconView({ icon: this.faIcon('envelope'), iconSize: 13, color: Color.White })
            Text('私信')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .margin({ left: 5 })
          }
        }
        .height(32)
        .backgroundColor($r('app.color.ld_accent'))
        .padding({ left: 14, right: 14 })
        .onClick(() => {
          this.openPrivateMessage();
        })
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: CARD_PADDING, bottom: 6 })
      .alignItems(VerticalAlign.Center)

      if (this.getBio().length > 0) {
        Text(this.getBio())
          .fontSize(13.5)
          .fontColor($r('app.color.text_body'))
          .lineHeight(20)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 2, bottom: 6 })
      }

      // meta 行固定高度:资料回来前后卡片不跳动。
      Text(this.getUserMetaLine())
        .fontSize(12)
        .fontColor($r('app.color.text_faint'))
        .width('100%')
        .height(USER_META_HEIGHT)
        .padding({ left: CARD_PADDING, right: CARD_PADDING })

      // 操作区:认可 + 关注同一行(私信已移到头像右侧)。按插件字段条件显示。
      this.ActionButtons()

      this.HairlineInset()

      // 统计区固定高度:加载占位与数据网格同高。
      if (this.summary) {
        this.StatsGrid(this.summary.stats)
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
        // 唯一可点的统计格:被采纳的答案是能力硬证据,也是四个插件页里唯一值得做的。
        // 其余七格只是数字,不做入口——否则每格都像按钮。
        if (this.getSolvedCount() > 0) {
          this.SolvedCell(this.formatCount(this.getSolvedCount()))
        } else {
          this.StatCell(stats.solvedCount !== undefined ? this.formatCount(stats.solvedCount) : '—', '解决方案')
        }
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
  private SolvedCell(value: string) {
    Column() {
      Row() {
        Text(value)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ld_success'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(11)
          .fontColor([$r('app.color.ld_success')])
          .margin({ left: 1 })
      }
      .alignItems(VerticalAlign.Center)
      Text('解决方案')
        .fontSize(11)
        .fontColor($r('app.color.text_faint'))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .onClick(() => {
      this.onOpenSolved(this.username, this.getSolvedCount());
    })
  }

  // ==================== 卡片 2:内容(分段) ====================

  @Builder
  private ContentCard() {
    Column() {
      Row() {
        this.SegmentTab('热门话题', SEGMENT_TOP_TOPICS)
        this.SegmentTab('热门回复', SEGMENT_TOP_REPLIES)
        this.SegmentTab('最近', SEGMENT_RECENT)
        Blank()
        // 与 tab 文字对齐:tab 列是「文字 + 下方 7px(margin5+线2)下划线」,文字被顶到列上半。
        // 给「全部」补同样 7px 下内边距,让它的盒子高度与 tab 列相等,Center 下两者文字(都在盒顶)才齐平。
        // 左右/下内边距同时把点击热区做大(原先只有文字那点大小,太难点)。
        Text('全部 ›')
          .fontSize(13)
          .fontColor($r('app.color.ld_accent'))
          .padding({ left: 14, right: 2, bottom: 7 })
          .onClick(() => {
            this.openSegmentAll();
          })
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 0 })
      .alignItems(VerticalAlign.Center)

      this.HairlineInset()
      this.SegmentList()
    }
    .cardStyle()
  }

  @Builder
  private SegmentTab(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(15)
        .fontWeight(this.selectedSegment === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.selectedSegment === index ? $r('app.color.text_primary') : $r('app.color.text_faint'))
      // 选中下划线:未选中时同色透明占位,保证三个 tab 基线一致。
      Divider()
        .strokeWidth(2)
        .color(this.selectedSegment === index ? $r('app.color.ld_accent') : Color.Transparent)
        .width(label.length * 15)
        .margin({ top: 5 })
    }
    .margin({ right: 18 })
    .onClick(() => {
      this.selectedSegment = index;
    })
  }

  // 无参 @Builder:分段内容随 @State selectedSegment 重绘。
  // 不做成按值传参的 Builder——那样切分段时内容不跟着换。
  @Builder
  private SegmentList() {
    Column() {
      if (this.selectedSegment === SEGMENT_TOP_TOPICS) {
        if (this.getTopTopics().length > 0) {
          ForEach(this.getTopTopics(), (item: UserTopTopic, index: number) => {
            Column() {
              if (index > 0) {
                this.HairlineInset()
              }
              this.TopTopicRow(item)
            }
            .width('100%')
          }, (item: UserTopTopic) => `topic_${item.topicId}`)
        } else if (this.summary !== undefined) {
          // 直接内联 if 读 this.summary,不经带参 @Builder——值参捕获初值不随 @State 重绘,
          // 会卡在「正在加载」直到手动切分段重建子树(用户反馈的 BUG)。
          this.EmptyHint('还没有发过话题')
        } else {
          this.EmptyHint('正在加载')
        }
      } else if (this.selectedSegment === SEGMENT_TOP_REPLIES) {
        if (this.getTopReplies().length > 0) {
          ForEach(this.getTopReplies(), (item: UserTopReply, index: number) => {
            Column() {
              if (index > 0) {
                this.HairlineInset()
              }
              this.TopReplyRow(item)
            }
            .width('100%')
          }, (item: UserTopReply) => `reply_${item.topicId}_${item.postNumber}`)
        } else if (this.summary !== undefined) {
          this.EmptyHint('还没有回复过')
        } else {
          this.EmptyHint('正在加载')
        }
      } else {
        if (this.recentActivity.length > 0) {
          ForEach(this.recentActivity, (item: UserActivityItem, index: number) => {
            Column() {
              if (index > 0) {
                this.HairlineInset()
              }
              this.ActivityRow(item)
            }
            .width('100%')
          }, (item: UserActivityItem, index: number) => `act_${item.topicId}_${item.postNumber ?? 0}_${index}`)
        } else {
          this.EmptyHint('最近没有动态')
        }
      }
    }
    .width('100%')
  }

  // 点赞数:实心 heart(与帖子详情同款 FA 图标 + 红)+ 数字。count 是静态数据非 @State,值参安全。
  @Builder
  private LikeBadge(count: number) {
    Row() {
      FaIconView({ icon: this.faIcon('heart'), iconSize: 12, color: LIKE_HEART_RED })
        .margin({ right: 3 })
      Text(this.formatCount(count))
        .fontSize(12)
        .fontColor($r('app.color.text_faint'))
    }
    .alignItems(VerticalAlign.Center)
    .margin({ left: 8 })
  }

  @Builder
  private TopTopicRow(item: UserTopTopic) {
    Column() {
      Text(item.title)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row() {
        if (this.getCategoryFor(item.categoryId)) {
          TopicMetadataBadges({
            category: this.getCategoryFor(item.categoryId),
            parentCategory: this.getParentCategoryFor(item.categoryId),
            tags: []
          })
            .layoutWeight(1)
        } else {
          Blank()
        }
        if (item.likeCount > 0) {
          this.LikeBadge(item.likeCount)
        }
        Text(RelativeTime.fromNow(item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 5 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpenTopic(item.topicId, item.title);
    })
  }

  @Builder
  private TopReplyRow(item: UserTopReply) {
    Column() {
      Row() {
        FaIconView({
          icon: this.faIcon('reply'),
          iconSize: 13,
          color: $r('app.color.text_faint')
        })
          .margin({ top: 3 })
        Text(item.topicTitle)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 6 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        if (this.getCategoryFor(item.categoryId)) {
          TopicMetadataBadges({
            category: this.getCategoryFor(item.categoryId),
            parentCategory: this.getParentCategoryFor(item.categoryId),
            tags: []
          })
            .layoutWeight(1)
        } else {
          Blank()
        }
        if (item.likeCount > 0) {
          this.LikeBadge(item.likeCount)
        }
        Text(RelativeTime.fromNow(item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 5 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      // 热门回复指向具体楼层,不是话题首楼。
      this.onOpenTopic(item.topicId, item.topicTitle, item.postNumber);
    })
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
        if (this.hasActivityBadges(item)) {
          TopicMetadataBadges({
            category: this.getCategoryFor(item.categoryId),
            parentCategory: this.getParentCategoryFor(item.categoryId),
            tags: item.tags
          })
            .layoutWeight(1)
        } else {
          Blank()
        }
        Text(RelativeTime.fromNow(item.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.text_faint'))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 5 })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 12, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpenTopic(item.topicId, item.title, item.postNumber);
    })
  }

  // ==================== 卡片 3:互动圈 ====================

  // Discourse 最有辨识度的部分:回答「这人跟谁混」。
  // 官网用三张各占半屏的长列表,手机上压成三行头像——一眼扫完三种关系。
  @Builder
  private CircleCard() {
    if (this.hasInteractions()) {
      Column() {
        Row() {
          Text('互动圈')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 10 })

        this.CircleRow('常回复', this.getMostRepliedTo())
        this.CircleRow('赞过', this.getMostLiked())
        this.CircleRow('被赞自', this.getMostLikedBy())
      }
      .cardStyle()
    }
  }

  @Builder
  private CircleRow(label: string, items: UserInteraction[]) {
    if (items.length > 0) {
      Row() {
        Text(label)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width(52)
        Row() {
          ForEach(items, (item: UserInteraction) => {
            // 次数挂头像右下角;顺序本身已表达强弱(服务端按次数降序)。
            Stack({ alignContent: Alignment.BottomEnd }) {
              UserAvatar({ user: item.user, avatarSize: 30 })
              if (item.count > 1) {
                Text(`${item.count}`)
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.surface_card'))
                  .borderRadius(8)
                  .borderWidth(0.5)
                  .borderColor($r('app.color.border'))
                  .padding({ left: 3, right: 3 })
                  .constraintSize({ minWidth: 15 })
                  .height(15)
                  .textAlign(TextAlign.Center)
                  .offset({ x: 3, y: 3 })
              }
            }
            .margin({ right: 8 })
            .onClick(() => {
              this.openUser(item.user);
            })
          }, (item: UserInteraction) => `${label}_${item.user.id}_${item.user.username}`)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
    }
  }

  // ==================== 卡片 4:徽章 ====================

  @Builder
  private BadgesCard() {
    Column() {
      this.SectionHead(this.getBadgeHeadLabel(), '全部 ›', () => {
        this.onOpenBadges(this.username, this.profileDetail?.badgeCount ?? 0);
      })
      if (this.getTopBadges().length > 0) {
        // 摘要接口最多返回几枚,固定 3 列网格等分展示,不做横滑。与「我的」页一致。
        Column() {
          ForEach(this.getBadgeRows(), (row: UserBadgeItem[], rowIndex: number) => {
            Row({ space: 8 }) {
              ForEach(row, (badge: UserBadgeItem) => {
                BadgeTile(badge, (tapped: UserBadgeItem) => {})
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
      } else if (this.summary !== undefined) {
        this.EmptyHint('暂无徽章')
      } else {
        this.EmptyHint('正在加载')
      }
    }
    .cardStyle()
  }

  // ==================== 通用 ====================

  @Builder
  private SectionHead(title: string, more: string, onMore: () => void) {
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
          onMore();
        })
    }
    .width('100%')
    .padding({ left: CARD_PADDING, right: CARD_PADDING, top: 14, bottom: 4 })
  }

  @Builder
  private HairlineInset() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.border'))
      .margin({ left: CARD_PADDING, right: CARD_PADDING })
  }

  @Builder
  private EmptyHint(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor($r('app.color.text_faint'))
      .width('100%')
      .padding({ left: CARD_PADDING, top: 14, bottom: CARD_PADDING })
  }

  // ==================== 数据加载 ====================

  // 资料/摘要/活动/分类并行加载。完成时校验用户未变(loadedUsername),
  // 避免互动圈递归跳转时旧响应污染新页面。
  // stale-while-revalidate:缓存已按 username 分键,先秒出上次数据,请求回来再原地更新。
  private loadProfileData(): void {
    if (this.username.length === 0 || this.loadedUsername === this.username) {
      return;
    }
    this.loadedUsername = this.username;

    const cachedDetail: UserProfileDetail | undefined = UserProfileCache.getDetail(this.username);
    const cachedSummary: UserSummary | undefined = UserProfileCache.getSummary(this.username);
    const cachedActivity: UserActivityItem[] | undefined = UserProfileCache.getActivity(this.username);
    this.profileDetail = cachedDetail;
    this.summary = cachedSummary;
    this.recentActivity = cachedActivity ? cachedActivity : [];
    this.syncRelationState(cachedDetail);

    // 服务不在字段初始化器里 new:那时父注入的 bridge 还是空壳默认值(惰性注入)。
    const service: UserProfileService = new UserProfileService(this.bridge);
    this.relationService = new UserRelationService(this.bridge);
    this.loadDetail(service, this.username);
    this.loadSummary(service, this.username);
    this.loadActivity(service, this.username);
    this.loadCategories();
  }

  private async loadDetail(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserProfileDetail> = await service.getProfileDetail(username);
    if (this.loadedUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.profileDetail = result.data;
      this.syncRelationState(result.data);
      UserProfileCache.setDetail(username, result.data);
      Log.i(`${LOG_TAG} detail loaded user=${username} trustLevel=${result.data.trustLevel ?? -1} ` +
        `canFollow=${result.data.canFollow ?? false} isFollowed=${result.data.isFollowed ?? false}`);
    } else {
      Log.i(`${LOG_TAG} detail load failed user=${username} status=${result.statusCode}`);
    }
  }

  // 关注/认可态从 detail 落到独立 @State:细粒度翻转不能直接改整体替换的 detail 对象。
  private syncRelationState(detail?: UserProfileDetail): void {
    this.isFollowing = detail?.isFollowed === true;
    this.endorsedCount = detail?.endorsedCategoryIds ? detail.endorsedCategoryIds.length : 0;
  }

  private async loadSummary(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserSummary> = await service.getSummary(username);
    if (this.loadedUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.summary = result.data;
      UserProfileCache.setSummary(username, result.data);
      Log.i(`${LOG_TAG} summary loaded user=${username} topics=${result.data.topTopics.length} ` +
        `replies=${result.data.topReplies.length} circle=${result.data.mostRepliedToUsers.length}`);
    } else {
      Log.i(`${LOG_TAG} summary load failed user=${username} status=${result.statusCode}`);
    }
  }

  private async loadActivity(service: UserProfileService, username: string): Promise<void> {
    const result: NetworkResult<UserActivityItem[]> = await service.getRecentActivity(username);
    if (this.loadedUsername !== username) {
      return;
    }
    if (result.success && result.data) {
      this.recentActivity = result.data;
      UserProfileCache.setActivity(username, result.data);
    } else {
      Log.i(`${LOG_TAG} recent activity load failed user=${username} status=${result.statusCode}`);
    }
  }

  private async loadCategories(): Promise<void> {
    const loaded: TopicCategory[] | null = await this.categoryIndex.loadIfNeeded(
      this.bridge, this.isArkWebReady, this.categories.length > 0, LOG_TAG);
    if (loaded) {
      this.categories = loaded;
    }
  }

  private handleArkWebReadyChanged(): void {
    if (this.isArkWebReady) {
      this.loadProfileData();
    }
  }

  // ==================== 事件 ====================

  private updateTitleVisibility(): void {
    const shown: boolean = this.scroller.currentOffset().yOffset > TITLE_REVEAL_OFFSET;
    // 仅在跨阈值时写 @State,避免每帧重绘。
    if (shown !== this.isTitleShown) {
      this.isTitleShown = shown;
    }
  }

  private openSegmentAll(): void {
    if (this.selectedSegment === SEGMENT_TOP_TOPICS) {
      this.onOpenActivity(this.username, '4', `${this.getDisplayName()} 的话题`);
      return;
    }
    if (this.selectedSegment === SEGMENT_TOP_REPLIES) {
      this.onOpenActivity(this.username, '5', `${this.getDisplayName()} 的回复`);
      return;
    }
    this.onOpenActivity(this.username, '4,5', `${this.getDisplayName()} 的动态`);
  }

  private openUser(user: User): void {
    if (user.username.length === 0 || user.username === this.username) {
      return;
    }
    this.onOpenUser(user.username, user.displayName ? user.displayName : '',
      user.avatarTemplate ? user.avatarTemplate : '', user.id);
  }

  private openPrivateMessage(): void {
    this.onOpenWeb(
      `${AppConstants.BASE_URL}/new-message?username=${encodeURIComponent(this.username)}`,
      `私信 ${this.getDisplayName()}`);
  }

  private openUserWebPage(): void {
    this.onOpenWeb(`${AppConstants.BASE_URL}/u/${encodeURIComponent(this.username)}`, this.getDisplayName());
  }

  // ==================== 关注 ====================

  // 点按钮:未关注直接关注;已关注先弹确认框,避免误触取消关注。
  private toggleFollow(): void {
    if (this.followPending || !this.relationService) {
      return;
    }
    if (this.isFollowing) {
      this.confirmUnfollow();
    } else {
      this.performFollow(true);
    }
  }

  // 取消关注二次确认。「取消关注」用 ld_danger 警示色;系统对话框自带明暗适配。
  private confirmUnfollow(): void {
    this.getUIContext().showAlertDialog({
      title: '取消关注',
      message: `确定不再关注 ${this.getDisplayName()} 吗？`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '再想想',
        action: () => {
        }
      },
      secondaryButton: {
        value: '取消关注',
        fontColor: $r('app.color.ld_danger'),
        action: () => {
          this.performFollow(false);
        }
      }
    });
  }

  // 保守更新:请求期间只转 loading、文字保持不变;服务端确认成功后才翻状态。
  // followPending 兼作在途锁(防抖):请求飞行中再点直接忽略,不会重复提交。
  private async performFollow(target: boolean): Promise<void> {
    if (this.followPending || !this.relationService) {
      return;
    }
    this.followPending = true;

    const result: NetworkResult<boolean> = target
      ? await this.relationService.followUser(this.username)
      : await this.relationService.unfollowUser(this.username);
    this.followPending = false;

    if (!result.success) {
      // 没做乐观翻转,失败无需回滚,只提示。
      this.showToast(result.error?.message ? result.error.message : (target ? '关注失败' : '取消关注失败'));
      Log.i(`${LOG_TAG} follow toggle failed user=${this.username} target=${target} status=${result.statusCode}`);
      return;
    }
    this.isFollowing = target;
    this.showToast(target ? '已关注' : '已取消关注');
  }

  // ==================== 认可 ====================

  private openEndorseSheet(): void {
    this.showEndorseSheet = true;
    this.loadEndorsableCategories();
  }

  private async loadEndorsableCategories(): Promise<void> {
    if (!this.relationService || this.endorseLoading) {
      return;
    }
    this.endorseLoading = true;
    // 编辑态:预选已认可的分类,让弹窗打开就反映当前状态。
    this.endorseSelectedIds = this.profileDetail?.endorsedCategoryIds
      ? this.profileDetail.endorsedCategoryIds.slice()
      : [];
    const result: NetworkResult<EndorsableCategoriesResult> =
      await this.relationService.getEndorsableCategories(this.username);
    this.endorseLoading = false;
    if (!result.success || result.data === undefined) {
      this.endorsableCategories = [];
      this.remainingEndorsements = 0;
      Log.i(`${LOG_TAG} endorsable categories load failed user=${this.username} status=${result.statusCode}`);
      return;
    }
    this.endorsableCategories = result.data.categories;
    this.remainingEndorsements = result.data.remainingEndorsements;
  }

  private toggleEndorseSelection(categoryId: number, checked: boolean): void {
    const index: number = this.endorseSelectedIds.indexOf(categoryId);
    if (checked && index < 0) {
      this.endorseSelectedIds = this.endorseSelectedIds.concat([categoryId]);
    } else if (!checked && index >= 0) {
      this.endorseSelectedIds = this.endorseSelectedIds.filter((id: number) => id !== categoryId);
    }
  }

  private async submitEndorse(): Promise<void> {
    if (this.endorseSubmitting || !this.relationService || this.endorseSelectedIds.length === 0) {
      return;
    }
    this.endorseSubmitting = true;
    const selected: number[] = this.endorseSelectedIds.slice();
    const result: NetworkResult<boolean> =
      await this.relationService.endorseCategories(this.username, selected);
    this.endorseSubmitting = false;
    if (!result.success) {
      this.showToast(result.error?.message ? result.error.message : '认可失败');
      Log.i(`${LOG_TAG} endorse failed user=${this.username} status=${result.statusCode}`);
      return;
    }
    // 认可后更新计数与 detail 缓存里的已认可分类,并关闭弹窗。
    this.endorsedCount = selected.length;
    if (this.profileDetail) {
      this.profileDetail.endorsedCategoryIds = selected;
      UserProfileCache.setDetail(this.username, this.profileDetail);
    }
    this.showEndorseSheet = false;
    this.showToast('已认可');
  }

  private showToast(message: string): void {
    promptToast(this.getUIContext(), message);
  }

  // ==================== 展示辅助 ====================

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }

  // 头像与名字:资料回来前用点击来源透传的种子值,回来后以 detail 为准(它才有 flair)。
  private getAvatarUser(): User {
    if (this.profileDetail) {
      return toAvatarUser(this.profileDetail);
    }
    const seed: User = {
      // 用点击来源透传的 id:决定头像形状(id===1 方形),避免种子先圆后方闪。
      id: this.seedUserId,
      username: this.username
    };
    if (this.seedDisplayName.length > 0) {
      seed.displayName = this.seedDisplayName;
    }
    if (this.seedAvatarTemplate.length > 0) {
      seed.avatarTemplate = this.seedAvatarTemplate;
    }
    return seed;
  }

  private getDisplayName(): string {
    const detailName: string | undefined = this.profileDetail?.displayName;
    if (detailName && detailName.length > 0) {
      return detailName;
    }
    if (this.seedDisplayName.length > 0) {
      return this.seedDisplayName;
    }
    return this.username;
  }

  private getUserTitle(): string {
    const title: string | undefined = this.profileDetail?.title;
    return title && title.length > 0 ? title : '';
  }

  // 认可/关注按钮是否显示:各自插件字段决定。
  private hasEndorse(): boolean {
    return this.profileDetail?.endorsementAvailable === true;
  }

  private hasFollow(): boolean {
    return this.profileDetail?.canFollow === true;
  }

  // 称号是否走全息闪动特效(与帖子详情一致)。
  private isHolographicTitle(): boolean {
    return HOLOGRAPHIC_TITLES.has(this.getUserTitle());
  }

  // 状态表情短名 → CDN url(经 EmojiUrlRegistry,含站点自定义表情)。
  private getStatusEmojiUrl(): string {
    const url: string | undefined = getEmojiUrl(this.profileDetail?.statusEmoji);
    return url ? url : '';
  }

  private getBio(): string {
    const bio: string | undefined = this.profileDetail?.bioExcerpt;
    return bio && bio.length > 0 ? bio : '';
  }

  // 信任等级标签:优先站点头衔(user.title),否则用 TL 默认名。与「我的」页同格式。
  private getTrustLabel(): string {
    const detail: UserProfileDetail | undefined = this.profileDetail;
    if (!detail || detail.trustLevel === undefined) {
      return '';
    }
    const levelName: string = detail.trustLevel >= 0 && detail.trustLevel < TRUST_LEVEL_NAMES.length
      ? TRUST_LEVEL_NAMES[detail.trustLevel]
      : '';
    return levelName.length > 0 ? `TL${detail.trustLevel} ${levelName}` : `TL${detail.trustLevel}`;
  }

  private getUserMetaLine(): string {
    const detail: UserProfileDetail | undefined = this.profileDetail;
    if (!detail) {
      return '';
    }
    const parts: string[] = [];
    const joinDate: string = this.formatJoinDate(detail.createdAt);
    if (joinDate.length > 0) {
      parts.push(`加入于 ${joinDate}`);
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

  private getSolvedCount(): number {
    const count: number | undefined = this.summary?.stats.solvedCount;
    return count !== undefined ? count : 0;
  }

  private getTopTopics(): UserTopTopic[] {
    return this.summary ? this.summary.topTopics : [];
  }

  private getTopReplies(): UserTopReply[] {
    return this.summary ? this.summary.topReplies : [];
  }

  private getMostRepliedTo(): UserInteraction[] {
    return this.summary ? this.summary.mostRepliedToUsers : [];
  }

  private getMostLiked(): UserInteraction[] {
    return this.summary ? this.summary.mostLikedUsers : [];
  }

  private getMostLikedBy(): UserInteraction[] {
    return this.summary ? this.summary.mostLikedByUsers : [];
  }

  private hasInteractions(): boolean {
    return this.getMostRepliedTo().length > 0 || this.getMostLiked().length > 0 || this.getMostLikedBy().length > 0;
  }

  private getTopBadges(): UserBadgeItem[] {
    return this.summary ? this.summary.topBadges : [];
  }

  // 徽章按 3 枚一行分组。
  private getBadgeRows(): UserBadgeItem[][] {
    const badges: UserBadgeItem[] = this.getTopBadges();
    const rows: UserBadgeItem[][] = [];
    for (let index: number = 0; index < badges.length; index += 3) {
      rows.push(badges.slice(index, index + 3));
    }
    return rows;
  }

  // 末行不足 3 枚时需要的占位数量。
  private getBadgeRowFillers(row: UserBadgeItem[]): number[] {
    const fillers: number[] = [];
    for (let index: number = row.length; index < 3; index++) {
      fillers.push(index);
    }
    return fillers;
  }

  private getBadgeHeadLabel(): string {
    const badgeCount: number | undefined = this.profileDetail?.badgeCount;
    return badgeCount !== undefined && badgeCount > 0 ? `徽章 · ${badgeCount}` : '徽章';
  }

  private getCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.find(this.categories, categoryId);
  }

  private getParentCategoryFor(categoryId?: number): TopicCategory | undefined {
    return CategoryIndex.findParent(this.categories, categoryId);
  }

  private hasActivityBadges(item: UserActivityItem): boolean {
    return this.getCategoryFor(item.categoryId) !== undefined || item.tags.length > 0;
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

  // 加入日期:createdAt 形如 2024-01-18T… → 「2024年1月18日」。前导零去掉。
  private formatJoinDate(iso?: string): string {
    if (!iso || iso.length === 0) {
      return '';
    }
    const match: RegExpMatchArray | null = iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!match) {
      return '';
    }
    const year: number = Number(match[1]);
    const month: number = Number(match[2]);
    const day: number = Number(match[3]);
    return `${year}年${month}月${day}日`;
  }
}
