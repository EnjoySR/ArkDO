import { Log } from '../logging/Log';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

const LOG_TAG: string = '[ArkDO][SiteIcon]';
const ICON_DIR_NAME: string = 'site_icons';

/**
 * 站点 favicon 的本地缓存。
 *
 * favicon 只能由 webview 引擎交出来,别无他法:
 *  · 原生 Image 走系统 netstack,不吃 DoH(setHttpDns 是 ArkWeb 引擎级设置),对被污染的站点必然加载失败
 *    ——而那正是本功能的目标站点;
 *  · host webview 的 bridge fetch 是跨域请求,favicon.ico 不带 CORS 头,读不到字节(同 LevelProgressPage 的处境)。
 * 故走 Web 组件的 onFaviconReceived 拿 PixelMap(引擎自己的网络栈,吃 DoH 且无 CORS),在此编码 PNG 落盘。
 *
 * 文件按 siteId 约定命名,不进 preferences:避免"文件已删而字段还在"的不同步,读取时查一次文件系统即可。
 */
export class SiteIconStore {
  private static dirOf(context: common.Context): string {
    return `${context.filesDir}/${ICON_DIR_NAME}`;
  }

  /** 站点图标的约定路径(不保证存在)。 */
  static pathOf(context: common.Context, siteId: string): string {
    return `${SiteIconStore.dirOf(context)}/${siteId}.png`;
  }

  /** Image 组件可直接加载的 uri;无图标时返回空串(调用方据此回退默认图标)。 */
  static uriOf(context: common.Context, siteId: string): string {
    try {
      const path: string = SiteIconStore.pathOf(context, siteId);
      return fs.accessSync(path) ? `file://${path}` : '';
    } catch (err) {
      return '';
    }
  }

  /** 存 favicon。同站点重复存即覆盖——站点换了 logo 也能跟上。 */
  static async save(context: common.Context, siteId: string, favicon: image.PixelMap): Promise<void> {
    let packer: image.ImagePacker | undefined = undefined;
    let file: fs.File | undefined = undefined;
    try {
      const dir: string = SiteIconStore.dirOf(context);
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      const path: string = SiteIconStore.pathOf(context, siteId);
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      packer = image.createImagePacker();
      const option: image.PackingOption = { format: 'image/png', quality: 100 };
      await packer.packToFile(favicon, file.fd, option);
      Log.i(`${LOG_TAG} saved icon site=${siteId}`);
    } catch (err) {
      Log.e(`${LOG_TAG} save icon failed site=${siteId}: ${JSON.stringify(err)}`);
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (err) {
          Log.e(`${LOG_TAG} close icon file failed: ${JSON.stringify(err)}`);
        }
      }
      if (packer) {
        try {
          packer.release();
        } catch (err) {
          Log.e(`${LOG_TAG} release packer failed: ${JSON.stringify(err)}`);
        }
      }
    }
  }

  /** 删站点时清掉图标文件,不留孤儿。 */
  static remove(context: common.Context, siteId: string): void {
    try {
      const path: string = SiteIconStore.pathOf(context, siteId);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (err) {
      Log.e(`${LOG_TAG} remove icon failed site=${siteId}: ${JSON.stringify(err)}`);
    }
  }
}
