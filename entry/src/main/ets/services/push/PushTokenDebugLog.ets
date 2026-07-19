import BuildProfile from 'BuildProfile';

// 日志会落盘,且设置页有「导出日志」入口——完整 deviceToken 等同于"可向本机投递推送的凭据",
// 一旦随日志外发,任何人都能拿它给这台设备推消息。故只留首尾各 6 位,够排查(比对是否换过 token)
// 又不足以复用。
const PUSH_TOKEN_VISIBLE_PREFIX: number = 6;
const PUSH_TOKEN_VISIBLE_SUFFIX: number = 6;

export function maskPushToken(token: string): string {
  if (token.length <= PUSH_TOKEN_VISIBLE_PREFIX + PUSH_TOKEN_VISIBLE_SUFFIX) {
    // 短到脱敏没意义(异常 token),只报长度,不泄内容。
    return `<len=${token.length}>`;
  }
  const head: string = token.substring(0, PUSH_TOKEN_VISIBLE_PREFIX);
  const tail: string = token.substring(token.length - PUSH_TOKEN_VISIBLE_SUFFIX);
  return `${head}…${tail}(len=${token.length})`;
}

export function buildPushTokenDebugLogLine(logTag: string, token: string, enabled: boolean): string {
  if (!enabled) {
    return '';
  }
  return `${logTag} token=${maskPushToken(token)}`;
}

export function isDebugBuildInfo(buildModeName: string, debug: boolean): boolean {
  return debug || buildModeName === 'debug';
}

export function shouldLogFullPushToken(): boolean {
  return isDebugBuildInfo(BuildProfile.BUILD_MODE_NAME, BuildProfile.DEBUG);
}
