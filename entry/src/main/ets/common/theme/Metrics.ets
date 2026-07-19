// 布局度量 token。
//
// 卡片四件套原先在 6 个页面(Sites / DohSettings / UserProfile / Settings /
// LevelProgress / Profile)各定义一遍,值完全相同。调一次卡片圆角要改 6 处,
// 漏一处就是一张卡片和别的不一样。

// 页面左右外边距。卡片列与屏幕边缘的距离。
export const PAGE_MARGIN: number = 12;
// 卡片圆角。
export const CARD_RADIUS: number = 16;
// 卡片内边距。
export const CARD_PADDING: number = 16;
// 相邻卡片的纵向间距。
export const CARD_GAP: number = 12;

// ---------------------------------------------------------------------------
// 字号 token
//
// 下面这组名字是从全项目 392 处 .fontSize() 的实际取值反推出来的,不是先设计后套用:
//   15(91处) 13(84) 12(49) 14(38) 16(30) 20(20) 18(16) 17(14) 11(13)
// 这九档覆盖了 91% 的调用点,余下的 8/9/10/10.5/13.5/19/21/22/24/26/28/30/32/40/44
// 都是个位数次的一次性用法(大号数字、图标字号等),不进 token——硬塞进标准
// 只会逼出"最接近的那一档",反而改变现有渲染。
//
// 新代码优先用这里的名字;既有调用点未做批量替换,理由见下:
// 把 .fontSize(15) 全局改成 .fontSize(FONT_BODY) 是 392 处的巨大 diff,
// 而每一处的语义角色(正文?次要说明?按钮文字?)只有看上下文才能定,
// grep 定不了。名字取错的 token 比裸数字更有害——它会误导后来者。
// 故此处只立标准,替换随各文件后续改动自然发生。
// ---------------------------------------------------------------------------

// 大标题。页面主标题、身份卡昵称。
export const FONT_TITLE: number = 20;
// 小节标题、二级标题。
export const FONT_SUBTITLE: number = 18;
// 强调正文。帖子列表标题等需要压过正文一档的地方。
export const FONT_BODY_LARGE: number = 17;
// 正文。全项目最常用的一档。
export const FONT_BODY: number = 15;
// 次要正文、按钮文字。
export const FONT_BODY_SMALL: number = 14;
// 说明文字、元信息行。第二常用。
export const FONT_CAPTION: number = 13;
// 辅助文字、角标数字。
export const FONT_FOOTNOTE: number = 12;
// 最小可读字号。徽标计数等。
export const FONT_MICRO: number = 11;
