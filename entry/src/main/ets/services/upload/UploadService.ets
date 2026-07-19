import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../logging/Log';
import { AppConstants } from '../../common/constants/AppConstants';
import { JsonNetworkClient, NetworkResult } from '../network/NetworkTypes';

// POST /uploads/lookup-urls 的响应项:把 upload:// 短码换成真实 CDN 直链。
interface DiscourseLookupUrlItem {
  short_url?: string;
  url?: string;
  short_path?: string;
}

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

// ── 图片优化参数:对齐 Discourse 官方 composer,免得原生端比网页端更狠地劣化画质。
// 依据 discourse main 分支 frontend/discourse/app/services/media-optimization-worker.js
// 与 frontend/discourse/app/workers/media-optimization/codecs.js。

// 小于此体积的图不重编码,原样上传(官方 composer_media_optimization_image_bytes_optimization_threshold)。
// 小图重编码是画质净赔:省不下几个字节,却白吃一遍有损压缩。
const BYTES_OPTIMIZATION_THRESHOLD: number = 524288;
// 宽度超过此值才缩放。官方只看宽度、不看最长边,故长截图这类竖图能保住原分辨率。
const RESIZE_THRESHOLD: number = 1920;
// 缩放目标宽度,高度按原比例。
const RESIZE_TARGET: number = 1920;
// 编码质量。90 对应官方 image_quality 默认档 high(其 medium 档才是 70)。
const ENCODE_QUALITY: number = 90;
// 嗅探文件头魔数所需字节数(HEIC 的 ftyp box 位置最靠后,12 字节够用)。
const SNIFF_BYTES: number = 16;
// 扫 PNG 块找 acTL 的窗口。acTL 必须出现在首个 IDAT 之前,不会藏在很后面。
const PNG_CHUNK_SCAN_BYTES: number = 4096;

// 图片上传服务:选图 → 按需优化(见 encodeForUpload) → base64 → 经 host webview multipart 传 /uploads.json。
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

  // 上传单张图片。读文件 → 按需优化(见 encodeForUpload) → base64 → 经 bridge 传 /uploads.json。
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

  // 预解析正文里「本会话没上传过」的 upload:// 短码:草稿续写/编辑旧帖时,图片是以前传的,
  // 本地映射表里没有,预览会留着 upload:// 加载不出来。走官方 POST /uploads/lookup-urls 批量换真实直链
  // (返回的 url 与服务端 cook 帖子里的图片同一形式,渲染路径已验证可用;不要自行拼 /uploads/short-url/,
  // 那条会 302 到跨源 CDN 且被 CF 挡,见 MediaSource 的记录)。
  // 结果并进同一张映射表,后续 resolvePreviewHtml 原样受益;已解析过的不再请求。
  async prefetchShortUrls(raw: string): Promise<void> {
    const pending: string[] = [];
    const pattern: RegExp = new RegExp('upload://[A-Za-z0-9]+\\.[A-Za-z0-9]+', 'g');
    let match: RegExpExecArray | null = pattern.exec(raw);
    while (match !== null) {
      const shortUrl: string = match[0];
      if (!this.shortUrlToRealUrl.has(shortUrl) && pending.indexOf(shortUrl) < 0) {
        pending.push(shortUrl);
      }
      match = pattern.exec(raw);
    }
    if (pending.length === 0) {
      return;
    }

    let body: string = '';
    for (let index: number = 0; index < pending.length; index++) {
      body += `${index > 0 ? '&' : ''}short_urls%5B%5D=${encodeURIComponent(pending[index])}`;
    }
    const response: NetworkResult<string> = await this.bridge.postForm('/uploads/lookup-urls', body, {
      notifyChallenge: false,
      referrer: `${AppConstants.BASE_URL}/`
    });
    if (!response.success || response.data === undefined) {
      // 解析失败不阻断预览:该图仍显示不出来,但正文与其余内容照常(发帖时服务端会自行解析短码)。
      return;
    }
    try {
      const items: DiscourseLookupUrlItem[] = JSON.parse(response.data) as DiscourseLookupUrlItem[];
      for (let index: number = 0; index < items.length; index++) {
        const item: DiscourseLookupUrlItem = items[index];
        if (typeof item.short_url === 'string' && typeof item.url === 'string' && item.url.length > 0) {
          this.shortUrlToRealUrl.set(item.short_url, item.url);
        }
      }
    } catch (error) {
      // 响应非 JSON:同上,静默降级。
    }
  }

  // 生成插入正文的图片 markdown:![文件名|宽x高](upload://…)。宽高缺失则省略尺寸段。
  static buildImageMarkdown(img: UploadedImage): string {
    const name: string = img.fileName.length > 0 ? img.fileName : 'image';
    if (img.width > 0 && img.height > 0) {
      return `![${name}|${img.width}x${img.height}](${img.shortUrl})`;
    }
    return `![${name}](${img.shortUrl})`;
  }

  // 把 uri 编码成可上传的字节。策略对齐 Discourse 官方 composer:只有 jpeg/png 且体积过门槛才重编码,
  // 带透明通道编 WebP(不支持则 PNG)以保住 alpha,其余格式(gif/webp/bmp/…)一律原样传。
  // 重编码失败、或结果反而更大,都退回原图字节——原图永远是安全兜底。
  private async encodeForUpload(uri: string): Promise<EncodedImage | undefined> {
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const originalSize: number = fs.statSync(file.fd).size;
      const format: string = this.sniffFormat(file);
      const raw: RawDescriptor = UploadService.rawDescriptor(format);

      // gif/webp/bmp 等不重编码:gif 会丢动画,其余官方端同样不碰。
      if (!raw.optimizable) {
        return this.readRaw(file, originalSize, raw);
      }
      // HEIC 论坛多半不在 authorized_extensions 里,原样传会被拒,故无视体积门槛一律转码。
      const mustConvert: boolean = format === 'heic';
      if (!mustConvert && originalSize < BYTES_OPTIMIZATION_THRESHOLD) {
        return this.readRaw(file, originalSize, raw);
      }
      // APNG 的动画帧会被解码器丢掉只剩首帧,故原样传。
      if (format === 'png' && this.isAnimatedPng(file)) {
        return this.readRaw(file, originalSize, raw);
      }

      let optimized: EncodedImage | undefined;
      try {
        optimized = await this.optimize(file, originalSize);
      } catch (error) {
        const err: BusinessError = error as BusinessError;
        Log.i(`[ArkDO][Upload] optimize failed code=${err.code} msg=${err.message}, keeping original`);
      }
      return optimized ? optimized : this.readRaw(file, originalSize, raw);
    } finally {
      fs.closeSync(file);
    }
  }

  // 解码 → 按需缩放 → 编码。返回 undefined 表示调用方应退回原图(结果没比原图小)。
  private async optimize(file: fs.File, originalSize: number): Promise<EncodedImage | undefined> {
    let imageSource: image.ImageSource | undefined;
    let pixelMap: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    try {
      imageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const target: TargetSize = UploadService.fitWidth(info.size.width, info.size.height);
      const decodeOptions: image.DecodingOptions = {
        desiredSize: { width: target.width, height: target.height }
      };
      pixelMap = await imageSource.createPixelMap(decodeOptions);

      // 有透明像素就不能编 JPEG(透明区会被拍平成黑底)。官方编 WebP;鸿蒙 packer 不支持 WebP 时退 PNG。
      const transparent: boolean = await UploadService.hasTransparency(pixelMap);
      packer = image.createImagePacker();
      const outputFormat: string = transparent ? UploadService.pickAlphaFormat(packer) : 'image/jpeg';
      const packOptions: image.PackingOption = { format: outputFormat, quality: ENCODE_QUALITY };
      const arrayBuffer: ArrayBuffer = await packer.packToData(pixelMap, packOptions);

      // 编完不比原图小就没必要换:退回原图既省体积又零损失(PNG 无损重编码常撞上这条)。
      if (arrayBuffer.byteLength >= originalSize) {
        Log.i(`[ArkDO][Upload] encoded ${arrayBuffer.byteLength}B >= original ${originalSize}B, keeping original`);
        return undefined;
      }

      const base64: string = this.base64Helper.encodeToStringSync(new Uint8Array(arrayBuffer));
      return {
        base64: base64,
        fileName: UploadService.fileNameFor(outputFormat),
        mimeType: outputFormat,
        width: target.width,
        height: target.height
      };
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
    }
  }

  // 是否含透明像素。先用 alphaType 快速排除(照片/相机图都是 OPAQUE),只有可能带 alpha 时才真扫像素:
  // 「有 alpha 通道」不等于「用到了透明」,截图 PNG 常常整幅不透明,扫完才敢放心编 JPEG。
  private static async hasTransparency(pixelMap: image.PixelMap): Promise<boolean> {
    const info: image.ImageInfo = await pixelMap.getImageInfo();
    if (info.alphaType === image.AlphaType.OPAQUE) {
      return false;
    }
    // 仅这两种排布的 alpha 落在每像素第 4 字节;其余格式(RGB_565/RGB_888…)本就无 alpha。
    if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888 &&
      info.pixelFormat !== image.PixelMapFormat.BGRA_8888) {
      return false;
    }

    const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
    await pixelMap.readPixelsToBuffer(buffer);
    const bytes: Uint8Array = new Uint8Array(buffer);
    // 逐行按 stride 走:行尾可能有对齐填充,填充字节是 0,顺序扫会把它误判成透明像素。
    const width: number = info.size.width;
    const height: number = info.size.height;
    const stride: number = info.stride > 0 ? info.stride : width * 4;
    for (let y: number = 0; y < height; y++) {
      const rowStart: number = y * stride;
      for (let x: number = 3; x < width * 4; x += 4) {
        if (bytes[rowStart + x] < 255) {
          return true;
        }
      }
    }
    return false;
  }

  // 选一个能保住 alpha 的输出格式。官方用 WebP;鸿蒙 packer 是否支持 WebP 编码只能运行时问
  // supportedFormats,不支持就退 PNG(无损、体积大些,总好过把透明拍平)。
  private static pickAlphaFormat(packer: image.ImagePacker): string {
    const supported: string[] = packer.supportedFormats;
    return supported && supported.includes('image/webp') ? 'image/webp' : 'image/png';
  }

  private static fileNameFor(mimeType: string): string {
    if (mimeType === 'image/webp') {
      return 'image.webp';
    }
    if (mimeType === 'image/png') {
      return 'image.png';
    }
    return 'image.jpg';
  }

  // 按文件头魔数判断真实格式。不能靠扩展名:相册返回的 uri 未必带真实后缀,
  // 之前 gif 就是靠 .gif 后缀识别的,一旦 uri 不带后缀就会被压成静帧。
  private sniffFormat(file: fs.File): string {
    const header: ArrayBuffer = new ArrayBuffer(SNIFF_BYTES);
    const read: number = fs.readSync(file.fd, header, { offset: 0 });
    const b: Uint8Array = new Uint8Array(header);
    if (read >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
      return 'jpeg';
    }
    if (read >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
      return 'png';
    }
    if (read >= 6 && b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) {
      return 'gif';
    }
    if (read >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) {
      return 'webp';
    }
    if (read >= 2 && b[0] === 0x42 && b[1] === 0x4d) {
      return 'bmp';
    }
    // ISO-BMFF ftyp box:HEIC/HEIF 共用,品牌位不再细分(都走转码)。
    if (read >= 12 && b[4] === 0x66 && b[5] === 0x74 && b[6] === 0x79 && b[7] === 0x70) {
      return 'heic';
    }
    return 'unknown';
  }

  // APNG 在首个 IDAT 前带 acTL 块;解码器只会给首帧,压了就丢动画,故需提前识别并原样传。
  private isAnimatedPng(file: fs.File): boolean {
    const buffer: ArrayBuffer = new ArrayBuffer(PNG_CHUNK_SCAN_BYTES);
    const read: number = fs.readSync(file.fd, buffer, { offset: 0 });
    const view: DataView = new DataView(buffer);
    let offset: number = 8; // 跳过 PNG 签名
    while (offset + 8 <= read) {
      const length: number = view.getUint32(offset);
      const type: string = String.fromCharCode(
        view.getUint8(offset + 4), view.getUint8(offset + 5),
        view.getUint8(offset + 6), view.getUint8(offset + 7));
      if (type === 'acTL') {
        return true;
      }
      if (type === 'IDAT' || type === 'IEND') {
        return false;
      }
      offset += 12 + length; // length(4) + type(4) + data + crc(4)
    }
    return false;
  }

  // 原样读取文件字节并 base64。宽高交给服务端(/uploads.json 响应里带,故这里给 0 即可)。
  private readRaw(file: fs.File, size: number, raw: RawDescriptor): EncodedImage {
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    fs.readSync(file.fd, buffer, { offset: 0 });
    const base64: string = this.base64Helper.encodeToStringSync(new Uint8Array(buffer));
    return { base64: base64, fileName: raw.fileName, mimeType: raw.mimeType, width: 0, height: 0 };
  }

  // 各格式原样上传时的文件名/类型,以及是否该走重编码。
  private static rawDescriptor(format: string): RawDescriptor {
    switch (format) {
      case 'png':
        return { fileName: 'image.png', mimeType: 'image/png', optimizable: true };
      case 'heic':
        return { fileName: 'image.heic', mimeType: 'image/heic', optimizable: true };
      case 'gif':
        return { fileName: 'image.gif', mimeType: 'image/gif', optimizable: false };
      case 'webp':
        return { fileName: 'image.webp', mimeType: 'image/webp', optimizable: false };
      case 'bmp':
        return { fileName: 'image.bmp', mimeType: 'image/bmp', optimizable: false };
      default: // jpeg 及嗅探不出的,按 jpeg 处理(与改造前的行为一致)
        return { fileName: 'image.jpg', mimeType: 'image/jpeg', optimizable: true };
    }
  }

  // 宽度超过阈值则等比缩到目标宽度,否则原样返回。只看宽度是照抄官方:竖向长图因此保住原分辨率。
  private static fitWidth(width: number, height: number): TargetSize {
    if (width <= RESIZE_THRESHOLD || width === 0) {
      return { width: width, height: height };
    }
    return {
      width: RESIZE_TARGET,
      height: Math.max(1, Math.round((height / width) * RESIZE_TARGET))
    };
  }
}

// 某格式原样上传时的描述,以及它是否适合重编码。
interface RawDescriptor {
  fileName: string;
  mimeType: string;
  optimizable: boolean;
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
