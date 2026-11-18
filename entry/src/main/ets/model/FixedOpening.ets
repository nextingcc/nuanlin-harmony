import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

export const FIXED_OPENING_SENTENCES: string[] = ['您好呀。', '我是暖邻语音助手，陪着工作人员和您聊聊。',
  '接下来聊聊您的心情和日常，按实际感受说就好，可以慢慢想。', '想停一停，随时告诉我们。'];

export async function fixedOpeningAudio(context: common.UIAbilityContext): Promise<string> {
  const bytes = await context.resourceManager.getRawFileContent('opening_x4_yezi_v1.mp3');
  const path = context.cacheDir + '/opening_x4_yezi_v1.mp3';
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try { fileIo.writeSync(file.fd, bytes.buffer); } finally { fileIo.closeSync(file); }
  return path;
}
