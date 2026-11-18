import { resolveDark } from './Theme';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export const DIALECTS: string[] = ['自动识别', '普通话', '武汉话', '黄石话', '十堰话', '宜昌话', '襄阳话', '鄂州话', '荆门话', '孝感话', '荆州话', '黄冈话', '咸宁话', '随州话', '其他'];

export interface UserPreferences {
  voiceDialect: string;
  ttsRate: number;
  textSize: string;
  reduceMotion: boolean;
  themeMode: string;
  followupDate: string;
}

export function referenceDate(value: string): string {
  if (typeof value !== 'string') return '';
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return '';
  const date = new Date(value + 'T12:00:00');
  return !isNaN(date.getTime()) && date.getFullYear() === Number(value.slice(0, 4)) &&
    date.getMonth() + 1 === Number(value.slice(5, 7)) && date.getDate() === Number(value.slice(8, 10)) ? value : '';
}

export function normalizePreferences(input: UserPreferences): UserPreferences {
  const result: UserPreferences = {
    voiceDialect: DIALECTS.indexOf(input.voiceDialect) >= 0 ? input.voiceDialect : '自动识别',
    ttsRate: [0.75, 1, 1.25, 1.5].indexOf(input.ttsRate) >= 0 ? input.ttsRate : 1,
    textSize: ['normal', 'large', 'extra'].indexOf(input.textSize) >= 0 ? input.textSize : 'normal',
    reduceMotion: input.reduceMotion === true,
    themeMode: ['auto', 'light', 'dark'].indexOf(input.themeMode) >= 0 ? input.themeMode : 'auto',
    followupDate: referenceDate(input.followupDate)
  };
  return result;
}

export function readPreferences(): UserPreferences {
  return normalizePreferences({
    voiceDialect: AppStorage.get<string>('voiceDialect') ?? '自动识别',
    ttsRate: AppStorage.get<number>('ttsRate') ?? 1,
    textSize: AppStorage.get<string>('textSize') ?? 'normal',
    reduceMotion: AppStorage.get<boolean>('reduceMotion') ?? false,
    themeMode: AppStorage.get<string>('themeMode') ?? 'auto',
    followupDate: AppStorage.get<string>('followupDate') ?? ''
  });
}

function applyPreferences(input: UserPreferences): void {
  const prefs = normalizePreferences(input);
  AppStorage.setOrCreate('voiceDialect', prefs.voiceDialect);
  AppStorage.setOrCreate('ttsRate', prefs.ttsRate);
  AppStorage.setOrCreate('textSize', prefs.textSize);
  AppStorage.setOrCreate('reduceMotion', prefs.reduceMotion);
  AppStorage.setOrCreate('themeMode', prefs.themeMode);
  AppStorage.setOrCreate('followupDate', prefs.followupDate);
}

// flush 成功后才更新共享状态，页面不会把写盘失败提示为保存成功。
export async function savePreferences(context: common.Context, input: UserPreferences): Promise<void> {
  const value = normalizePreferences(input);
  const store = await preferences.getPreferences(context, { name: 'nuanlin_preferences' });
  await store.put('settings', JSON.stringify(value));
  await store.flush();
  applyPreferences(value);
}

export function applyPreferenceTheme(systemDark: boolean): void {
  AppStorage.setOrCreate('darkMode', resolveDark(AppStorage.get<string>('themeMode') ?? 'auto', systemDark));
}

// 首个页面加载前从有明确Context的Preferences恢复；授权和业务记录不写入设置。
export async function initializePreferences(context: common.Context, systemDark: boolean = false): Promise<void> {
  let value = readPreferences();
  try {
    const store = await preferences.getPreferences(context, { name: 'nuanlin_preferences' });
    const saved = await store.get('settings', '') as string;
    if (saved.length > 0) value = normalizePreferences(JSON.parse(saved) as UserPreferences);
  } catch (e) {
    // 损坏或暂不可读时使用安全默认值，后续显式保存可重试。
  }
  applyPreferences(value);
  applyPreferenceTheme(systemDark);
}

// 标准模式保留现有尺寸，大字/特大给工作信息设置可读下限。
export function readableFont(base: number, size: string): number {
  if (size === 'large') return Math.max(16, Math.round(base * 1.15));
  if (size === 'extra') return Math.max(18, Math.round(base * 1.3));
  return base;
}

export function readableLineHeight(base: number, size: string): number {
  if (size === 'large') return Math.max(24, Math.round(base * 1.15));
  if (size === 'extra') return Math.max(28, Math.round(base * 1.3));
  return base;
}
