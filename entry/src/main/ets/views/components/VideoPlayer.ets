import { Log } from '../../services/logging/Log';
import { fileUri } from '@kit.CoreFileKit';
import { MediaPlaybackCoordinator } from '../../services/content/MediaPlaybackCoordinator';

const LOG_TAG: string = '[ArkDO][VideoPlayer]';

// 帖子内联视频。媒体源同音频(/uploads/short-url/*.xz,302 到跨源 CDN、CF 挡非浏览器客户端),
// 故先经 onResolveMedia(→ host webview 下载委托过盾)下到沙箱,再用原生 Video 组件播本地文件。
// 首帧显示黑底 + 播放按钮,点击后下载并自动播放;参与全局播放协调器(播它时停其它)。
@Component
export struct VideoPlayer {
  src: string = '';
  videoAspectRatio: number = 1.78;
  onResolveMedia: (url: string) => Promise<string> = () => Promise.reject(new Error('媒体下载未接入'));
  // 本地文件 uri(下载完成后填);为空时显示占位。
  @State private localUri: string = '';
  // idle=未开始 / loading=下载中 / ready=已就绪(交给 Video) / error。
  @State private status: string = 'idle';
  // 下载完成时是否自动播放:仅当仍是活跃者(未被其它播放器抢占)才自动播,否则停在首帧等用户点。
  @State private autoPlay: boolean = true;
  private controller: VideoController = new VideoController();
  private coordinatorId: number = 0;

  aboutToAppear(): void {
    this.coordinatorId = MediaPlaybackCoordinator.register(() => {
      this.stopForCoordinator();
    });
  }

  aboutToDisappear(): void {
    MediaPlaybackCoordinator.unregister(this.coordinatorId);
  }

  private stopForCoordinator(): void {
    try {
      this.controller.pause();
    } catch (error) {
      Log.e(`${LOG_TAG} pause on coordinator failed: ${JSON.stringify(error)}`);
    }
  }

  build() {
    Stack() {
      if (this.localUri.length > 0) {
        Video({ src: this.localUri, controller: this.controller })
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .controls(true)
          .autoPlay(this.autoPlay)
          .onStart(() => {
            // 视频真正开始播放:让其它播放器停下。
            MediaPlaybackCoordinator.notifyStarted(this.coordinatorId);
          })
          .onError(() => {
            this.status = 'error';
            this.localUri = '';
          })
      } else {
        Column() {
          if (this.status === 'loading') {
            LoadingProgress()
              .width(48)
              .height(48)
              .color('#FFFFFF')
          } else if (this.status === 'error') {
            Image($rawfile('fa_icons/circle-exclamation.svg'))
              .width(40)
              .height(40)
              .objectFit(ImageFit.Contain)
              .renderMode(ImageRenderMode.Template)
              .fillColor('#FFFFFF')
              .draggable(false)
            Text('加载失败，点击重试')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .margin({ top: 10 })
          } else {
            Image($rawfile('fa_icons/play.svg'))
              .width(30)
              .height(30)
              .objectFit(ImageFit.Contain)
              .renderMode(ImageRenderMode.Template)
              .fillColor('#FFFFFF')
              .draggable(false)
          }
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.start();
        })
      }
    }
    .width('100%')
    .aspectRatio(this.videoAspectRatio)
    .constraintSize({ maxHeight: 520 })
    .backgroundColor('#000000')
    .borderRadius(8)
    .clip(true)
  }

  private start(): void {
    if (this.status === 'loading') {
      return;
    }
    this.status = 'loading';
    // 点击加载即抢占播放:先让其它播放器停下。
    MediaPlaybackCoordinator.notifyStarted(this.coordinatorId);
    this.onResolveMedia(this.src).then((path: string) => {
      // 下载竞态:加载期间若已被别的播放器抢占,则不自动播,停在首帧等用户点。
      this.autoPlay = MediaPlaybackCoordinator.isActive(this.coordinatorId);
      this.localUri = fileUri.getUriFromPath(path);
      this.status = 'ready';
    }).catch((error: Object) => {
      Log.e(`${LOG_TAG} resolve media failed: ${String(error)}`);
      this.status = 'error';
    });
  }
}
