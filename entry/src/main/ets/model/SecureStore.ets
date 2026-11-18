// 会话加密：HUKS 内生成不可导出的 AES-256 密钥，Preferences 里只存密文。
// 采用 CBC + PKCS7：HUKS 的 GCM 解密在模拟器上对 AE_TAG 处理不稳定，CBC 行为可预期。
import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

const KEY_ALIAS: string = 'nuanlin_session_aes_v3';
const IV_SIZE: number = 16;
const VERSION: string = 'v1';
const base64: util.Base64Helper = new util.Base64Helper();

function param(tag: huks.HuksTag, value: boolean | number | bigint | Uint8Array): huks.HuksParam {
  const item: huks.HuksParam = { tag: tag, value: value };
  return item;
}

function cipherProperties(iv: Uint8Array, purpose: number): huks.HuksParam[] {
  return [
    param(huks.HuksTag.HUKS_TAG_ALGORITHM, huks.HuksKeyAlg.HUKS_ALG_AES),
    param(huks.HuksTag.HUKS_TAG_PURPOSE, purpose),
    param(huks.HuksTag.HUKS_TAG_BLOCK_MODE, huks.HuksCipherMode.HUKS_MODE_CBC),
    param(huks.HuksTag.HUKS_TAG_PADDING, huks.HuksKeyPadding.HUKS_PADDING_PKCS7),
    param(huks.HuksTag.HUKS_TAG_IV, iv)
  ];
}

async function ensureKey(): Promise<void> {
  let exists: boolean = false;
  try {
    exists = await huks.isKeyItemExist(KEY_ALIAS, { properties: [] });
  } catch (e) {
    // 部分版本在密钥不存在时抛异常而不是返回 false。
    exists = false;
  }
  if (exists) return;
  await huks.generateKeyItem(KEY_ALIAS, {
    properties: [
      param(huks.HuksTag.HUKS_TAG_ALGORITHM, huks.HuksKeyAlg.HUKS_ALG_AES),
      param(huks.HuksTag.HUKS_TAG_KEY_SIZE, huks.HuksKeySize.HUKS_AES_KEY_SIZE_256),
      param(huks.HuksTag.HUKS_TAG_PURPOSE,
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT),
      param(huks.HuksTag.HUKS_TAG_PADDING, huks.HuksKeyPadding.HUKS_PADDING_PKCS7),
      param(huks.HuksTag.HUKS_TAG_BLOCK_MODE, huks.HuksCipherMode.HUKS_MODE_CBC),
      param(huks.HuksTag.HUKS_TAG_DIGEST, huks.HuksKeyDigest.HUKS_DIGEST_NONE)
    ]
  });
}

function randomIv(): Uint8Array {
  return cryptoFramework.createRandom().generateRandomSync(IV_SIZE).data;
}

export async function encryptSession(plain: string): Promise<string> {
  await ensureKey();
  const iv: Uint8Array = randomIv();
  const properties: huks.HuksParam[] = cipherProperties(iv, huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT);
  const handle: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, { properties: properties });
  const out: huks.HuksReturnResult = await huks.finishSession(handle.handle, {
    properties: properties,
    inData: new util.TextEncoder().encodeInto(plain)
  });
  if (out.outData === undefined || out.outData.length === 0) throw new Error('encrypt failed');
  return VERSION + '.' + base64.encodeToStringSync(iv) + '.' + base64.encodeToStringSync(out.outData);
}

export async function decryptSession(stored: string): Promise<string> {
  const parts: string[] = stored.split('.');
  if (parts.length !== 3 || parts[0] !== VERSION) return '';
  const iv: Uint8Array = base64.decodeSync(parts[1]);
  const cipher: Uint8Array = base64.decodeSync(parts[2]);
  const properties: huks.HuksParam[] = cipherProperties(iv, huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT);
  const handle: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, { properties: properties });
  const out: huks.HuksReturnResult = await huks.finishSession(handle.handle, {
    properties: properties,
    inData: cipher
  });
  if (out.outData === undefined || out.outData.length === 0) return '';
  const plain: string = util.TextDecoder.create('utf-8').decodeToString(out.outData);
  return plain.startsWith('nuanlin_session=') ? plain : '';
}

export function isEncryptedSession(stored: string): boolean {
  return stored.startsWith(VERSION + '.');
}
