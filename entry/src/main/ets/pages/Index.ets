import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import ContinuousCamera from '../camera/ContinuousCamera';

const MAX_PHOTO_COUNT: number = 9;

@Entry
@Component
struct Index {
  @StorageLink('cameraGranted') cameraGranted: boolean = false;
  @State cameraReady: boolean = false;
  @State isCapturing: boolean = false;
  @State photoUris: Array<string> = [];
  private pendingPhotoCount: number = 0;
  private controller: XComponentController = new XComponentController();
  private surfaceId: string = '';

  async aboutToDisappear(): Promise<void> {
    await ContinuousCamera.release();
  }

  async onPageShow(): Promise<void> {
    if (this.surfaceId !== '' && !this.cameraReady) {
      await this.startCamera();
    }
  }

  async onPageHide(): Promise<void> {
    this.cameraReady = false;
    await ContinuousCamera.release();
  }

  private onPhotoSaved = (uri: string): void => {
    this.pendingPhotoCount = Math.max(0, this.pendingPhotoCount - 1);
    if (uri === '') {
      promptAction.showToast({ message: '照片保存失败，请重拍' });
      return;
    }
    this.photoUris = [...this.photoUris, uri];
    promptAction.showToast({ message: `已拍摄 ${this.photoUris.length} 张，可继续拍` });
  }

  private async startCamera(): Promise<void> {
    if (!this.cameraGranted || this.surfaceId === '') {
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.cameraReady = await ContinuousCamera.start(context, this.surfaceId, this.onPhotoSaved);
    if (!this.cameraReady) {
      promptAction.showToast({ message: '相机启动失败，请检查权限或使用真机调试' });
    }
  }

  private async takePhoto(): Promise<void> {
    if (!this.cameraReady || this.isCapturing ||
      this.photoUris.length + this.pendingPhotoCount >= MAX_PHOTO_COUNT) {
      return;
    }
    this.isCapturing = true;
    this.pendingPhotoCount++;
    try {
      await ContinuousCamera.capture();
    } catch (_) {
      this.pendingPhotoCount = Math.max(0, this.pendingPhotoCount - 1);
      promptAction.showToast({ message: '拍摄失败，请重试' });
    } finally {
      this.isCapturing = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.cameraGranted) {
        XComponent({
          id: 'deliveryCamera',
          type: XComponentType.SURFACE,
          controller: this.controller
        })
          .width('100%')
          .height('100%')
          .onLoad(async (): Promise<void> => {
            this.surfaceId = this.controller.getXComponentSurfaceId();
            // 竖屏预览的 Surface 宽高与 1920x1080 相机流方向相反。
            const rect: SurfaceRect = { surfaceWidth: 1080, surfaceHeight: 1920 };
            this.controller.setXComponentSurfaceRect(rect);
            await this.startCamera();
          })
      } else {
        Column({ space: 16 }) {
          Text('需要相机权限')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
          Text('请允许访问相机，以拍摄送达凭证')
            .fontSize(15)
            .fontColor('#666666')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F5F5')
      }

      Column() {
        Row() {
          Text('送达凭证')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Blank()
          Text(`${this.photoUris.length}/${MAX_PHOTO_COUNT}`)
            .fontSize(16)
            .fontColor(Color.White)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 10 })

        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.photoUris, (_uri: string, index: number) => {
              Column() {
                Text(`${index + 1}`)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
              }
              .width(54)
              .height(54)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#4DFFFFFF')
              .border({ width: 1, color: Color.White })
              .borderRadius(8)
            }, (_uri: string, index: number) => `${index}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(64)
        .padding({ left: 20, right: 20 })

        Row() {
          Button(this.photoUris.length > 0 ? `完成（${this.photoUris.length}张）` : '至少拍摄1张')
            .enabled(this.photoUris.length > 0)
            .width(120)
            .height(44)
            .backgroundColor('#FF7A00')
            .onClick((): void => {
              // 在真实业务中，将 photoUris 一次性回传订单页或批量上传。
              promptAction.showToast({ message: `已完成，共 ${this.photoUris.length} 张送达凭证` });
            })

          Button() {
            Text(this.isCapturing ? '保存中' : '')
              .fontSize(11)
              .fontColor('#333333')
          }
          .enabled(this.cameraReady && !this.isCapturing && this.photoUris.length < MAX_PHOTO_COUNT)
          .width(76)
          .height(76)
          .borderRadius(38)
          .backgroundColor(Color.White)
          .border({ width: 5, color: '#80FFFFFF' })
          .onClick(async (): Promise<void> => {
            await this.takePhoto();
          })

          Text(this.photoUris.length >= MAX_PHOTO_COUNT ? '已达上限' : '拍完自动保存\n可继续拍下一张')
            .width(120)
            .fontSize(13)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
        .alignItems(VerticalAlign.Center)
        .padding({ top: 8, bottom: 24 })
      }
      .width('100%')
      .backgroundColor('#B3000000')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
