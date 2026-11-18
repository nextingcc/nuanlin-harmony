export interface MemoItem {
  id: string;
  text: string;
  done: boolean;
  dueAt: string;
}

let memoStorageReady: boolean = false;

export function readMemoItems(): MemoItem[] {
  if (!memoStorageReady) {
    PersistentStorage.persistProp('memoItems', '[]');
    memoStorageReady = true;
  }
  try {
    const items = JSON.parse(AppStorage.get<string>('memoItems') ?? '[]') as MemoItem[];
    return Array.isArray(items) ? items : [];
  } catch (e) {
    return [];
  }
}

export function memoDate(date: Date): string {
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

export function memoMinute(date: Date): string {
  const hour = date.getHours().toString().padStart(2, '0');
  const minute = date.getMinutes().toString().padStart(2, '0');
  return `${memoDate(date)} ${hour}:${minute}`;
}

export function isMemoOverdue(item: MemoItem, now: string): boolean {
  const due = item.dueAt ?? '';
  return !item.done && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(due) && due <= now;
}

export function watchMemoMinute(update: (now: string) => void): () => void {
  let timer = -1;
  const tick = (): void => {
    const now = new Date();
    update(memoMinute(now));
    timer = setTimeout(tick, 60000 - now.getTime() % 60000);
  };
  tick();
  return (): void => { clearTimeout(timer); };
}
