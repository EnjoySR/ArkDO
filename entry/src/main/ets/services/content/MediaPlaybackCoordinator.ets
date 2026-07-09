// 全局「同一时刻只有一个媒体在播」协调器。音频/视频播放器各自注册一个停止回调并拿到唯一 id;
// 某个播放器开始播放时调用 notifyStarted(id),其余所有播放器收到通知即停止并复位 UI。
// 这样在同一帖子里先播 A 再播 B,A 会自动停下。
export type MediaStopListener = () => void;

export class MediaPlaybackCoordinator {
  private static listeners: Map<number, MediaStopListener> = new Map();
  private static nextId: number = 1;
  // 当前活跃(最后一个发起播放的)播放器 id。用于「下载竞态」:先点 A(下载中)再点 B 后,
  // A 下载完时若已不是活跃者(activeId 已是 B),就不该自动开播,避免 A、B 同时响。
  private static activeId: number = 0;

  static register(onStop: MediaStopListener): number {
    const id: number = MediaPlaybackCoordinator.nextId;
    MediaPlaybackCoordinator.nextId++;
    MediaPlaybackCoordinator.listeners.set(id, onStop);
    return id;
  }

  static unregister(id: number): void {
    MediaPlaybackCoordinator.listeners.delete(id);
    if (MediaPlaybackCoordinator.activeId === id) {
      MediaPlaybackCoordinator.activeId = 0;
    }
  }

  // 某播放器(activeId)发起播放:记为活跃者并通知其余所有播放器停止。
  static notifyStarted(activeId: number): void {
    MediaPlaybackCoordinator.activeId = activeId;
    MediaPlaybackCoordinator.listeners.forEach((onStop: MediaStopListener, id: number) => {
      if (id !== activeId) {
        onStop();
      }
    });
  }

  // 该 id 是否仍是当前活跃者(下载完成后据此决定是否自动开播)。
  static isActive(id: number): boolean {
    return MediaPlaybackCoordinator.activeId === id;
  }
}
