import { fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, Want, wantConstant } from '@kit.AbilityKit';

const LOG_TAG: string = '[ArkDO][Download]';

// 常见附件扩展名 → MIME,用于「打开方式」选择器给系统正确的类型提示。
const MIME_BY_EXT: Record<string, string> = {
  'txt': 'text/plain',
  'log': 'text/plain',
  'json': 'application/json',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'rar': 'application/x-rar-compressed',
  '7z': 'application/x-7z-compressed',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'mp4': 'video/mp4',
  'mp3': 'audio/mpeg',
  'apk': 'application/vnd.android.package-archive',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
};

// 附件相关工具:下载由 host webview 的原生下载委托完成(带会话 Cookie、自动跟随重定向);
// 本类只负责下载完成后「用系统打开/分享」以及类型推断,因为文件落在应用沙箱、系统「文件」App 不可见。
export class DownloadService {
  // 下载完成后拉起系统「打开方式/分享」面板。沙箱文件转 file:// uri,并授临时读权限给目标应用。
  static openWithSystem(context: common.UIAbilityContext, filePath: string): void {
    try {
      const uri: string = fileUri.getUriFromPath(filePath);
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: uri,
        type: DownloadService.mimeOf(filePath),
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      context.startAbility(want).catch((err: BusinessError) => {
        console.info(`${LOG_TAG} open ability failed code=${err.code} msg=${err.message}`);
      });
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.info(`${LOG_TAG} open with system failed code=${error.code}`);
    }
  }

  static mimeOf(filePath: string): string {
    const dot: number = filePath.lastIndexOf('.');
    if (dot < 0) {
      return '*/*';
    }
    const ext: string = filePath.substring(dot + 1).toLowerCase();
    const mime: string | undefined = MIME_BY_EXT[ext];
    return mime !== undefined ? mime : '*/*';
  }
}
