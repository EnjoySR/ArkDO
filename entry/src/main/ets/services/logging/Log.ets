import { FileLogger } from './FileLogger';

// 日志门面:同时输出到 hilog(经 console→hilog,插线调试可见)与本机文件(FileLogger 落盘,可从设置导出)。
// ArkTS 禁止重写 console 方法(arkts-no-method-reassignment),故全项目改用本门面取代直接 console 调用。
export class Log {
  static i(message: string): void {
    console.info(message);
    FileLogger.append('I', message);
  }

  static w(message: string): void {
    console.warn(message);
    FileLogger.append('W', message);
  }

  static e(message: string): void {
    console.error(message);
    FileLogger.append('E', message);
  }
}
