// 服务卡片数据：复用 App 会话，读取到期回访与重点关怀数量。
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { reminderCountText, reminderSummary } from './ReminderRules';
import { decryptSession, isEncryptedSession } from './SecureStore';

const BASE: string = 'http://127.0.0.1:8010/api/v1';

export interface CardView {
  title: string;
  count: string;
  detail: string;
}

interface ReminderList {
  items: Object[];
}

async function sessionCookie(context: common.Context): Promise<string> {
  try {
    const store = await preferences.getPreferences(context, { name: 'nuanlin_session' });
    const saved = await store.get('session', '') as string;
    const cookie = isEncryptedSession(saved) ? await decryptSession(saved) : saved;
    return /^nuanlin_session=[A-Za-z0-9_-]+$/.test(cookie) ? cookie : '';
  } catch (e) {
    return '';
  }
}

async function itemCount(path: string, cookie: string): Promise<number> {
  const req = http.createHttp();
  try {
    const res = await req.request(BASE + path, {
      method: http.RequestMethod.GET,
      header: { 'Cookie': cookie, 'Accept': 'application/json' },
      connectTimeout: 3000,
      readTimeout: 3000,
      expectDataType: http.HttpDataType.STRING
    });
    if (res.responseCode === 401) return -2;
    if (res.responseCode !== 200) return -1;
    const body = JSON.parse(res.result as string) as Record<string, Object>;
    const data = body['data'] as ReminderList;
    return Array.isArray(data.items) ? data.items.length : -1;
  } catch (e) {
    return -1;
  } finally {
    req.destroy();
  }
}

export function loadingCard(): CardView {
  const view: CardView = { title: '今日提醒', count: '…', detail: '正在读取回访与关怀' };
  return view;
}

export async function reminderCard(context: common.Context): Promise<CardView> {
  const cookie = await sessionCookie(context);
  if (cookie.length === 0) {
    const signedOut: CardView = { title: '今日提醒', count: '—', detail: '打开暖邻登录后查看' };
    return signedOut;
  }
  const due = await itemCount('/followups?view=due', cookie);
  const care = await itemCount('/care-cases', cookie);
  if (due === -2 || care === -2) {
    const expired: CardView = { title: '今日提醒', count: '—', detail: '登录已失效，打开暖邻重新登录' };
    return expired;
  }
  if (due < 0 && care < 0) {
    const offline: CardView = { title: '今日提醒', count: '—', detail: '暂时读不到，点开暖邻查看' };
    return offline;
  }
  if (due < 0 || care < 0) {
    const partial: CardView = {
      title: '今日提醒', count: '—',
      detail: due < 0 ? '回访暂不可用 · 重点关怀 ' + care.toString() + ' 条' :
        '回访 ' + due.toString() + ' 条 · 重点关怀暂不可用'
    };
    return partial;
  }
  const followups = due > 0 ? due : 0;
  const cases = care > 0 ? care : 0;
  const view: CardView = {
    title: '今日提醒',
    count: reminderCountText(followups + cases),
    detail: reminderSummary(followups, cases)
  };
  return view;
}
