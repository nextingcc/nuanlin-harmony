export class Theme {
  static readonly ink: string = '#4A3428';
  static readonly ink2: string = '#7C5E46';
  static readonly muted: string = '#A0806E';
  static readonly cream: string = '#FEFAF4';
  static readonly paper: string = '#FBEEF0';
  static readonly pink: string = '#C2778A';
  static readonly pinkSoft: string = '#EFD8DC';
  static readonly green: string = '#7E8F63';
  static readonly greenDeep: string = '#5C6B45';
  static readonly sky: string = '#93B9C7';
  static readonly line: string = '#E8CBD0';
  static readonly lineWarm: string = '#EEDCC9';
  static readonly lilac: string = '#F0E9F6';
  static readonly creamSoft: string = 'rgba(255,253,248,0.92)';
}

// 运行时调色板：浅色值与 Theme 的既有颜色一致，深色只影响操作类页面。
export interface Palette {
  pageBg: string;
  surface: string;
  surfaceSoft: string;
  border: string;
  ink: string;
  ink2: string;
  muted: string;
  chipBg: string;
  chipInk: string;
  accent: string;
  accentText: string;
  segBg: string;
  segActive: string;
  divider: string;
  section: string;
  iconA: string;
  iconB: string;
  iconC: string;
  segInk: string;
  segSub: string;
  chevron: string;
  noteBorder: string;
  danger: string;
  dangerBg: string;
}

const LIGHT: Palette = {
  pageBg: '#F8E8E2',
  surface: '#FFFDF8',
  surfaceSoft: '#F7F2E7',
  border: '#EFDCCF',
  ink: '#4A3428',
  ink2: '#7C5E46',
  muted: '#A0806E',
  chipBg: '#F5ECE1',
  chipInk: '#6E5343',
  accent: '#7E8F63',
  accentText: '#5C6B45',
  segBg: '#F3EADF',
  segActive: '#FFFDF8',
  divider: '#F3E5D9',
  section: '#9C7E66',
  iconA: '#F6E9DC',
  iconB: '#EDF2E2',
  iconC: '#EFF3E4',
  segInk: '#8A6B54',
  segSub: '#B39A85',
  chevron: '#C6AC97',
  noteBorder: '#E3D2BF',
  danger: '#9C4A45',
  dangerBg: '#F7E4E1'
};

const DARK: Palette = {
  pageBg: '#151311',
  surface: '#241F1B',
  surfaceSoft: '#1D1916',
  border: '#3A332C',
  ink: '#F0E6DA',
  ink2: '#D3C3B2',
  muted: '#A99A8B',
  chipBg: '#332C26',
  chipInk: '#D9C8B6',
  accent: '#8FA574',
  accentText: '#B7C79F',
  segBg: '#2A2420',
  segActive: '#3A332C',
  divider: '#332C26',
  section: '#B9A794',
  iconA: '#2E2723',
  iconB: '#2A2E24',
  iconC: '#2C2A22',
  segInk: '#CBB9A7',
  segSub: '#8E7F71',
  chevron: '#8A7C6E',
  noteBorder: '#3A332C',
  danger: '#E3A5A0',
  dangerBg: '#3A2A28'
};

export function palette(dark: boolean): Palette {
  return dark ? DARK : LIGHT;
}

// themeMode: 'auto' 跟随系统 / 'light' 浅色 / 'dark' 深色。
export function resolveDark(themeMode: string, systemDark: boolean): boolean {
  if (themeMode === 'dark') return true;
  if (themeMode === 'light') return false;
  return systemDark;
}

export function isDarkMode(): boolean {
  return AppStorage.get<boolean>('darkMode') === true;
}
