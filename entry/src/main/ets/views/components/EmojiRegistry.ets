// 长按面板里 10 个可选回应表情的展示顺序(= linux.do 启用的 reactions:reaction_for_like + enabled_reactions)。
export const REACTION_ORDER: string[] = [
  'heart', '+1', 'laughing', 'open_mouth', 'clap',
  'confetti_ball', 'hugs', 'distorted_face', 'tieba_087', 'bili_057'
];

// discourse-reactions 表情短名 → 本地 media 资源。
// linux.do 启用的 10 个回应表情素材见 resources/base/media/emoji_*.png。
// 唯一非直观映射:短名 '+1' → 资源 emoji_plus1(资源名不能含 '+');其余 = 'emoji_' + 短名。
export function getReactionEmoji(name: string): Resource | undefined {
  switch (name) {
    case 'heart': return $r('app.media.emoji_heart');
    case '+1': return $r('app.media.emoji_plus1');
    case 'laughing': return $r('app.media.emoji_laughing');
    case 'open_mouth': return $r('app.media.emoji_open_mouth');
    case 'clap': return $r('app.media.emoji_clap');
    case 'confetti_ball': return $r('app.media.emoji_confetti_ball');
    case 'hugs': return $r('app.media.emoji_hugs');
    case 'distorted_face': return $r('app.media.emoji_distorted_face');
    case 'tieba_087': return $r('app.media.emoji_tieba_087');
    case 'bili_057': return $r('app.media.emoji_bili_057');
    default: return undefined; // 未知表情(站点仅启用这 10 个)→ 跳过渲染
  }
}
