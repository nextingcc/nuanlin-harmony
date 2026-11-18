import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const AVATAR_FILE: string = 'avatar.jpg';
const SOURCE_FILE: string = 'avatar-src.jpg';

export interface AvatarSourceImage {
  pixelMap: image.PixelMap | undefined;
  width: number;
  height: number;
}

export function avatarPath(context: common.UIAbilityContext): string {
  return context.filesDir + '/' + AVATAR_FILE;
}

export function avatarSourcePath(context: common.UIAbilityContext): string {
  return context.filesDir + '/' + SOURCE_FILE;
}

export function avatarExists(context: common.UIAbilityContext): boolean {
  try {
    return fileIo.accessSync(avatarPath(context));
  } catch (e) {
    return false;
  }
}

function copyUri(uri: string, path: string): void {
  const source = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const target = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      const buffer = new ArrayBuffer(128 * 1024);
      let read: number = fileIo.readSync(source.fd, buffer);
      while (read > 0) {
        fileIo.writeSync(target.fd, buffer.slice(0, read));
        read = fileIo.readSync(source.fd, buffer);
      }
    } finally {
      fileIo.closeSync(target);
    }
  } finally {
    fileIo.closeSync(source);
  }
}

// 选择图片后先落到 avatar-src.jpg 作为裁剪源；用户确认后再写 avatar.jpg。
export async function pickAvatarSource(context: common.UIAbilityContext): Promise<boolean> {
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = 1;
  const result = await new photoAccessHelper.PhotoViewPicker().select(options);
  const uris: string[] = result.photoUris;
  if (uris === undefined || uris.length === 0) return false;
  copyUri(uris[0], avatarSourcePath(context));
  return true;
}

export function discardAvatarSource(context: common.UIAbilityContext): void {
  try {
    fileIo.unlinkSync(avatarSourcePath(context));
  } catch (e) {
    // 源文件不存在时忽略。
  }
}

export async function loadAvatarSourceImage(context: common.UIAbilityContext): Promise<AvatarSourceImage> {
  let file: fileIo.File | null = null;
  let source: image.ImageSource | null = null;
  try {
    file = fileIo.openSync(avatarSourcePath(context), fileIo.OpenMode.READ_ONLY);
    source = image.createImageSource(file.fd);
    const info = await source.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    const k = Math.min(1, 1024 / Math.max(width, height));
    const pixelMap = await source.createPixelMap({
      desiredSize: { width: Math.max(1, Math.round(width * k)), height: Math.max(1, Math.round(height * k)) }
    });
    return { pixelMap: pixelMap, width: width, height: height };
  } catch (e) {
    return { pixelMap: undefined, width: 1, height: 1 };
  } finally {
    if (source !== null) {
      try { await source.release(); } catch (ignored) {}
    }
    if (file !== null) {
      try { fileIo.closeSync(file); } catch (ignored) {}
    }
  }
}

// 按裁剪区域裁切，再压成 256×256 JPEG 写入 avatar.jpg。
export async function saveCroppedAvatar(context: common.UIAbilityContext,
  x: number, y: number, size: number): Promise<boolean> {
  let file: fileIo.File | null = null;
  let source: image.ImageSource | null = null;
  let pixelMap: image.PixelMap | null = null;
  try {
    file = fileIo.openSync(avatarSourcePath(context), fileIo.OpenMode.READ_ONLY);
    source = image.createImageSource(file.fd);
    const info = await source.getImageInfo();
    const sourceWidth = Math.max(1, info.size.width);
    const sourceHeight = Math.max(1, info.size.height);
    const decodeScale = Math.min(1, 1024 / Math.max(sourceWidth, sourceHeight));
    const decodedWidth = Math.max(1, Math.round(sourceWidth * decodeScale));
    const decodedHeight = Math.max(1, Math.round(sourceHeight * decodeScale));
    pixelMap = await source.createPixelMap({ desiredSize: { width: decodedWidth, height: decodedHeight } });
    const ratio = decodedWidth / sourceWidth;
    const side = Math.max(1, Math.min(Math.round(size * ratio), decodedWidth, decodedHeight));
    const left = Math.max(0, Math.min(Math.round(x * ratio), decodedWidth - side));
    const top = Math.max(0, Math.min(Math.round(y * ratio), decodedHeight - side));
    await pixelMap.crop({ x: left, y: top, size: { width: side, height: side } });
    const target = 256 / side;
    await pixelMap.scale(target, target);
    const packer = image.createImagePacker();
    const data = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 92 });
    await packer.release();
    const out = fileIo.openSync(avatarPath(context),
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(out.fd, data);
    } finally {
      fileIo.closeSync(out);
    }
    return true;
  } catch (e) {
    hilog.error(0x0000, 'nuanlin', 'avatar crop failed: %{public}s', JSON.stringify(e));
    return false;
  } finally {
    if (pixelMap !== null) {
      try { await pixelMap.release(); } catch (ignored) {}
    }
    if (source !== null) {
      try { await source.release(); } catch (ignored) {}
    }
    if (file !== null) {
      try { fileIo.closeSync(file); } catch (ignored) {}
    }
  }
}

export async function loadAvatar(context: common.UIAbilityContext): Promise<image.PixelMap | undefined> {
  if (!avatarExists(context)) return undefined;
  let file: fileIo.File | null = null;
  try {
    file = fileIo.openSync(avatarPath(context), fileIo.OpenMode.READ_ONLY);
    const source = image.createImageSource(file.fd);
    const pixelMap = await source.createPixelMap({ desiredSize: { width: 256, height: 256 } });
    await source.release();
    return pixelMap;
  } catch (e) {
    return undefined;
  } finally {
    if (file !== null) {
      try { fileIo.closeSync(file); } catch (ignored) {}
    }
  }
}
