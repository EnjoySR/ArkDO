// 非资源色 token。
//
// 为什么这些颜色不进 resources/base/element/color.json:
// 资源色会随系统深浅色自动翻转,而下面这些**不能翻转**——
//   - ON_DARK_FG 是"盖在深色/彩色表面上的前景",底色本身不随主题变(视频画面、
//     图片预览的黑底、绿色采纳徽章),前景跟着翻就会变成白底白字。
//   - SCRIM_* / SHADOW_* 是黑色不同透明度的遮罩与投影,深色模式下同样要压暗,
//     翻成白色会把遮罩变成高光。
//   - 语义状态色(点赞红/成功绿/品牌蓝)是站点身份的一部分,两种主题下保持同色。
// 项目里对这类色的处理约定见 ThemeManager 的 appIsDark:需要区分深浅时手动切,
// 而不是交给资源系统。
//
// 集中到这里之前,同一个色值散在多个文件里、还起了不同的名字:
//   #EF4444 → TopicPostItem.LIKE_RED  +  UserProfilePage.LIKE_HEART_RED
//   #22C55E → TopicPostItem.COPY_CHECK_COLOR  +  NotificationApi.C_APPROVED  +  LevelProgressPage 两处带透明度的裸值
//   #F5A623 → NotificationBell.BELL_COLOR  +  NotificationApi.C_WATCH
//   #0088CC → 5 处裸值,另有 NotificationListItem 写成缩写 '#08C'(同色不同写法)
// 这类分身一旦要调色就必然漏改。

// 深色/彩色表面上的前景色。视频与音频控件、图片预览、采纳徽章文字等。
// 底色不随主题变,故此色恒为白,不可换成会翻转的资源色。
export const ON_DARK_FG: string = '#FFFFFF';
// 同上,次要一档(85% 白)。同一条彩色条上的附注文字,比主文字弱一档但仍需可读。
export const ON_DARK_FG_DIM: string = '#D9FFFFFF';

// 遮罩:浮层背后压暗底层内容。20% 黑。
export const SCRIM: string = '#33000000';
// 强遮罩:底部弹面板背后,压得更实。40% 黑。
export const SCRIM_STRONG: string = '#66000000';
// 卡片/浮层投影。15% 黑。
export const SHADOW_CARD: string = '#26000000';
// 轻投影。13% 黑。
export const SHADOW_SOFT: string = '#22000000';

// 点赞红。爱心图标与点赞计数。
export const LIKE_RED: string = '#EF4444';
// 成功绿。复制成功打勾、通知里的"已批准"、等级进度的达标态。
export const SUCCESS_GREEN: string = '#22C55E';
// 品牌蓝。回复入口、未读徽标底色。与站点主色一致。
export const BRAND_BLUE: string = '#0088CC';
// 琥珀色。通知铃铛、"关注中"类通知。
export const AMBER: string = '#F5A623';
