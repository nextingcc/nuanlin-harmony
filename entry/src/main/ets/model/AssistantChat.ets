export interface AssistantSource {
  id: string;
  label: string;
  personId: string;
  assessmentId?: string;
  date?: string;
}

export interface AssistantMessage {
  id: string;
  role: string;
  text: string;
  sources: AssistantSource[];
  actionIds?: string[];
}

export interface AssistantActionPayload {
  name?: string;
  age?: number | null;
  gender?: string;
  community?: string;
  address?: string;
  phone?: string;
  living?: string;
  contactName?: string;
  contactPhone?: string;
  notes?: string;
  text?: string;
  dueAt?: string;
  date?: string;
  startTime?: string;
  endTime?: string;
  transport?: string;
  returnToStart?: boolean;
}

export interface AssistantDuplicate { id: string; name: string; age: number; community: string; }
export interface AssistantActionResult { personId?: string; memoId?: string; planId?: string; message?: string; }
export interface AssistantAction {
  id: string;
  kind: string;
  status: string;
  revision: number;
  expiresAt: string;
  ownerKey: string;
  payload: AssistantActionPayload;
  duplicates: AssistantDuplicate[];
  result?: AssistantActionResult;
  executionToken?: string;
  deviceId?: string;
}

export interface AssistantConversation {
  id: string;
  personId: string | null;
  messages: AssistantMessage[];
  revision: number;
  inflight?: boolean;
  actions?: AssistantAction[];
}

export interface AssistantAttachment {
  name: string;
  text: string;
}

export interface PendingAssistantMessage {
  text: string;
  clientMessageId: string;
  attachments?: AssistantAttachment[];
}

let assistantStorageReady: boolean = false;
export function lastAssistantConversationId(): string {
  if (!assistantStorageReady) {
    // Only an opaque ID is stored on the phone; messages stay in encrypted backend storage.
    PersistentStorage.persistProp('assistantConversationId', '');
    assistantStorageReady = true;
  }
  return AppStorage.get<string>('assistantConversationId') || '';
}

// A retry represents the same turn, including when the first response was lost.
export function pendingAssistantMessage(text: string, attachments: AssistantAttachment[] = []): PendingAssistantMessage {
  const clean = text.trim();
  if (!clean || clean.length > 2000) throw new Error('请输入1～2000字的问题。');
  const message: PendingAssistantMessage = {
    text: clean,
    clientMessageId: 'chat-' + Date.now().toString() + '-' + Math.random().toString(36).slice(2)
  };
  if (attachments.length > 0) message.attachments = attachments.slice(0, 3);
  return message;
}

export function appendAssistantDictation(original: string, transcript: string): string {
  const speech = transcript.trim();
  if (!speech) throw new Error('没有识别到文字，可以重新录音或打字。');
  const merged = original + (original && !original.endsWith('\n') ? '\n' : '') + speech;
  if (merged.length > 2000) throw new Error('合并后超过2000字，原输入已保留。可长按复制转写文字，整理后发送。');
  return merged;
}

export function requireAssistantConversation(value: AssistantConversation, expectedId: string = ''): AssistantConversation {
  if (!value || !value.id || (expectedId && value.id !== expectedId) ||
    !Array.isArray(value.messages) || !Number.isInteger(value.revision) || value.revision < 1) {
    throw new Error('对话信息不一致，请重新加载。');
  }
  for (const message of value.messages) {
    if (!message.id || (message.role !== 'user' && message.role !== 'assistant') ||
      typeof message.text !== 'string' || !Array.isArray(message.sources)) {
      throw new Error('对话内容不完整，请重新加载。');
    }
  }
  return value;
}
