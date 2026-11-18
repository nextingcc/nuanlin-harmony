// 提醒文案与去重规则。纯函数，便于单测。
export function reminderDay(date: Date): string {
  return date.getFullYear().toString() + '-' +
    (date.getMonth() + 1).toString().padStart(2, '0') + '-' +
    date.getDate().toString().padStart(2, '0');
}

// 同一天只提醒一次；跨天或上次记录异常时重新提醒。
export function shouldNotify(lastDay: string, today: string): boolean {
  return lastDay !== today;
}

export function reminderCountText(count: number): string {
  return count > 0 ? count.toString() + ' 件' : '0 件';
}

export function reminderSummary(followups: number, care: number): string {
  const total = followups + care;
  if (total <= 0) return '今天没有到期提醒';
  const parts: string[] = [];
  if (followups > 0) parts.push('回访 ' + followups.toString() + ' 条');
  if (care > 0) parts.push('重点关怀 ' + care.toString() + ' 条');
  return parts.join(' · ') + ' 今天到期';
}

export function reminderTag(count: number): string {
  return count > 0 ? '有 ' + count.toString() + ' 件待处理' : '暂无待办';
}
