import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 本机日志落盘:钩住 console.info/warn/error,把与 hdc 抓取格式一致的日志行缓冲后异步批量写入
// 应用沙箱,支持大小轮转与合并导出。用于用户脱机跑一天后从设置里导出日志给开发者分析(CF 挑战等)。
const HILOG_DOMAIN: number = 0x0000;
const LOG_DIR_NAME: string = 'app_logs';
const CURRENT_FILE_NAME: string = 'arkdo.log';
const EXPORT_FILE_NAME: string = 'arkdo-log-export.txt';
// 单文件封顶 4MB,归档保留 2 个(current + 2 = 3 份),总占用 ≤12MB。
const MAX_FILE_BYTES: number = 4 * 1024 * 1024;
const MAX_ARCHIVE_FILES: number = 2;
// 攒够 64KB 或每 5 秒刷盘一次:批量写避免高峰期(列表刷新)频繁同步 IO 卡主线程。
const FLUSH_INTERVAL_MS: number = 5000;
const FLUSH_SIZE_THRESHOLD: number = 64 * 1024;
const COPY_BUFFER_BYTES: number = 256 * 1024;
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_ENABLED: string = 'fileLogEnabled';
const PREF_KEY_VERBOSE: string = 'fileLogVerbose';

export class FileLogger {
  private static logDir: string = '';
  private static initialized: boolean = false;
  private static enabled: boolean = true;
  private static verbose: boolean = false;
  private static buffer: string[] = [];
  private static bufferBytes: number = 0;
  private static currentFileBytes: number = 0;
  private static flushTimer: number = -1;

  // 应用启动时调用(EntryAbility.onCreate):建目录、读当前文件大小与偏好开关。
  static init(context: common.Context): void {
    if (FileLogger.initialized) {
      return;
    }
    try {
      FileLogger.logDir = `${context.filesDir}/${LOG_DIR_NAME}`;
      if (!fs.accessSync(FileLogger.logDir)) {
        fs.mkdirSync(FileLogger.logDir);
      }
      const currentPath: string = FileLogger.currentFilePath();
      if (fs.accessSync(currentPath)) {
        FileLogger.currentFileBytes = fs.statSync(currentPath).size;
      }
      FileLogger.loadPreferences(context);
      FileLogger.initialized = true;
      hilog.info(HILOG_DOMAIN, 'FileLogger', 'init ok dir=%{public}s bytes=%{public}d', FileLogger.logDir, FileLogger.currentFileBytes);
    } catch (error) {
      hilog.error(HILOG_DOMAIN, 'FileLogger', 'init failed: %{public}s', JSON.stringify(error));
    }
  }

  static append(level: string, message: string): void {
    if (!FileLogger.enabled || !FileLogger.initialized) {
      return;
    }
    const line: string = `${FileLogger.timestamp()} ${level} ${message}\n`;
    FileLogger.buffer.push(line);
    FileLogger.bufferBytes += line.length;
    if (FileLogger.bufferBytes >= FLUSH_SIZE_THRESHOLD) {
      FileLogger.flush();
    } else {
      FileLogger.ensureFlushTimer();
    }
  }

  // 同步写盘(单线程,写入本身很快;批量后每次数据量可控)。退后台/崩溃/导出前强制调用。
  static flush(): void {
    FileLogger.clearFlushTimer();
    if (!FileLogger.initialized || FileLogger.buffer.length === 0) {
      return;
    }
    const chunk: string = FileLogger.buffer.join('');
    FileLogger.buffer = [];
    FileLogger.bufferBytes = 0;
    try {
      if (FileLogger.currentFileBytes + chunk.length > MAX_FILE_BYTES) {
        FileLogger.rotate();
        FileLogger.currentFileBytes = 0;
      }
      const file: fs.File = fs.openSync(FileLogger.currentFilePath(),
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      const written: number = fs.writeSync(file.fd, chunk);
      fs.closeSync(file);
      FileLogger.currentFileBytes += written;
    } catch (error) {
      hilog.error(HILOG_DOMAIN, 'FileLogger', 'flush failed: %{public}s', JSON.stringify(error));
    }
  }

  // 合并当前 + 归档为单个导出文件(旧→新按时间顺序),返回沙箱路径;失败返回空串。
  static exportToFile(): string {
    FileLogger.flush();
    if (!FileLogger.initialized) {
      return '';
    }
    const exportPath: string = `${FileLogger.logDir}/${EXPORT_FILE_NAME}`;
    try {
      const out: fs.File = fs.openSync(exportPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        for (let index: number = MAX_ARCHIVE_FILES; index >= 1; index--) {
          FileLogger.appendFileTo(out.fd, FileLogger.archivePath(index));
        }
        FileLogger.appendFileTo(out.fd, FileLogger.currentFilePath());
      } finally {
        fs.closeSync(out);
      }
      return exportPath;
    } catch (error) {
      hilog.error(HILOG_DOMAIN, 'FileLogger', 'export failed: %{public}s', JSON.stringify(error));
      return '';
    }
  }

  static clear(): void {
    FileLogger.buffer = [];
    FileLogger.bufferBytes = 0;
    FileLogger.clearFlushTimer();
    if (!FileLogger.initialized) {
      return;
    }
    try {
      FileLogger.unlinkIfExists(FileLogger.currentFilePath());
      for (let index: number = 1; index <= MAX_ARCHIVE_FILES; index++) {
        FileLogger.unlinkIfExists(FileLogger.archivePath(index));
      }
      FileLogger.unlinkIfExists(`${FileLogger.logDir}/${EXPORT_FILE_NAME}`);
      FileLogger.currentFileBytes = 0;
    } catch (error) {
      hilog.error(HILOG_DOMAIN, 'FileLogger', 'clear failed: %{public}s', JSON.stringify(error));
    }
  }

  static getTotalSizeBytes(): number {
    let total: number = FileLogger.bufferBytes;
    if (!FileLogger.initialized) {
      return total;
    }
    try {
      const current: string = FileLogger.currentFilePath();
      if (fs.accessSync(current)) {
        total += fs.statSync(current).size;
      }
      for (let index: number = 1; index <= MAX_ARCHIVE_FILES; index++) {
        const archive: string = FileLogger.archivePath(index);
        if (fs.accessSync(archive)) {
          total += fs.statSync(archive).size;
        }
      }
    } catch (error) {
      hilog.error(HILOG_DOMAIN, 'FileLogger', 'size failed: %{public}s', JSON.stringify(error));
    }
    return total;
  }

  static isEnabled(): boolean {
    return FileLogger.enabled;
  }

  static isVerbose(): boolean {
    return FileLogger.verbose;
  }

  static setEnabled(context: common.Context, value: boolean): void {
    FileLogger.enabled = value;
    FileLogger.persist(context, PREF_KEY_ENABLED, value);
  }

  static setVerbose(context: common.Context, value: boolean): void {
    FileLogger.verbose = value;
    FileLogger.persist(context, PREF_KEY_VERBOSE, value);
  }

  private static loadPreferences(context: common.Context): void {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      FileLogger.enabled = store.getSync(PREF_KEY_ENABLED, true) as boolean;
      FileLogger.verbose = store.getSync(PREF_KEY_VERBOSE, false) as boolean;
    } catch (error) {
      hilog.error(HILOG_DOMAIN, 'FileLogger', 'load prefs failed: %{public}s', JSON.stringify(error));
    }
  }

  private static persist(context: common.Context, key: string, value: boolean): void {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
      store.putSync(key, value);
      store.flush();
    } catch (error) {
      hilog.error(HILOG_DOMAIN, 'FileLogger', 'persist failed: %{public}s', JSON.stringify(error));
    }
  }

  // current → arkdo.1.log → arkdo.2.log;超出的最老一份被丢弃。
  private static rotate(): void {
    try {
      FileLogger.unlinkIfExists(FileLogger.archivePath(MAX_ARCHIVE_FILES));
      for (let index: number = MAX_ARCHIVE_FILES - 1; index >= 1; index--) {
        const from: string = FileLogger.archivePath(index);
        if (fs.accessSync(from)) {
          fs.renameSync(from, FileLogger.archivePath(index + 1));
        }
      }
      const current: string = FileLogger.currentFilePath();
      if (fs.accessSync(current)) {
        fs.renameSync(current, FileLogger.archivePath(1));
      }
    } catch (error) {
      hilog.error(HILOG_DOMAIN, 'FileLogger', 'rotate failed: %{public}s', JSON.stringify(error));
    }
  }

  private static appendFileTo(destFd: number, sourcePath: string): void {
    if (!fs.accessSync(sourcePath)) {
      return;
    }
    const src: fs.File = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
    try {
      const size: number = fs.statSync(src.fd).size;
      const arrayBuffer: ArrayBuffer = new ArrayBuffer(COPY_BUFFER_BYTES);
      let offset: number = 0;
      while (offset < size) {
        const length: number = Math.min(COPY_BUFFER_BYTES, size - offset);
        const readLen: number = fs.readSync(src.fd, arrayBuffer, { offset: offset, length: length });
        if (readLen <= 0) {
          break;
        }
        fs.writeSync(destFd, arrayBuffer.slice(0, readLen));
        offset += readLen;
      }
    } finally {
      fs.closeSync(src);
    }
  }

  private static unlinkIfExists(path: string): void {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  }

  private static currentFilePath(): string {
    return `${FileLogger.logDir}/${CURRENT_FILE_NAME}`;
  }

  private static archivePath(index: number): string {
    return `${FileLogger.logDir}/arkdo.${index}.log`;
  }

  private static ensureFlushTimer(): void {
    if (FileLogger.flushTimer >= 0) {
      return;
    }
    FileLogger.flushTimer = setTimeout(() => {
      FileLogger.flushTimer = -1;
      FileLogger.flush();
    }, FLUSH_INTERVAL_MS);
  }

  private static clearFlushTimer(): void {
    if (FileLogger.flushTimer >= 0) {
      clearTimeout(FileLogger.flushTimer);
      FileLogger.flushTimer = -1;
    }
  }

  // 与 hdc hilog 抓取一致的时间前缀 MM-DD HH:mm:ss.SSS,便于沿用既有分析方法。
  private static timestamp(): string {
    const now: Date = new Date();
    const mm: string = FileLogger.pad(now.getMonth() + 1, 2);
    const dd: string = FileLogger.pad(now.getDate(), 2);
    const hh: string = FileLogger.pad(now.getHours(), 2);
    const mi: string = FileLogger.pad(now.getMinutes(), 2);
    const ss: string = FileLogger.pad(now.getSeconds(), 2);
    const ms: string = FileLogger.pad(now.getMilliseconds(), 3);
    return `${mm}-${dd} ${hh}:${mi}:${ss}.${ms}`;
  }

  private static pad(value: number, width: number): string {
    let text: string = value.toString();
    while (text.length < width) {
      text = `0${text}`;
    }
    return text;
  }
}
