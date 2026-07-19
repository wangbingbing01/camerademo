import { camera } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ContinuousCamera';

export type PhotoSavedCallback = (uri: string) => void;

/**
 * 一个会话连续拍多张：拍照后保存，但不关闭相机、也不跳确认页。
 */
class ContinuousCamera {
  private context: common.UIAbilityContext | undefined = undefined;
  private cameraManager: camera.CameraManager | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  private session: camera.PhotoSession | undefined = undefined;
  private onPhotoSaved: PhotoSavedCallback = () => {};

  async start(context: common.UIAbilityContext, surfaceId: string,
    onPhotoSaved: PhotoSavedCallback): Promise<boolean> {
    await this.release();
    this.context = context;
    this.onPhotoSaved = onPhotoSaved;

    try {
      this.cameraManager = camera.getCameraManager(context);
      const cameras: Array<camera.CameraDevice> = this.cameraManager.getSupportedCameras();
      if (cameras.length === 0) {
        return false;
      }

      // 手机的第一个设备通常是后置主摄；业务项目也可按 cameraPosition 进一步筛选。
      const device: camera.CameraDevice = cameras[0];
      const mode: camera.SceneMode = camera.SceneMode.NORMAL_PHOTO;
      const capability: camera.CameraOutputCapability =
        this.cameraManager.getSupportedOutputCapability(device, mode);
      if (capability.previewProfiles.length === 0 || capability.photoProfiles.length === 0) {
        return false;
      }

      const previewProfile: camera.Profile = capability.previewProfiles[0];
      const photoProfile: camera.Profile = capability.photoProfiles[0];
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, surfaceId);
      this.photoOutput = this.cameraManager.createPhotoOutput(photoProfile);
      this.cameraInput = this.cameraManager.createCameraInput(device);
      await this.cameraInput.open();

      this.photoOutput.on('photoAssetAvailable',
        (error: BusinessError, asset: photoAccessHelper.PhotoAsset): void => {
          if (error || asset === undefined) {
            hilog.error(DOMAIN, TAG, 'photoAssetAvailable failed: %{public}s', JSON.stringify(error));
            return;
          }
          this.savePhoto(asset);
        });

      this.photoOutput.on('error', (error: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'Photo output error: %{public}s', JSON.stringify(error));
      });

      this.session = this.cameraManager.createSession(mode) as camera.PhotoSession;
      this.session.beginConfig();
      this.session.addInput(this.cameraInput);
      this.session.addOutput(this.previewOutput);
      this.session.addOutput(this.photoOutput);
      await this.session.commitConfig();
      await this.session.start();
      return true;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Start camera failed: %{public}d %{public}s', err.code, err.message);
      await this.release();
      return false;
    }
  }

  /** 每次调用只拍一张；调用结束后预览会话仍保持运行，可立即拍下一张。 */
  async capture(): Promise<void> {
    if (this.photoOutput === undefined) {
      throw new Error('Camera is not ready');
    }
    const setting: camera.PhotoCaptureSetting = {
      quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
      mirror: false
    };
    await this.photoOutput.capture(setting);
  }

  private async savePhoto(asset: photoAccessHelper.PhotoAsset): Promise<void> {
    if (this.context === undefined) {
      return;
    }
    try {
      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(this.context);
      const request: photoAccessHelper.MediaAssetChangeRequest =
        new photoAccessHelper.MediaAssetChangeRequest(asset);
      request.saveCameraPhoto();
      await helper.applyChanges(request);
      this.onPhotoSaved(asset.uri);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Save photo failed: %{public}d %{public}s', err.code, err.message);
      this.onPhotoSaved('');
    }
  }

  async release(): Promise<void> {
    try {
      await this.session?.stop();
    } catch (_) {
    }
    try {
      await this.previewOutput?.release();
    } catch (_) {
    }
    try {
      await this.photoOutput?.release();
    } catch (_) {
    }
    try {
      await this.session?.release();
    } catch (_) {
    }
    try {
      await this.cameraInput?.close();
    } catch (_) {
    }
    this.previewOutput = undefined;
    this.photoOutput = undefined;
    this.session = undefined;
    this.cameraInput = undefined;
    this.cameraManager = undefined;
  }
}

export default new ContinuousCamera();
