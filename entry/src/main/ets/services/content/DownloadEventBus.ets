const LOG_TAG: string = '[ArkDO][DownloadBus]';

// 一次附件下载的结果(由 host webview 的下载委托回调产生,派发给页面做 toast + 打开)。
export interface DownloadResult {
  success: boolean;
  fileName: string;
  filePath: string;
  message: string;
}

export type DownloadResultListener = (result: DownloadResult) => void;

// host webview 的原生下载委托运行在组件层(ArkWebHost),完成/失败结果经此总线上抛给根页面处理。
export class DownloadEventBus {
  private static listeners: Map<number, DownloadResultListener> = new Map();
  private static nextListenerId: number = 0;

  static subscribe(listener: DownloadResultListener): () => void {
    const listenerId: number = DownloadEventBus.nextListenerId;
    DownloadEventBus.nextListenerId++;
    DownloadEventBus.listeners.set(listenerId, listener);
    return () => {
      DownloadEventBus.listeners.delete(listenerId);
    };
  }

  static notify(result: DownloadResult): void {
    const snapshot: DownloadResultListener[] = [];
    DownloadEventBus.listeners.forEach((listener: DownloadResultListener) => {
      snapshot.push(listener);
    });
    console.info(`${LOG_TAG} notify success=${result.success} file=${result.fileName} listeners=${snapshot.length}`);
    for (let index: number = 0; index < snapshot.length; index++) {
      try {
        snapshot[index](result);
      } catch (error) {
        console.info(`${LOG_TAG} listener failed error=${JSON.stringify(error)}`);
      }
    }
  }
}
