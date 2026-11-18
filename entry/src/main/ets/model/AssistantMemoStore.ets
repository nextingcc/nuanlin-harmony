import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { MemoItem, readMemoItems } from './MemoReminders';
import { AssistantAction } from './AssistantChat';

interface MemoReceipt {
  actionId: string;
  ownerKey: string;
  memoId: string;
  fingerprint: string;
}
interface MemoState {
  version: number;
  deviceId: string;
  items: MemoItem[];
  receipts: MemoReceipt[];
}

const STORE_NAME: string = 'nuanlin_assistant_memos';
let memoStore: preferences.Preferences | undefined;
let memoContext: common.Context | undefined;
let committed: MemoState | null = null;
let committedRaw: string = '';
let queue: Promise<void> = Promise.resolve();

function serial<T>(operation: () => Promise<T>): Promise<T> {
  const result = queue.then(operation);
  queue = result.then(() => {}, () => {});
  return result;
}

function copyItems(items: MemoItem[]): MemoItem[] {
  if (!Array.isArray(items)) throw new Error('备忘录内容不可读取，未覆盖原数据。');
  const ids: string[] = [];
  return items.map((item: MemoItem): MemoItem => {
    if (!item || typeof item.id !== 'string' || !item.id || ids.includes(item.id) ||
      typeof item.text !== 'string' || typeof item.done !== 'boolean' ||
      (item.dueAt !== undefined && typeof item.dueAt !== 'string')) {
      throw new Error('备忘录记录不完整，未覆盖原数据。');
    }
    ids.push(item.id);
    return { id: item.id, text: item.text, done: item.done, dueAt: item.dueAt ?? '' };
  });
}

function parseState(raw: string): MemoState {
  const state = JSON.parse(raw) as MemoState;
  if (!state || state.version !== 1 || typeof state.deviceId !== 'string' || !state.deviceId ||
    !Array.isArray(state.receipts)) throw new Error('备忘录存储损坏，请保留数据后重试。');
  state.items = copyItems(state.items);
  const receiptIds: string[] = [];
  for (const receipt of state.receipts) {
    if (!receipt || !receipt.actionId || !receipt.ownerKey || receipt.memoId !== 'assistant-' + receipt.actionId ||
      typeof receipt.fingerprint !== 'string' || receiptIds.includes(receipt.actionId)) {
      throw new Error('助手执行回执不可读取，未覆盖原数据。');
    }
    receiptIds.push(receipt.actionId);
  }
  return state;
}

function publish(state: MemoState): void {
  AppStorage.setOrCreate('memoItems', JSON.stringify(state.items));
  AppStorage.setOrCreate('assistantMemoStorageError', '');
}

async function commit(state: MemoState): Promise<void> {
  if (!memoStore) throw new Error('备忘录存储尚未初始化，请重新进入应用。');
  const raw = JSON.stringify(state);
  try {
    await memoStore.put('state', raw);
    await memoStore.flush();
  } catch (e) {
    // Preferences.put also mutates its in-process cache. Restore the last known
    // committed JSON so a later get/flush cannot publish the failed operation.
    try { await memoStore.put('state', committedRaw); } catch (ignored) {}
    AppStorage.setOrCreate('assistantMemoStorageError', '备忘录尚未写入本机，请重试。');
    throw new Error('备忘录尚未写入本机，请重试。');
  }
  committedRaw = raw;
  committed = state;
  publish(state);
}

async function initialize(): Promise<void> {
  if (committed) return;
  if (!memoContext) throw new Error('备忘录存储尚未初始化，请重新进入应用。');
  memoStore = await preferences.getPreferences(memoContext, { name: STORE_NAME });
  const raw = await memoStore.get('state', '') as string;
  if (raw) {
    const state = parseState(raw);
    committedRaw = raw;
    committed = state;
    // Prime the previous PersistentStorage property before updating its value.
    readMemoItems();
    publish(state);
    return;
  }
  const initial: MemoState = { version: 1, deviceId: 'memo-device-' + util.generateRandomUUID(true),
    items: copyItems(readMemoItems()), receipts: [] };
  await commit(initial);
}

export async function initializeAssistantMemoStore(context: common.Context): Promise<void> {
  memoContext = context;
  return serial(async () => {
    try { await initialize(); }
    catch (e) {
      AppStorage.setOrCreate('assistantMemoStorageError', '本机备忘录尚未准备好，请重试。');
      throw new Error((e as Error).message || '本机备忘录尚未准备好，请重试。');
    }
  });
}

export function assistantDeviceId(): string {
  return committed?.deviceId ?? '';
}

export async function saveAssistantMemoItems(items: MemoItem[]): Promise<void> {
  const desired = copyItems(items);
  return serial(async () => {
    await initialize();
    const state = committed as MemoState;
    await commit({ version: 1, deviceId: state.deviceId, items: desired, receipts: state.receipts.slice() });
  });
}

function validDueAt(value: string): boolean {
  if (!value) return true;
  if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(value)) return false;
  const date = new Date(value.replace(' ', 'T') + ':00');
  return Number.isFinite(date.getTime()) && date.getFullYear() === Number(value.slice(0, 4)) &&
    date.getMonth() + 1 === Number(value.slice(5, 7)) && date.getDate() === Number(value.slice(8, 10)) &&
    date.getHours() === Number(value.slice(11, 13)) && date.getMinutes() === Number(value.slice(14, 16));
}

export async function executeAssistantMemo(action: AssistantAction, ownerKey: string): Promise<string> {
  return serial(async () => {
    await initialize();
    const state = committed as MemoState;
    if (!action || action.kind !== 'create_memo' || action.status !== 'awaiting_device' ||
      typeof action.id !== 'string' || !action.id || action.id.length > 128 ||
      !Number.isInteger(action.revision) || action.revision < 1 ||
      typeof ownerKey !== 'string' || !ownerKey || action.ownerKey !== ownerKey || action.deviceId !== state.deviceId ||
      typeof action.executionToken !== 'string' || !action.executionToken.trim()) {
      throw new Error('助手备忘录指令与当前账号或设备不一致，未执行。');
    }
    const text = action.payload?.text;
    const dueAt = action.payload?.dueAt ?? '';
    if (typeof text !== 'string' || !text.trim() || text.trim().length > 1000 ||
      typeof dueAt !== 'string' || !validDueAt(dueAt)) throw new Error('备忘录内容或时间无效，未执行。');
    const clean = text.trim();
    const fingerprint = JSON.stringify([action.id, ownerKey, text, dueAt]);
    const receipt = state.receipts.find((value: MemoReceipt) => value.actionId === action.id);
    if (receipt) {
      if (receipt.ownerKey !== ownerKey || receipt.fingerprint !== fingerprint) {
        throw new Error('备忘录指令已变化，不能复用原执行回执。');
      }
      return receipt.memoId;
    }
    if (typeof action.expiresAt !== 'string' || !Number.isFinite(Date.parse(action.expiresAt)) ||
      Date.parse(action.expiresAt) <= Date.now()) {
      throw new Error('备忘录指令已过期或有效期不可核对，请重新确认。');
    }
    const memoId = 'assistant-' + action.id;
    if (state.items.some((value: MemoItem) => value.id === memoId)) throw new Error('备忘录标识已存在，请重新核对。');
    const item: MemoItem = { id: memoId, text: clean, dueAt: dueAt, done: false };
    const nextReceipt: MemoReceipt = { actionId: action.id, ownerKey: ownerKey, memoId: memoId, fingerprint: fingerprint };
    await commit({ version: 1, deviceId: state.deviceId, items: [...state.items, item], receipts: [...state.receipts, nextReceipt] });
    return memoId;
  });
}
