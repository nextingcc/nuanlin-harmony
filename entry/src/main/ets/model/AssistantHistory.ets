import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE: string = 'nuanlin_assistant_history';
const KEY: string = 'items';
const LIMIT: number = 30;
const MESSAGE_LIMIT: number = 24;
const TEXT_LIMIT: number = 600;

export interface AssistantHistoryMessage {
  role: string;
  text: string;
}

export interface AssistantHistoryItem {
  id: string;
  title: string;
  updatedAt: number;
  preview: string;
  messages: AssistantHistoryMessage[];
}

let store: preferences.Preferences | null = null;

async function ready(context: common.UIAbilityContext): Promise<preferences.Preferences> {
  if (store === null) {
    store = await preferences.getPreferences(context, { name: STORE });
  }
  return store;
}

function normalize(raw: Record<string, Object>): AssistantHistoryItem {
  const rawMessages = raw['messages'];
  const messages: AssistantHistoryMessage[] = Array.isArray(rawMessages)
    ? (rawMessages as AssistantHistoryMessage[]) : [];
  const preview = typeof raw['preview'] === 'string' ? raw['preview'] as string : '';
  return {
    id: raw['id'] as string,
    title: (raw['title'] as string) || '会话',
    updatedAt: typeof raw['updatedAt'] === 'number' ? raw['updatedAt'] as number : 0,
    preview: preview.length > 0 ? preview : (messages.length > 0 ? messages[messages.length - 1].text : ''),
    messages: messages.filter((item: AssistantHistoryMessage) => !!item && typeof item.text === 'string')
      .map((item: AssistantHistoryMessage) => {
        const message: AssistantHistoryMessage = {
          role: item.role === 'user' ? 'user' : 'assistant',
          text: item.text.length > TEXT_LIMIT ? item.text.slice(0, TEXT_LIMIT) + '…' : item.text
        };
        return message;
      })
  };
}

export async function readAssistantHistory(context: common.UIAbilityContext): Promise<AssistantHistoryItem[]> {
  try {
    const prefs = await ready(context);
    const raw = await prefs.get(KEY, '[]');
    if (typeof raw !== 'string' || raw.length === 0) return [];
    const parsed = JSON.parse(raw) as Record<string, Object>[];
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item: Record<string, Object>) => typeof item['id'] === 'string' && (item['id'] as string).length > 0)
      .map((item: Record<string, Object>) => normalize(item))
      .filter((item: AssistantHistoryItem) => item.messages.length > 0 || item.preview.length > 0)
      .sort((a: AssistantHistoryItem, b: AssistantHistoryItem) => b.updatedAt - a.updatedAt);
  } catch (e) {
    return [];
  }
}

async function write(context: common.UIAbilityContext, items: AssistantHistoryItem[]): Promise<void> {
  const prefs = await ready(context);
  await prefs.put(KEY, JSON.stringify(items.slice(0, LIMIT)));
  await prefs.flush();
}

export async function rememberAssistantConversation(context: common.UIAbilityContext, id: string,
  title: string, updatedAt: number, messages: AssistantHistoryMessage[]): Promise<void> {
  if (id.length === 0) return;
  try {
    const items = await readAssistantHistory(context);
    const clean = title.trim().replace(/\s+/g, ' ').slice(0, 24);
    const kept = items.find((item: AssistantHistoryItem) => item.id === id);
    const recent = messages.slice(-MESSAGE_LIMIT).map((item: AssistantHistoryMessage) => {
      const message: AssistantHistoryMessage = {
        role: item.role,
        text: item.text.length > TEXT_LIMIT ? item.text.slice(0, TEXT_LIMIT) + '…' : item.text
      };
      return message;
    });
    const preview = recent.length > 0 ? recent[recent.length - 1].text : '';
    const next: AssistantHistoryItem[] = items.filter((item: AssistantHistoryItem) => item.id !== id);
    const entry: AssistantHistoryItem = {
      id: id,
      title: kept ? kept.title : (clean.length > 0 ? clean : '新对话'),
      updatedAt: updatedAt,
      preview: preview,
      messages: recent.length > 0 ? recent : (kept ? kept.messages : [])
    };
    next.unshift(entry);
    await write(context, next);
  } catch (e) {
    // 历史记录只是本地便利功能，失败不影响对话。
  }
}

export async function renameAssistantConversation(context: common.UIAbilityContext, id: string,
  title: string): Promise<void> {
  try {
    const items = await readAssistantHistory(context);
    const clean = title.trim().replace(/\s+/g, ' ').slice(0, 24);
    if (clean.length === 0) return;
    const next = items.map((item: AssistantHistoryItem) => {
      if (item.id !== id) return item;
      const updated: AssistantHistoryItem = {
        id: item.id, title: clean, updatedAt: Date.now(), preview: item.preview, messages: item.messages
      };
      return updated;
    });
    await write(context, next);
  } catch (e) {
    // 同上。
  }
}

export async function forgetAssistantConversation(context: common.UIAbilityContext, id: string): Promise<void> {
  try {
    const items = await readAssistantHistory(context);
    await write(context, items.filter((item: AssistantHistoryItem) => item.id !== id));
  } catch (e) {
    // 同上。
  }
}
