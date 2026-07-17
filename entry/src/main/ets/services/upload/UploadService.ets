import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';

// 一次成功上传的结果:short_url 是写进帖子 raw 的短码(upload://…),url 是真实 CDN 直链(预览用)。
export interface UploadedImage {
  shortUrl: string;
  url: string;
  fileName: string;
  width: number;
  height: number;
}

// /uploads.json 成功响应的关注字段(其余忽略)。short_url 形如 upload://abc.jpeg;url 为真实直链。
interface UploadResponse {
  short_url?: string;
  url?: string;
  original_filename?: string;
  width?: number;
  height?: number;
}

// 压缩上限:最长边超过则等比缩到该值(论坛配图足够,且把注入脚本的 base64 体积压到 host 可承受)。
const MAX_EDGE: number = 1920;
// JPEG 压缩质量(0-100)。70 在清晰度与体积间平衡。
const JPEG_QUALITY: number = 70;

// 图片上传服务:选图 → 压缩(gif 除外) → base64 → 经 host webview multipart 传 /uploads.json。
// 维护 short_url → 真实 url 映射,供编辑器预览把 raw 里的 upload:// 短码换成可加载直链
// (CookedHtmlParser 对 upload:// 原样返回、无法加载,故预览必须替换)。
export class UploadService {
  private bridge: JsonNetworkClient;
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  // short_url → 真实 url。上传成功即登记,预览渲染时据此替换短码。
  private shortUrlToRealUrl: Map<string, string> = new Map();

  constructor(bridge: JsonNetworkClient) {
    this.bridge = bridge;
  }

  // 拉起系统相册选图,返回选中的 uri 列表(最多 maxCount 张)。取消或失败返回空数组。
  async pickImages(maxCount: number): Promise<string[]> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = Math.max(1, maxCount);
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      return result.photoUris ? result.photoUris : [];
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Upload] pickImages failed code=${err.code} msg=${err.message}`);
      return [];
    }
  }

  // 上传单张图片。读文件 → (gif 原样 / 其余解码压缩为 jpeg) → base64 → 经 bridge 传 /uploads.json。
  // 成功返回 UploadedImage 并登记短码映射;失败返回 undefined。
  async uploadUri(uri: string): Promise<UploadedImage | undefined> {
    let encoded: EncodedImage | undefined;
    try {
      encoded = await this.encodeForUpload(uri);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.i(`[ArkDO][Upload] encode failed code=${err.code} msg=${err.message}`);
      return undefined;
    }
    if (!encoded) {
      return undefined;
    }

    const referrer: string = `${AppConstants.BASE_URL}/`;
    const response: NetworkResult<string> = await this.bridge.uploadImage(
      encoded.base64, encoded.fileName, encoded.mimeType, { notifyChallenge: true, referrer: referrer });
    if (!response.success || response.data === undefined) {
      Log.i(`[ArkDO][Upload] upload failed status=${response.statusCode}`);
      return undefined;
    }

    try {
      const parsed: UploadResponse = JSON.parse(response.data) as UploadResponse;
      const shortUrl: string = parsed.short_url ? parsed.short_url : '';
      const realUrl: string = parsed.url ? parsed.url : '';
      if (shortUrl.length === 0) {
        Log.i('[ArkDO][Upload] response missing short_url');
        return undefined;
      }
      if (realUrl.length > 0) {
        this.shortUrlToRealUrl.set(shortUrl, realUrl);
      }
      return {
        shortUrl: shortUrl,
        url: realUrl,
        fileName: parsed.original_filename ? parsed.original_filename : encoded.fileName,
        width: typeof parsed.width === 'number' ? parsed.width : encoded.width,
        height: typeof parsed.height === 'number' ? parsed.height : encoded.height
      };
    } catch (error) {
      Log.i('[ArkDO][Upload] response not valid JSON');
      return undefined;
    }
  }

  // 取某短码对应的真实直链(预览替换用);未登记返回 undefined。
  getRealUrl(shortUrl: string): string | undefined {
    return this.shortUrlToRealUrl.get(shortUrl);
  }

  // 预览用:把 markdown-it 编译出的 HTML 里 <img src="upload://…"> 的短码换成真实直链。
  // CookedHtmlParser 对 upload:// 原样返回、无法加载,故预览前必须替换成本次上传拿到的直链。
  resolvePreviewHtml(html: string): string {
    let result: string = html;
    this.shortUrlToRealUrl.forEach((realUrl: string, shortUrl: string) => {
      result = result.split(shortUrl).join(realUrl);
    });
    return result;
  }

  // 生成插入正文的图片 markdown:![文件名|宽x高](upload://…)。宽高缺失则省略尺寸段。
  static buildImageMarkdown(img: UploadedImage): string {
    const name: string = img.fileName.length > 0 ? img.fileName : 'image';
    if (img.width > 0 && img.height > 0) {
      return `![${name}|${img.width}x${img.height}](${img.shortUrl})`;
    }
    return `![${name}](${img.shortUrl})`;
  }

  // 把 uri 编码成可上传的字节:gif 保留原文件(压缩会丢动画),其余解码后等比缩放并压成 jpeg。
  private async encodeForUpload(uri: string): Promise<EncodedImage | undefined> {
    const lower: string = uri.toLowerCase();
    if (lower.endsWith('.gif')) {
      return this.encodeRaw(uri, 'image.gif', 'image/gif');
    }

    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let imageSource: image.ImageSource | undefined;
    let pixelMap: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    try {
      imageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const srcW: number = info.size.width;
      const srcH: number = info.size.height;
      const target: TargetSize = UploadService.fitWithin(srcW, srcH, MAX_EDGE);
      const decodeOptions: image.DecodingOptions = {
        desiredSize: { width: target.width, height: target.height }
      };
      pixelMap = await imageSource.createPixelMap(decodeOptions);
      packer = image.createImagePacker();
      const packOptions: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY };
      const arrayBuffer: ArrayBuffer = await packer.packing(pixelMap, packOptions);
      const base64: string = this.base64Helper.encodeToStringSync(new Uint8Array(arrayBuffer));
      return { base64: base64, fileName: 'image.jpg', mimeType: 'image/jpeg', width: target.width, height: target.height };
    } finally {
      if (pixelMap) {
        pixelMap.release();
      }
      if (packer) {
        packer.release();
      }
      if (imageSource) {
        imageSource.release();
      }
      fs.closeSync(file);
    }
  }

  // 原样读取文件字节并 base64(gif 等不宜重编码的格式)。宽高交给服务端(返 0 时省略尺寸段)。
  private encodeRaw(uri: string, fileName: string, mimeType: string): EncodedImage {
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = fs.statSync(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      const base64: string = this.base64Helper.encodeToStringSync(new Uint8Array(buffer));
      return { base64: base64, fileName: fileName, mimeType: mimeType, width: 0, height: 0 };
    } finally {
      fs.closeSync(file);
    }
  }

  // 把 (w,h) 等比缩放到最长边不超过 maxEdge;本就不超则原样返回。
  private static fitWithin(width: number, height: number, maxEdge: number): TargetSize {
    const longest: number = Math.max(width, height);
    if (longest <= maxEdge || longest === 0) {
      return { width: width, height: height };
    }
    const ratio: number = maxEdge / longest;
    return {
      width: Math.max(1, Math.round(width * ratio)),
      height: Math.max(1, Math.round(height * ratio))
    };
  }
}

// 编码后待上传的图片字节。
interface EncodedImage {
  base64: string;
  fileName: string;
  mimeType: string;
  width: number;
  height: number;
}

interface TargetSize {
  width: number;
  height: number;
}
