import { Log } from '../../services/logging/Log';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { MediaPlaybackCoordinator } from '../../services/content/MediaPlaybackCoordinator';

const LOG_TAG: string = '[ArkDO][AudioPlayer]';

// 帖子内联音频播放条。首次点播放时才惰性创建 AVPlayer(一个长帖可能有很多条音频,不提前占资源)。
// 媒体源是 /uploads/short-url/*.xz:服务端 302 到跨源 CDN 且 CF 挡非浏览器客户端,AVPlayer/http/fetch 都拿不到,
// 唯有 host webview(Chromium)下载委托能过盾。故先经 onResolveMedia(→ bridge.downloadMedia)下到沙箱,
// 再用 fdSrc 播本地文件。组件销毁时释放 player 并关闭文件句柄。
@Component
export struct AudioPlayer {
  src: string = '';
  // 把媒体 URL 交给页面(经 bridge 的下载委托)下到沙箱,返回本地文件路径。
  onResolveMedia: (url: string) => Promise<string> = () => Promise.reject(new Error('媒体下载未接入'));
  private player?: media.AVPlayer;
  // 播本地文件用的文件句柄(fdSrc),释放时须一并 close。
  private mediaFile?: fs.File;
  // idle=未开始 / loading=创建+准备中 / playing / paused / error。
  @State private status: string = 'idle';
  @State private currentMs: number = 0;
  @State private durationMs: number = 0;
  // 拖动进度条期间暂停 timeUpdate 回写,避免滑块与播放头打架。
  @State private seeking: boolean = false;
  // 全局播放协调器分配的 id:开始播放时通知其它播放器停止;收到他人开始则自己停。
  private coordinatorId: number = 0;

  aboutToAppear(): void {
    this.coordinatorId = MediaPlaybackCoordinator.register(() => {
      this.stopForCoordinator();
    });
  }

  aboutToDisappear(): void {
    MediaPlaybackCoordinator.unregister(this.coordinatorId);
    this.releasePlayer();
  }

  // 被其它播放器抢占:正在播则暂停(UI 回到「播放」态)。
  private stopForCoordinator(): void {
    if (this.status === 'playing') {
      this.pause();
    }
  }

  build() {
    Row() {
      // 播放/暂停/重试按钮:loading 显示转圈,error 显示感叹号(点一下重试)。
      Stack() {
        if (this.status === 'loading') {
          // 原生转圈,自动动画(静态 SVG 不会自转)。
          LoadingProgress()
            .width(22)
            .height(22)
            .color('#FFFFFF')
        } else if (this.status === 'error') {
          Image($rawfile('fa_icons/circle-exclamation.svg'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .renderMode(ImageRenderMode.Template)
            .fillColor('#FFFFFF')
            .draggable(false)
        } else {
          Image(this.status === 'playing' ? $rawfile('fa_icons/pause.svg') : $rawfile('fa_icons/play.svg'))
            .width(16)
            .height(16)
            .objectFit(ImageFit.Contain)
            .renderMode(ImageRenderMode.Template)
            .fillColor('#FFFFFF')
            .draggable(false)
        }
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.status === 'error' ? '#DC2626' : '#0088CC')
      .onClick(() => {
        this.onPrimaryTap();
      })

      Column() {
        Slider({
          value: this.progressPercent(),
          min: 0,
          max: 100,
          step: 0.1
        })
          .width('100%')
          .trackColor('#E5E7EB')
          .selectedColor('#0088CC')
          .blockColor('#0088CC')
          .trackThickness(3)
          .enabled(this.durationMs > 0)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.onSliderChange(value, mode);
          })

        Row() {
          Text(this.formatTime(this.currentMs))
            .fontSize(11)
            .fontColor('#6B7280')
          Blank()
          Text(this.durationMs > 0 ? this.formatTime(this.durationMs) : '--:--')
            .fontSize(11)
            .fontColor('#6B7280')
        }
        .width('100%')
      }
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 10, right: 14, top: 8, bottom: 8 })
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
  }

  private onPrimaryTap(): void {
    if (this.status === 'loading') {
      return;
    }
    if (this.status === 'error') {
      this.releasePlayer();
      this.status = 'idle';
    }
    if (this.status === 'playing') {
      this.pause();
      return;
    }
    // 本播放器开始/恢复播放前,先让其它播放器停下。
    MediaPlaybackCoordinator.notifyStarted(this.coordinatorId);
    if (this.status === 'paused' && this.player) {
      this.play();
      return;
    }
    this.startPlayback();
  }

  // 先下载到沙箱(http 带 cookie 跟 302),再创建 AVPlayer、用 fdSrc 播本地文件。
  // fdSrc 设置后走 initialized→prepared→playing 状态机。
  private startPlayback(): void {
    if (this.src.length === 0) {
      return;
    }
    this.status = 'loading';
    this.onResolveMedia(this.src).then((path: string) => {
      this.playLocalFile(path);
    }).catch((error: Object) => {
      this.handleError('download failed', error);
    });
  }

  private playLocalFile(path: string): void {
    let file: fs.File;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    } catch (error) {
      this.handleError('open local file failed', error);
      return;
    }
    this.mediaFile = file;
    media.createAVPlayer().then((avPlayer: media.AVPlayer) => {
      this.player = avPlayer;
      this.bindEvents(avPlayer);
      try {
        avPlayer.fdSrc = { fd: file.fd };
      } catch (error) {
        this.handleError('set fdSrc failed', error);
      }
    }).catch((error: BusinessError) => {
      this.handleError('createAVPlayer failed', error);
    });
  }

  private bindEvents(avPlayer: media.AVPlayer): void {
    avPlayer.on('stateChange', (state: string) => {
      switch (state) {
        case 'initialized':
          avPlayer.prepare().catch((error: BusinessError) => {
            this.handleError('prepare failed', error);
          });
          break;
        case 'prepared':
          this.durationMs = avPlayer.duration > 0 ? avPlayer.duration : 0;
          // 下载竞态:加载期间若已被别的播放器抢占,则不自动开播,停在暂停态等用户再点。
          if (MediaPlaybackCoordinator.isActive(this.coordinatorId)) {
            avPlayer.play().catch((error: BusinessError) => {
              this.handleError('play failed', error);
            });
          } else {
            this.status = 'paused';
          }
          break;
        case 'playing':
          this.status = 'playing';
          break;
        case 'paused':
          this.status = 'paused';
          break;
        case 'completed':
          this.status = 'paused';
          this.currentMs = this.durationMs;
          break;
        default:
          break;
      }
    });
    avPlayer.on('timeUpdate', (time: number) => {
      if (!this.seeking) {
        this.currentMs = time;
      }
    });
    avPlayer.on('durationUpdate', (duration: number) => {
      if (duration > 0) {
        this.durationMs = duration;
      }
    });
    avPlayer.on('error', (error: BusinessError) => {
      this.handleError('avplayer error', error);
    });
  }

  private play(): void {
    if (!this.player) {
      return;
    }
    this.player.play().catch((error: BusinessError) => {
      this.handleError('resume play failed', error);
    });
  }

  private pause(): void {
    if (!this.player) {
      return;
    }
    this.player.pause().catch((error: BusinessError) => {
      this.handleError('pause failed', error);
    });
  }

  private onSliderChange(value: number, mode: SliderChangeMode): void {
    if (this.durationMs <= 0) {
      return;
    }
    const target: number = Math.round((value / 100) * this.durationMs);
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.seeking = true;
      this.currentMs = target;
    } else {
      this.seeking = false;
      if (this.player && (this.status === 'playing' || this.status === 'paused')) {
        this.player.seek(target, media.SeekMode.SEEK_CLOSEST);
      }
    }
  }

  private handleError(context: string, error: Object): void {
    const err: BusinessError = error as BusinessError;
    const code: number | undefined = err ? err.code : undefined;
    const message: string | undefined = err ? err.message : undefined;
    Log.e(`${LOG_TAG} ${context}: code=${code} message=${message} str=${String(error)}`);
    this.status = 'error';
  }

  private releasePlayer(): void {
    const avPlayer: media.AVPlayer | undefined = this.player;
    this.player = undefined;
    if (avPlayer) {
      avPlayer.release().catch((error: BusinessError) => {
        Log.e(`${LOG_TAG} release failed: ${JSON.stringify(error)}`);
      });
    }
    const file: fs.File | undefined = this.mediaFile;
    this.mediaFile = undefined;
    if (file) {
      try {
        fs.closeSync(file);
      } catch (error) {
        Log.e(`${LOG_TAG} close media file failed: ${JSON.stringify(error)}`);
      }
    }
  }

  private progressPercent(): number {
    if (this.durationMs <= 0) {
      return 0;
    }
    const percent: number = (this.currentMs / this.durationMs) * 100;
    if (percent < 0) {
      return 0;
    }
    if (percent > 100) {
      return 100;
    }
    return percent;
  }

  private formatTime(ms: number): string {
    const totalSeconds: number = Math.floor(ms / 1000);
    const minutes: number = Math.floor(totalSeconds / 60);
    const seconds: number = totalSeconds % 60;
    const paddedSeconds: string = seconds < 10 ? `0${seconds}` : `${seconds}`;
    return `${minutes}:${paddedSeconds}`;
  }
}
