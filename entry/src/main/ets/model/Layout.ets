// 一多（手机 / 平板 / 2in1）断点规则。纯函数，便于单测。
export class Layout {
  // HarmonyOS 官方断点：sm < 600vp ≤ md < 840vp ≤ lg
  static readonly MEDIUM: number = 600;
  static readonly LARGE: number = 840;

  static parseWidth(value: string | number): number {
    const width = typeof value === 'number' ? value : parseFloat(value);
    return isNaN(width) || width < 0 ? 0 : width;
  }

  static isWide(width: number): boolean {
    return width >= Layout.MEDIUM;
  }

  static columns(width: number): number {
    if (width >= Layout.LARGE) return 3;
    if (width >= Layout.MEDIUM) return 2;
    return 1;
  }

  // 两栏时给卡片留出中间间距，返回百分比字符串，例如 "48.5%"
  static cardRatio(columns: number, gap: number): string {
    const count = columns < 1 ? 1 : columns;
    const inner = 100 - (count - 1) * gap;
    return (inner / count).toFixed(1) + '%';
  }
}
