import { http } from '@kit.NetworkKit';
import { request as uploadRequest } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { decryptSession, encryptSession, isEncryptedSession } from './SecureStore';
import { InterviewEvent, InterviewEventParser } from './InterviewProgress';
import { patchRequest } from './PatchTransport';
import { OpeningContent } from './OpeningState';
import { AssistantConversation, PendingAssistantMessage, requireAssistantConversation, AssistantAction, AssistantActionPayload } from './AssistantChat';
import { VisitPlanContext, VisitPlanPrepareInput, VisitPlanPrepared, VisitPlanSolveInput, VisitPlanNavigation, VisitPlanList } from './VisitPlanState';
import { LocationContext, LocationInput, requireLocationContext, navigableLocation } from './MapLocationState';

interface AssistantStreamFrame {
  type: string;
  text?: string;
  message?: string;
  response?: Envelope;
}

export interface ResidenceInput {
  address: string;
  phone: string;
  living: string;
  contactName: string;
  contactPhone: string;
}

export interface Person {
  notes?: string | null;
  preferredAddress?: string | null;
  preferredAddressConfirmed?: boolean;
  communicationNeeds?: string[];
  revision?: number;
  living?: string;
  contactName?: string;
  contactPhone?: string;
  id: string;
  name: string;
  age: number;
  gender: string;
  phone: string;
  community: string;
  address: string;
  assessmentCount: number;
  needsFollowup?: boolean;
  lastAssessmentAt: string | null;
}

interface VoiceCapabilities {
  enabled: boolean;
  asrReady: boolean;
  ttsReady: boolean;
}

// 后端允许这些资料未填写并返回null；页面消费统一为可显示的空字符串。
export function normalizePerson(person: Person): Person {
  person.gender = person.gender ?? '';
  person.community = person.community ?? '';
  person.phone = person.phone ?? '';
  person.address = person.address ?? '';
  person.living = person.living ?? '';
  person.contactName = person.contactName ?? '';
  person.contactPhone = person.contactPhone ?? '';
  return person;
}
export interface VoiceSession {
  ticket: string;
  path: string;
  expiresIn: number;
}

interface Envelope {
  data: Object;
}

export interface JournalEntry {
  date: string;
  diary: string;
  mood: string;
  comfort: number | null;
}

export interface JournalSuggestion {
  suggestion_id: string;
  title: string;
  content: string;
  category: string;
  illustration: string;
  steps: string[];
  created_at: string;
  text: string;
  source: string;
  page?: number;
  section?: string;
}

export interface JournalAnalysis {
  contextId: string;
  periodStart: string;
  periodEnd: string;
  diaryDates: string[];
  diaries: JournalDiarySource[];
  score: number | null;
  summary: string;
  state: string;
  diaryCount: number;
  moodCount: number;
}

export interface JournalDiarySource {
  date: string;
  text: string;
}

export interface JournalAdviceBundle {
  items: JournalSuggestion[];
  diaryDates: string[];
  analysis: JournalAnalysis | null;
}

export interface JournalDraft {
  day: string;
  text: string;
}

export interface Assessment {
  id: string;
  scale: string;
  status: string;
  startedAt: string;
  score: number | null;
  completedAt: string | null;
}

export interface ImportField {
  field: string;
  value: string | number;
  status: string;
}

export interface ImportEvidence {
  quote: string;
}
export interface ImportIssue {
  message: string;
  candidateField?: string;
  candidatePreview?: string;
  evidence?: ImportEvidence[];
}
export interface ImportBlock {
  text: string;
}

export interface NoteFact {
  evidence?: ImportEvidence[];
  id: string;
  statement: string;
  category: string;
  validationStatus: string;
}

export interface ImportResult {
  fields: ImportField[];
  noteFacts: NoteFact[];
  issues?: ImportIssue[];
  warnings: string[];
}

export interface ImportBatch {
  id: string;
  revision: number;
  status: string;
  result: ImportResult | null;
  blocks?: ImportBlock[];
  errors?: ImportIssue[];
  documents: Object[];
  subjects: Object[];
}

export interface PersonInput {
  name: string;
  age: number;
  gender: string;
  community: string;
  phone: string;
  address: string;
  living: string;
  contactName: string;
  contactPhone: string;
  notes: string;
}

interface AssessmentPage {
  items: Assessment[];
  nextCursor: string | null;
}

interface PersonPage {
  items: Person[];
  nextCursor: string | null;
}

let cookie: string = '';
let csrf: string = '';
let sessionStorage: preferences.Preferences | undefined;

// 两类原生通信实现共用状态码、鉴权错误和版本校验处理。
interface RequestReply {
  responseCode: number;
  result: string | Object | ArrayBuffer;
  cookies: string;
}

const BASE: string = 'http://127.0.0.1:8010/api/v1';

function headerMap(): Record<string, string> {
  const h: Record<string, string> = { 'Content-Type': 'application/json' };
  if (cookie.length > 0) {
    h['Cookie'] = cookie;
  }
  if (csrf.length > 0) {
    h['X-CSRF-Token'] = csrf;
  }
  return h;
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
}

async function sendRaw(url: string, method: http.RequestMethod | 'PATCH', headers: Record<string, string>,
  body: string, readTimeout: number): Promise<RequestReply> {
  if (method === 'PATCH') {
    const patched = await patchRequest(url, headers, body, readTimeout);
    return { responseCode: patched.responseCode, result: patched.result, cookies: patched.cookies };
  }
  const req = http.createHttp();
  try {
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      connectTimeout: 8000,
      readTimeout: readTimeout,
      expectDataType: http.HttpDataType.STRING
    };
    if (body.length > 0) {
      options.extraData = body;
    }
    const standard = await req.request(url, options);
    return { responseCode: standard.responseCode, result: standard.result, cookies: standard.cookies };
  } finally {
    req.destroy();
  }
}

// 统一重试：网络异常与 5xx/408/429 自动重试一次；写请求复用同一个 Idempotency-Key，避免重复提交。
async function request(path: string, method: http.RequestMethod | 'PATCH', body: string, revision: number = 0,
  readTimeout: number = 8000): Promise<string> {
  const headers: Record<string, string> = headerMap();
  if (method !== http.RequestMethod.GET) {
    headers['Idempotency-Key'] = 'nl-' + Date.now().toString() + '-' + Math.random().toString(36).slice(2);
  }
  if (revision > 0) headers['If-Match'] = '"' + revision.toString() + '"';
  let lastError: Error = new Error('网络请求失败，请检查连接后重试。');
  for (let attempt = 0; attempt < 2; attempt++) {
    let res: RequestReply;
    try {
      hilog.info(0x0000, 'nuanlin', 'REQ %{public}s %{public}s', String(method), BASE + path);
      res = await sendRaw(BASE + path, method, headers, body, readTimeout);
    } catch (e) {
      const failure = e as Record<string, Object>;
      const code = failure['code'] as number;
      lastError = new Error(code !== undefined
        ? '网络连接失败，请检查网络或后端服务后重试。'
        : ((e as Error).message || '网络请求失败，请重试。'));
      hilog.warn(0x0000, 'nuanlin', 'request retry attempt=%{public}d error=%{public}s', attempt, JSON.stringify(e));
      if (attempt === 0) {
        await delay(300);
        continue;
      }
      hilog.error(0x0000, 'nuanlin', 'request error: %{public}s', JSON.stringify(e));
      throw lastError;
    }
    hilog.info(0x0000, 'nuanlin', 'HTTP %{public}d %{public}s', res.responseCode, path);
    const setCookie = res.cookies;
    if (typeof setCookie === 'string' && setCookie.length > 0) {
      const standard = /(?:^|[;,\s])nuanlin_session=([A-Za-z0-9_-]+)/.exec(setCookie);
      const tabular = /(?:^|\t)nuanlin_session\t([A-Za-z0-9_-]+)/.exec(setCookie);
      const session = standard ?? tabular;
      if (session) cookie = 'nuanlin_session=' + session[1];
    }
    if (res.responseCode >= 200 && res.responseCode < 300) {
      return res.result as string;
    }
    let message: string = '';
    try {
      const errorBody = JSON.parse(res.result as string) as Record<string, Object>;
      const error = errorBody['error'] as Record<string, Object>;
      message = error !== undefined && error !== null ? (error['message'] as string) : '';
    } catch (e) {}
    if (attempt === 0 && (res.responseCode >= 500 || res.responseCode === 408 || res.responseCode === 429)) {
      lastError = new Error(message || `服务请求失败（${res.responseCode}），正在重试…`);
      hilog.warn(0x0000, 'nuanlin', 'server retry attempt=0 code=%{public}d', res.responseCode);
      await delay(400);
      continue;
    }
    if (res.responseCode === 401) {
      cookie = '';
      csrf = '';
      AppStorage.setOrCreate('assistantConversationId', '');
      AppStorage.setOrCreate('assistantOwnerKey', '');
      try {
        await sessionStorage?.delete('session');
        await sessionStorage?.flush();
      } catch (e) {}
    }
    throw new Error(message || `服务请求失败（${res.responseCode}），请刷新状态后重试。`);
  }
  throw lastError;
}

export interface FollowupHistoryRecord {
  id: string;
  personId: string;
  date: string;
  method: string;
  outcome: string;
  notes: string;
}

export interface FollowupHistoryPage {
  items: FollowupHistoryRecord[];
  nextCursor: string | null;
}

export interface FollowupStart {
  taskId: string;
  personId: string;
  assessmentId: string;
}

export interface FollowupTaskContext {
  id: string;
  personId: string;
  revision: number;
  kind?: string;
  state?: string;
  status?: string;
  activeAssessmentId?: string | null;
  dueAt?: string;
  plannedDate?: string;
}

export interface FollowupContext { task: FollowupTaskContext; person: Person; }

export class Api {
  static async visitPlanList(cursor: string = ''): Promise<VisitPlanList> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/visit-plans?limit=20' + (cursor ? '&cursor=' + encodeURIComponent(cursor) : ''),
      http.RequestMethod.GET, '');
    const value = (JSON.parse(raw) as Envelope).data as VisitPlanList;
    if (!value || !Array.isArray(value.items)) throw new Error('计划列表读取失败，请重试。');
    return value;
  }

  static async visitPlan(id: string): Promise<VisitPlanContext> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/visit-plans/' + encodeURIComponent(id), http.RequestMethod.GET, '');
    const value = (JSON.parse(raw) as Envelope).data as VisitPlanContext;
    if (!value || value.actionId !== id) throw new Error('计划信息不一致，请重新读取。');
    return value;
  }

  static async prepareVisitPlan(id: string, revision: number, input: VisitPlanPrepareInput): Promise<VisitPlanPrepared> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    if (input.revision !== revision) throw new Error('计划版本不一致，请重新核对。');
    const raw = await request('/assistant/visit-plans/' + encodeURIComponent(id) + '/prepare', http.RequestMethod.POST,
      JSON.stringify(input), revision);
    return (JSON.parse(raw) as Envelope).data as VisitPlanPrepared;
  }

  static async solveVisitPlan(id: string, revision: number, input: VisitPlanSolveInput): Promise<VisitPlanContext> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    if (input.revision !== revision) throw new Error('计划版本不一致，请重新核对。');
    const raw = await request('/assistant/visit-plans/' + encodeURIComponent(id) + '/solve', http.RequestMethod.POST,
      JSON.stringify(input), revision, 20000);
    return (JSON.parse(raw) as Envelope).data as VisitPlanContext;
  }

  static async visitPlanNavigation(id: string, personId: string): Promise<VisitPlanNavigation> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/visit-plans/' + encodeURIComponent(id) + '/navigation/' + encodeURIComponent(personId),
      http.RequestMethod.GET, '');
    return (JSON.parse(raw) as Envelope).data as VisitPlanNavigation;
  }

  static assistantOwnerKey(): string {
    return AppStorage.get<string>('assistantOwnerKey') || '';
  }

  static async updateAssistantAction(id: string, revision: number, payload: AssistantActionPayload): Promise<AssistantAction> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/actions/' + encodeURIComponent(id) + '/update', http.RequestMethod.POST,
      JSON.stringify({ revision, payload }));
    return (JSON.parse(raw) as Envelope).data as AssistantAction;
  }

  static async confirmAssistantAction(action: AssistantAction, deviceId: string, acknowledgeDuplicate: boolean): Promise<AssistantAction> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const body = action.kind === 'create_memo' ? JSON.stringify({ revision: action.revision, deviceId, acknowledgeDuplicate }) :
      JSON.stringify({ revision: action.revision, acknowledgeDuplicate });
    const raw = await request('/assistant/actions/' + encodeURIComponent(action.id) + '/confirm', http.RequestMethod.POST,
      body);
    return (JSON.parse(raw) as Envelope).data as AssistantAction;
  }

  static async cancelAssistantAction(action: AssistantAction): Promise<AssistantAction> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/actions/' + encodeURIComponent(action.id) + '/cancel', http.RequestMethod.POST,
      JSON.stringify({ revision: action.revision }));
    return (JSON.parse(raw) as Envelope).data as AssistantAction;
  }

  static async receiptAssistantAction(action: AssistantAction, deviceId: string, memoId: string, error: string = ''): Promise<AssistantAction> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/actions/' + encodeURIComponent(action.id) + '/receipt', http.RequestMethod.POST,
      JSON.stringify({ revision: action.revision, deviceId, executionToken: action.executionToken || '',
        status: error ? 'failed' : 'completed', memoId: memoId || null, error: error || null }));
    return (JSON.parse(raw) as Envelope).data as AssistantAction;
  }

  static async createAssistantConversation(personId: string = ''): Promise<AssistantConversation> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/conversations', http.RequestMethod.POST,
      JSON.stringify({ personId: personId || null }));
    return requireAssistantConversation((JSON.parse(raw) as Envelope).data as AssistantConversation);
  }

  static async assistantConversation(id: string): Promise<AssistantConversation> {
    if (!id || !await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/conversations/' + encodeURIComponent(id), http.RequestMethod.GET, '');
    return requireAssistantConversation((JSON.parse(raw) as Envelope).data as AssistantConversation, id);
  }

  static async extractAssistantAttachment(name: string, content: string): Promise<Record<string, Object>> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/assistant/attachments', http.RequestMethod.POST,
      JSON.stringify({ name: name, content: content }), 0, 300000);
    return (JSON.parse(raw) as Envelope).data as Record<string, Object>;
  }

  static async sendAssistantMessage(id: string, pending: PendingAssistantMessage, preview?: (text: string) => void): Promise<AssistantConversation> {
    if (!id || !await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    if (preview) {
      const req = http.createHttp();
      const decoder = util.TextDecoder.create('utf-8');
      try {
        return await new Promise<AssistantConversation>((resolve, reject) => {
          let buffer = ''; let finished = false;
          const fail = (message: string): void => { if (!finished) { finished = true; reject(new Error(message)); } };
          req.on('dataReceive', (chunk: ArrayBuffer) => {
            if (finished) return;
            try {
              buffer += decoder.decodeToString(new Uint8Array(chunk), { stream: true });
              let split = buffer.indexOf('\n');
              while (split >= 0 && !finished) {
                const line = buffer.slice(0, split); buffer = buffer.slice(split + 1);
                if (line.trim()) {
                  const event = JSON.parse(line) as AssistantStreamFrame;
                  if (event.type === 'preview') preview(event.text || '');
                  if (event.type === 'error') fail(event.message || '回答未完成，请重试。');
                  if (event.type === 'done') {
                    const result = requireAssistantConversation(event.response?.data as AssistantConversation, id);
                    finished = true; resolve(result);
                  }
                }
                split = buffer.indexOf('\n');
              }
            } catch (e) { fail('回答连接异常，请重试同一条消息。'); }
          });
          req.on('dataEnd', () => fail('回答连接已中断，请重试同一条消息。'));
          req.requestInStream(BASE + '/assistant/conversations/' + encodeURIComponent(id) + '/messages/stream', {
            method: http.RequestMethod.POST, header: { 'Content-Type': 'application/json', 'Accept': 'application/x-ndjson',
              'Cookie': cookie, 'X-CSRF-Token': csrf }, extraData: JSON.stringify(pending), connectTimeout: 8000, readTimeout: 100000
          }).then((status: number) => { if (status !== 200) fail('助手请求失败（' + status + '），请重试。'); })
            .catch(() => fail('回答连接失败，请重试同一条消息。'));
        });
      } finally { req.destroy(); }
    }
    const raw = await request('/assistant/conversations/' + encodeURIComponent(id) + '/messages',
      http.RequestMethod.POST, JSON.stringify(pending), 0, 100000);
    return requireAssistantConversation((JSON.parse(raw) as Envelope).data as AssistantConversation, id);
  }

  static async followupContext(id: string): Promise<FollowupContext> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/followups/' + encodeURIComponent(id) + '/context', http.RequestMethod.GET, '');
    const value = (JSON.parse(raw) as Envelope).data as FollowupContext;
    if (!value.task || !value.person || value.task.id !== id || value.task.personId !== value.person.id) {
      throw new Error('任务与人员资料不一致，请刷新核对。');
    }
    value.person = normalizePerson(value.person);
    return value;
  }
  static async archiveReviewedInterview(id: string, revision: number): Promise<void> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request('/interviews/' + encodeURIComponent(id) + '/archive', http.RequestMethod.POST,
      JSON.stringify({ revision, confirmedRevision: revision, followupMode: 'auto' }), revision);
  }
  static async editReport(id: string, revision: number, editedText: string): Promise<void> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request('/interviews/' + encodeURIComponent(id) + '/summary', 'PATCH',
      JSON.stringify({ revision, editedText }), revision);
  }

  static async confirmReport(id: string, revision: number): Promise<void> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request('/interviews/' + encodeURIComponent(id) + '/confirm', http.RequestMethod.POST,
      JSON.stringify({ revision, reviewedRevision: revision }), revision);
  }

  static async followupItems(id: string): Promise<Object> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/interviews/' + encodeURIComponent(id) + '/followup-items', http.RequestMethod.GET, '');
    return (JSON.parse(raw) as Envelope).data;
  }

  static async draftFollowupItems(id: string, revision: number): Promise<void> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request('/interviews/' + encodeURIComponent(id) + '/followup-items/draft', http.RequestMethod.POST,
      JSON.stringify({ revision }), revision);
  }

  static async decideFollowupItem(id: string, revision: number, decision: string, note: string): Promise<void> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request('/followup-items/' + encodeURIComponent(id), 'PATCH',
      JSON.stringify({ revision, decision, note }), revision);
  }
  static async followupHistory(cursor: string = ''): Promise<FollowupHistoryPage> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const suffix = cursor.length > 0 ? '&cursor=' + encodeURIComponent(cursor) : '';
    const text = await request('/followup-records?limit=20' + suffix, http.RequestMethod.GET, '');
    const page = (JSON.parse(text) as Envelope).data as FollowupHistoryPage;
    if (!Array.isArray(page.items)) throw new Error('回访记录读取失败，请重试。');
    return page;
  }
  static async restoreSession(context: common.UIAbilityContext): Promise<boolean> {
    try {
      sessionStorage = await preferences.getPreferences(context, { name: 'nuanlin_session' });
      const saved = await sessionStorage.get('session', '');
      if (typeof saved !== 'string' || saved.length === 0) return false;
      const legacy: boolean = !isEncryptedSession(saved) && /^nuanlin_session=[A-Za-z0-9_-]+$/.test(saved);
      const value: string = isEncryptedSession(saved) ? await decryptSession(saved) : (legacy ? saved : '');
      if (value.length === 0) return false;
      cookie = value;
      const raw = await request('/me', http.RequestMethod.GET, '', 0, 4000);
      const data = (JSON.parse(raw) as Envelope).data as Record<string, Object>;
      csrf = data['csrfToken'] as string;
      const account = data['account'] as string;
      if (typeof account === 'string' && account.length > 0) AppStorage.setOrCreate('accountName', account);
      const org = data['organizationId'] as string;
      if (typeof org === 'string' && org.length > 0) AppStorage.setOrCreate('orgName', org);
      const actorId = data['id'] as string;
      AppStorage.setOrCreate('assistantOwnerKey', org && actorId ? org + ':' + actorId : '');
      if (legacy) await Api.persistSession();
      return typeof csrf === 'string' && csrf.length > 0;
    } catch (e) {
      cookie = '';
      csrf = '';
      // A temporary network/startup failure is not evidence that the saved session
      // is revoked. HTTP 401 already clears it in request(); keep ciphertext here.
      return false;
    }
  }

  // 会话只以 HUKS 加密后的密文落盘；HUKS 不可用时宁可不持久化。
  private static async persistSession(): Promise<void> {
    if (!sessionStorage || cookie.length === 0) return;
    try {
      await sessionStorage.put('session', await encryptSession(cookie));
      await sessionStorage.flush();
    } catch (e) {
      hilog.warn(0x0000, 'nuanlin', 'session not persisted: %{public}s', JSON.stringify(e));
    }
  }

  // 退出登录：清空内存会话与磁盘密文，不删除其他本地数据。
  static async logout(): Promise<void> {
    cookie = '';
    csrf = '';
    AppStorage.setOrCreate('assistantOwnerKey', '');
    AppStorage.setOrCreate('assistantConversationId', '');
    try {
      await sessionStorage?.delete('session');
      await sessionStorage?.flush();
    } catch (e) {
      hilog.warn(0x0000, 'nuanlin', 'logout cleanup failed: %{public}s', JSON.stringify(e));
    }
  }
  static async journal(start: string, end: string): Promise<JournalEntry[]> {
    const raw = await request(`/journal?start=${start}&end=${end}`, http.RequestMethod.GET, '');
    return (JSON.parse(raw) as Envelope).data as JournalEntry[];
  }

  static async saveJournal(day: string, diary: string | null, mood: string | null, comfort: number | null): Promise<void> {
    await request('/journal/entries/' + day, http.RequestMethod.PUT, JSON.stringify({ diary, mood, comfort }));
  }

  static async journalSuggestions(start: string, diaryDates: string[], draft?: JournalDraft, contextId?: string): Promise<JournalSuggestion[]> {
    const raw = await request('/journal/suggestions', http.RequestMethod.POST,
      JSON.stringify({ start, diaryDates, draft, contextId }), 0, 120000);
    return (JSON.parse(raw) as Envelope).data as JournalSuggestion[];
  }

  static async journalAnalysis(start: string, diaryDates: string[]): Promise<JournalAnalysis> {
    const raw = await request('/journal/analysis', http.RequestMethod.POST,
      JSON.stringify({ start, diaryDates }), 0, 90000);
    return (JSON.parse(raw) as Envelope).data as JournalAnalysis;
  }

  static async journalPrevious(start: string): Promise<JournalAdviceBundle> {
    const raw = await request('/journal/suggestions?start=' + start, http.RequestMethod.GET, '');
    return (JSON.parse(raw) as Envelope).data as JournalAdviceBundle;
  }
  static subscribeInterview(id: string, receive: (event: InterviewEvent) => void,
    disconnected: () => void): () => void {
    if (!cookie) throw new Error('登录已失效，请重新登录。');
    const req = http.createHttp();
    const decoder = util.TextDecoder.create('utf-8');
    const parser = new InterviewEventParser();
    let closed = false;
    const close = (): void => {
      if (closed) return;
      closed = true;
      req.destroy();
    };
    const finish = (): void => {
      if (closed) return;
      close();
      disconnected();
    };
    req.on('dataReceive', (chunk: ArrayBuffer) => {
      if (closed) return;
      try {
        parser.feed(decoder.decodeToString(new Uint8Array(chunk), { stream: true }), (event: InterviewEvent) => {
          if (!closed) receive(event);
        });
      } catch (e) { finish(); }
    });
    req.on('dataEnd', finish);
    try {
      req.requestInStream(`${BASE}/interviews/${encodeURIComponent(id)}/events`, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'text/event-stream', 'Cookie': cookie },
        connectTimeout: 8000,
        readTimeout: 45000
      }).then((status: number) => { if (status !== 200) finish(); }).catch(finish);
    } catch (e) {
      close();
      throw e as Error;
    }
    return close;
  }

  static async login(account: string, password: string): Promise<boolean> {
    try {
      const text = await request('/auth/login', http.RequestMethod.POST,
        JSON.stringify({ account: account, password: password }));
      const env = JSON.parse(text) as Envelope;
      const data = env.data as Record<string, Object>;
      AppStorage.setOrCreate('assistantConversationId', '');
      AppStorage.setOrCreate('assistantOwnerKey', '');
      if (typeof data['csrfToken'] === 'string') {
        csrf = data['csrfToken'] as string;
      }
      const user = data['user'] as Record<string, Object>;
      if (user !== undefined && user !== null) {
        const accountName = user['account'] as string;
        if (typeof accountName === 'string' && accountName.length > 0) AppStorage.setOrCreate('accountName', accountName);
        const org = user['organizationId'] as string;
        if (typeof org === 'string' && org.length > 0) AppStorage.setOrCreate('orgName', org);
        const actorId = user['id'] as string;
        AppStorage.setOrCreate('assistantOwnerKey', org && actorId ? org + ':' + actorId : '');
      }
      hilog.info(0x0000, 'nuanlin', 'csrf length: %{public}d', csrf.length);
      if (cookie && csrf && sessionStorage) {
        await Api.persistSession();
      }
      return cookie.length > 0;
    } catch (e) {
      hilog.error(0x0000, 'nuanlin', 'login error: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  static async ensureSession(): Promise<boolean> {
    return cookie.length > 0;
  }

  static async people(): Promise<Person[]> {
    const ok = await Api.ensureSession();
    if (!ok) throw new Error('登录已失效，请重新登录。');
    const text = await request('/people?limit=50', http.RequestMethod.GET, '');
    const env = JSON.parse(text) as Envelope;
    const page = env.data as PersonPage;
    return page.items.map((person: Person) => normalizePerson(person));
  }

  static async person(id: string): Promise<Person | null> {
    const ok = await Api.ensureSession();
    if (!ok) return null;
    const text = await request(`/people/${id}`, http.RequestMethod.GET, '');
    const env = JSON.parse(text) as Envelope;
    return normalizePerson(env.data as Person);
  }

  static async residenceLocation(id: string): Promise<LocationContext> {
    if (!id || !await Api.ensureSession()) throw new Error('请重新登录并选择居民。');
    const text = await request('/people/' + encodeURIComponent(id) + '/residence-location', http.RequestMethod.GET, '');
    return requireLocationContext((JSON.parse(text) as Envelope).data as LocationContext, id);
  }

  static async saveResidenceLocation(id: string, revision: number, input: LocationInput): Promise<LocationContext> {
    if (!id || !Number.isInteger(revision) || revision < 1 || !await Api.ensureSession()) {
      throw new Error('无法核对登录或档案版本，请重新读取。');
    }
    const text = await request('/people/' + encodeURIComponent(id) + '/residence-location', http.RequestMethod.PUT,
      JSON.stringify({ revision: revision, latitude: input.latitude, longitude: input.longitude,
        coordinateSystem: input.coordinateSystem, provider: input.provider, cityCode: input.cityCode,
        addressSnapshot: input.addressSnapshot, poiId: input.poiId, entranceLabel: input.entranceLabel, confirmed: input.confirmed }), revision);
    const value = requireLocationContext((JSON.parse(text) as Envelope).data as LocationContext, id);
    const location = navigableLocation(value, id);
    if (value.revision <= revision || location.latitude !== input.latitude || location.longitude !== input.longitude ||
      location.coordinateSystem !== input.coordinateSystem) throw new Error('保存结果尚未核对成功，请重新读取位置。');
    return value;
  }

  static async updateCommunicationPreferences(id: string, revision: number, preferredAddress: string,
    confirmed: boolean, needs: string[]): Promise<void> {
    if (!id || !Number.isInteger(revision) || revision < 1 || !await Api.ensureSession()) throw new Error('无法核对登录或人员版本。');
    const text = await request('/people/' + encodeURIComponent(id), 'PATCH', JSON.stringify({ revision: revision,
      preferredAddress: preferredAddress, preferredAddressConfirmed: confirmed, communicationNeeds: needs }), revision);
    const value = (JSON.parse(text) as Envelope).data as Person;
    if (!value || value.id !== id || (value.revision ?? 0) <= revision) throw new Error('尚未核对保存成功，请重新读取档案。');
  }

  static async updateResidence(id: string, revision: number, input: ResidenceInput): Promise<Person> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    if (!id || !Number.isInteger(revision) || revision < 1) throw new Error('档案版本不可用，请重新读取。');
    const body = JSON.stringify({ revision: revision, address: input.address, phone: input.phone,
      living: input.living, contactName: input.contactName, contactPhone: input.contactPhone });
    const text = await request('/people/' + encodeURIComponent(id), 'PATCH', body, revision);
    const value = (JSON.parse(text) as Envelope).data as Person;
    if (!value || value.id !== id) throw new Error('保存返回的人员不一致，请重新读取核对。');
    return normalizePerson(value);
  }

  static async createPerson(input: PersonInput): Promise<Person | null> {
    const ok = await Api.ensureSession();
    if (!ok) return null;
    const text = await request('/people', http.RequestMethod.POST, JSON.stringify(input));
    const env = JSON.parse(text) as Envelope;
    return env.data as Person;
  }

  static async deletePerson(id: string): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const req = http.createHttp();
    const headers: Record<string, string> = {};
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'del-' + Date.now().toString();
    try {
      const res = await req.request(BASE + '/people/' + id, {
        method: http.RequestMethod.DELETE,
        header: headers,
        expectDataType: http.HttpDataType.STRING
      });
      hilog.info(0x0000, 'nuanlin', 'delete person %{public}d', res.responseCode);
      return res.responseCode === 200 || res.responseCode === 204;
    } catch (e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  static async assessments(id: string): Promise<Assessment[]> {
    const ok = await Api.ensureSession();
    if (!ok) return [];
    const text = await request(`/people/${id}/assessments?limit=20`, http.RequestMethod.GET, '');
    const env = JSON.parse(text) as Envelope;
    const page = env.data as AssessmentPage;
    return page.items;
  }

  static async capabilities(): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const text = await request('/document-import-capabilities', http.RequestMethod.GET, '');
    const env = JSON.parse(text) as Envelope;
    const data = env.data as Record<string, Object>;
    return data['enabled'] === true;
  }

  static async createImport(): Promise<ImportBatch | null> {
    const ok = await Api.ensureSession();
    if (!ok) return null;
    const text = await request('/document-imports', http.RequestMethod.POST, '{}');
    const env = JSON.parse(text) as Envelope;
    return env.data as ImportBatch;
  }

  static async uploadImportDocument(batch: ImportBatch,
    filePath: string, filename: string, mime: string): Promise<ImportBatch> {
    const headers = headerMap();
    headers['Content-Type'] = 'multipart/form-data';
    headers['Idempotency-Key'] = 'doc-' + Date.now().toString() + '-' + Math.random().toString(36).slice(2);
    headers['If-Match'] = '"' + batch.revision.toString() + '"';
    const req = http.createHttp();
    try {
      const response = await req.request(BASE + '/document-imports/' + batch.id + '/documents?synthetic=true', {
        header: headers,
        method: http.RequestMethod.POST,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING,
        multiFormDataList: [{ remoteFileName: filename, name: 'file', filePath: filePath, contentType: mime }]
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const body = JSON.parse(response.result as string) as Record<string, Object>;
        const error = body['error'] as Record<string, Object>;
        throw new Error((error?.['message'] as string) || '上传失败，请重试。');
      }
      return (JSON.parse(response.result as string) as Envelope).data as ImportBatch;
    } finally {
      req.destroy();
    }
  }

  static async runImport(batch: ImportBatch): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'run-' + Date.now().toString() + '-' + Math.random().toString(36).slice(2);
    headers['If-Match'] = '"' + batch.revision.toString() + '"';
    const req = http.createHttp();
    try {
      const res = await req.request(BASE + '/document-imports/' + batch.id + '/run', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: '{}',
        connectTimeout: 15000,
        readTimeout: 120000,
        expectDataType: http.HttpDataType.STRING
      });
      hilog.info(0x0000, 'nuanlin', 'run %{public}d', res.responseCode);
      return res.responseCode === 200 || res.responseCode === 202;
    } catch (e) {
      hilog.error(0x0000, 'nuanlin', 'run error %{public}s', JSON.stringify(e));
      return false;
    } finally {
      req.destroy();
    }
  }

  static async getImport(id: string): Promise<ImportBatch | null> {
    const ok = await Api.ensureSession();
    if (!ok) return null;
    const text = await request('/document-imports/' + id, http.RequestMethod.GET, '');
    const env = JSON.parse(text) as Envelope;
    return env.data as ImportBatch;
  }

  static async uploadAttachment(context: common.UIAbilityContext, personId: string,
    filename: string): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const headers: Record<string, string> = {};
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'att-' + Date.now().toString() + '-' + Math.random().toString(36).slice(2);
    try {
      const task = await uploadRequest.uploadFile(context, {
        url: BASE + '/people/' + personId + '/attachments',
        header: headers,
        method: 'POST',
        files: [{ filename: filename, name: 'file', uri: 'internal://cache/' + filename, type: 'application/octet-stream' }],
        data: []
      });
      hilog.info(0x0000, 'nuanlin', 'upload task %{public}s', task);
      return true;
    } catch (e) {
      hilog.error(0x0000, 'nuanlin', 'upload error %{public}s', JSON.stringify(e));
      return false;
    }
  }

  static async me(): Promise<boolean> {
    try {
      await request('/me', http.RequestMethod.GET, '');
      return true;
    } catch (e) {
      return false;
    }
  }

  static async startInterview(personId: string): Promise<ImportBatch | null> {
    const ok = await Api.ensureSession();
    if (!ok) return null;
    const body = JSON.stringify({ instrumentId: 'TOPIC-INTERVIEW', interactionMode: 'assisted', workflow: 'automatic' });
    const text = await request('/people/' + personId + '/assessments', http.RequestMethod.POST, body);
    const env = JSON.parse(text) as Envelope;
    return env.data as ImportBatch;
  }

  static async getInterview(id: string): Promise<Object | null> {
    const ok = await Api.ensureSession();
    if (!ok) return null;
    const text = await request('/interviews/' + id, http.RequestMethod.GET, '');
    const env = JSON.parse(text) as Envelope;
    return env.data;
  }

  static async precheckInterview(id: string, revision: number): Promise<boolean> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request(`/interviews/${id}/precheck?opening=true`, http.RequestMethod.PUT,
      JSON.stringify({ consent: true, accessibility: true, safetyChecks: true, revision: revision }), revision);
    return true;
  }

  static async submitTurn(id: string, revision: number, topicId: string, questionId: string,
    verbatim: string): Promise<boolean> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request(`/interviews/${id}/turns`, http.RequestMethod.POST,
      JSON.stringify({ topicId: topicId, questionId: questionId, verbatim: verbatim,
        source: 'resident', revision: revision }), revision);
    return true;
  }

  static async confirmTopic(id: string, revision: number, topicId: string,
    optionId: string): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const req = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'cf-' + Date.now().toString();
    headers['If-Match'] = '"' + revision.toString() + '"';
    try {
      const res = await req.request(BASE + '/interviews/' + id + '/topics/' + topicId + '/confirm', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({
          revision: revision, status: 'answered', frequencyOptionId: optionId,
          basis: '工作人员核对原话后确认', timeframeConfirmed: true, reviewedRevision: revision
        }),
        connectTimeout: 15000, readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      });
      hilog.info(0x0000, 'nuanlin', 'confirm topic %{public}d', res.responseCode);
      return res.responseCode === 200;
    } catch (e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  static async calculate(id: string, revision: number): Promise<number | null> {
    const ok = await Api.ensureSession();
    if (!ok) return null;
    const req = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'calc-' + Date.now().toString();
    headers['If-Match'] = '"' + revision.toString() + '"';
    try {
      const res = await req.request(BASE + '/interviews/' + id + '/calculate', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({ revision: revision }),
        expectDataType: http.HttpDataType.STRING
      });
      if (res.responseCode !== 200) return null;
      const env = JSON.parse(res.result as string) as Record<string, Object>;
      const data = env['data'] as Record<string, Object>;
      const score = data['score'];
      return typeof score === 'number' ? score : null;
    } catch (e) {
      return null;
    } finally {
      req.destroy();
    }
  }

  static async confirmRisk(id: string, revision: number, riskLevel: string, basis: string): Promise<void> {
    await request('/interviews/' + id + '/risk-confirmation', http.RequestMethod.POST,
      JSON.stringify({ revision, riskLevel, basis }), revision);
  }

  static async reviewSupplement(id: string, revision: number, plannedDate: string): Promise<void> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request('/interviews/' + encodeURIComponent(id) + '/supplemental-review', http.RequestMethod.POST,
      JSON.stringify({ revision: revision, plannedDate: plannedDate, acknowledged: true }), revision);
  }

  static async confirmInterview(id: string, revision: number): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const req = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'cfi-' + Date.now().toString();
    headers['If-Match'] = '"' + revision.toString() + '"';
    try {
      const res = await req.request(BASE + '/interviews/' + id + '/confirm', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({ revision: revision, reviewedRevision: revision }),
        expectDataType: http.HttpDataType.STRING
      });
      return res.responseCode === 200;
    } catch (e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  static async archiveInterview(id: string, revision: number): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const req = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'ar-' + Date.now().toString();
    headers['If-Match'] = '"' + revision.toString() + '"';
    try {
      const res = await req.request(BASE + '/interviews/' + id + '/archive', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({ revision: revision, confirmedRevision: revision, followupMode: 'auto' }),
        expectDataType: http.HttpDataType.STRING
      });
      hilog.info(0x0000, 'nuanlin', 'archive %{public}d', res.responseCode);
      return res.responseCode === 200;
    } catch (e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  static async addFollowupRecord(taskId: string, revision: number, method: string, outcome: string,
    notes: string, date: string): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const req = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    const recordKey = 'rec-' + Date.now().toString();
    headers['Idempotency-Key'] = recordKey;
    headers['If-Match'] = '"' + revision.toString() + '"';
    try {
      const res = await req.request(BASE + '/followups/' + taskId + '/records', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({
          revision: revision, date: date, method: method, outcome: outcome,
          notes: notes, idempotencyKey: recordKey
        }),
        expectDataType: http.HttpDataType.STRING
      });
      hilog.info(0x0000, 'nuanlin', 'record %{public}d', res.responseCode);
      return res.responseCode === 201;
    } catch (e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  static async startFollowup(taskId: string, revision: number): Promise<FollowupStart> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const raw = await request('/followups/' + encodeURIComponent(taskId) + '/start-assessment', http.RequestMethod.POST,
      JSON.stringify({ revision }), revision);
    const value = (JSON.parse(raw) as Envelope).data as FollowupStart;
    if (!value.assessmentId || !value.personId || value.taskId !== taskId) {
      throw new Error('复筛返回资料不完整，请刷新任务后重试。');
    }
    return value;
  }

  static voiceCookie(): string {
    return cookie;
  }

  static voiceStreamUrl(path: string): string {
    if (!path.startsWith('/api/v1/voice/')) throw new Error('语音通道地址无效。');
    return BASE.replace(/^http/, 'ws').replace(/\/api\/v1$/, '') + path;
  }

  static async voiceSession(interviewId: string, questionId: string, revision: number): Promise<VoiceSession> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    if (!(AppStorage.get<boolean>('voiceConsent') ?? false)) {
      throw new Error('请先在设置中开启本次登录的云端语音授权。');
    }
    const text = await request('/voice/config', http.RequestMethod.GET, '');
    const capabilities = (JSON.parse(text) as Envelope).data as VoiceCapabilities;
    if (!capabilities.enabled || !capabilities.asrReady) throw new Error('语音识别暂未启用，可使用文字输入。');
    const result = await request('/voice/sessions', http.RequestMethod.POST, JSON.stringify({
      interviewId: interviewId, questionId: questionId, revision: revision,
      consent: true, dialect: AppStorage.get<string>('voiceDialect') ?? '自动识别'
    }));
    return (JSON.parse(result) as Envelope).data as VoiceSession;
  }

  static async dictationSession(): Promise<VoiceSession> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    if (!(AppStorage.get<boolean>('voiceConsent') ?? false)) {
      throw new Error('请先在设置中开启本次登录的云端语音授权。');
    }
    const result = await request('/voice/dictation-sessions', http.RequestMethod.POST, JSON.stringify({
      consent: true, dialect: AppStorage.get<string>('voiceDialect') ?? '自动识别'
    }));
    return (JSON.parse(result) as Envelope).data as VoiceSession;
  }

  static async opening(interviewId: string): Promise<OpeningContent> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const text = await request('/interviews/' + encodeURIComponent(interviewId) + '/opening', http.RequestMethod.GET, '');
    const value = (JSON.parse(text) as Envelope).data as OpeningContent;
    if (!value || !value.text || !Array.isArray(value.sentences) || !value.openingKey || value.sentences.join('') !== value.text) {
      throw new Error('开场文字尚未核对成功，请重试。');
    }
    return value;
  }

  static async openingTts(context: common.UIAbilityContext, interviewId: string,
    opening: OpeningContent, sentenceIndex: number): Promise<string> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const req = http.createHttp();
    try {
      const headers = headerMap();
      headers['Idempotency-Key'] = 'opening-' + Date.now().toString() + '-' + sentenceIndex;
      const res = await req.request(BASE + '/voice/opening-tts', {
        method: http.RequestMethod.POST, header: headers,
        extraData: JSON.stringify({ interviewId: interviewId, revision: opening.revision,
          openingKey: opening.openingKey, sentenceIndex: sentenceIndex, speed: 45 }),
        connectTimeout: 15000, readTimeout: 35000, expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (res.responseCode !== 200) {
        if (res.responseCode === 409) throw new Error('开场状态已变化，请重新核对访谈。');
        throw new Error('开场合成失败，可重试或直接开始答题。');
      }
      const bytes = res.result as ArrayBuffer;
      if (bytes.byteLength === 0) throw new Error('开场合成未返回音频，请重试。');
      const path = context.cacheDir + '/opening-' + Date.now().toString() + '-' + sentenceIndex + '.mp3';
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes); } finally { fileIo.closeSync(file); }
      return path;
    } finally { req.destroy(); }
  }

  static async tts(context: common.UIAbilityContext, interviewId: string, questionId: string,
    revision: number): Promise<string> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    const text = await request('/voice/config', http.RequestMethod.GET, '');
    const capabilities = (JSON.parse(text) as Envelope).data as VoiceCapabilities;
    if (!capabilities.enabled || !capabilities.ttsReady) throw new Error('题目播报暂未启用，可直接阅读问题。');
    const req = http.createHttp();
    try {
      const headers = headerMap();
      headers['Idempotency-Key'] = 'tts-' + Date.now().toString();
      const res = await req.request(BASE + '/voice/tts', {
        method: http.RequestMethod.POST, header: headers,
        extraData: JSON.stringify({ interviewId: interviewId, questionId: questionId,
          revision: revision, speed: 50 }),
        connectTimeout: 15000, readTimeout: 35000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (res.responseCode !== 200) {
        if (res.responseCode === 409) throw new Error('问题已变化，请刷新后播报。');
        throw new Error(`题目播报请求失败（${res.responseCode}），可重试或阅读文字。`);
      }
      const bytes = res.result as ArrayBuffer;
      if (bytes.byteLength === 0) throw new Error('播报没有返回音频，请重试。');
      const path = context.cacheDir + '/question-' + Date.now().toString() + '.mp3';
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes); } finally { fileIo.closeSync(file); }
      return path;
    } finally { req.destroy(); }
  }

  static async retryInterview(id: string, revision: number): Promise<boolean> {
    if (!await Api.ensureSession()) throw new Error('登录已失效，请重新登录。');
    await request(`/interviews/${id}/retry`, http.RequestMethod.POST, JSON.stringify({ revision: revision }), revision);
    return true;
  }

  static async followups(): Promise<Object | null> {
    try {
      const ok = await Api.ensureSession();
      if (!ok) return null;
      const text = await request('/followups?view=due&limit=20', http.RequestMethod.GET, '');
      return (JSON.parse(text) as Envelope).data;
    } catch (e) {
      return null;
    }
  }

  static async closeCare(id: string, revision: number, reason: string): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const req = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'close-' + Date.now().toString();
    headers['If-Match'] = '"' + revision.toString() + '"';
    try {
      const res = await req.request(BASE + '/care-cases/' + id + '/close', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({ revision: revision, reason: reason }),
        expectDataType: http.HttpDataType.STRING
      });
      return res.responseCode === 200;
    } catch (e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  static async notifications(): Promise<Object | null> {
    try {
      const ok = await Api.ensureSession();
      if (!ok) return null;
      const text = await request('/notifications?limit=20', http.RequestMethod.GET, '');
      return (JSON.parse(text) as Envelope).data;
    } catch (e) {
      return null;
    }
  }

  static async markNotificationRead(id: string, activationVersion: number): Promise<boolean> {
    const ok = await Api.ensureSession();
    if (!ok) return false;
    const req = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (cookie.length > 0) headers['Cookie'] = cookie;
    if (csrf.length > 0) headers['X-CSRF-Token'] = csrf;
    headers['Idempotency-Key'] = 'rd-' + Date.now().toString();
    try {
      const res = await req.request(BASE + '/notifications/' + id + '/read', {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({ activationVersion: activationVersion }),
        expectDataType: http.HttpDataType.STRING
      });
      return res.responseCode === 200;
    } catch (e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  static async careCases(): Promise<Object | null> {
    try {
      const ok = await Api.ensureSession();
      if (!ok) return null;
      const text = await request('/care-cases?limit=20', http.RequestMethod.GET, '');
      return (JSON.parse(text) as Envelope).data;
    } catch (e) {
      return null;
    }
  }

  static async followupEnabled(): Promise<boolean> {
    try {
      const ok = await Api.ensureSession();
      if (!ok) return false;
      const text = await request('/followup-capabilities', http.RequestMethod.GET, '');
      const env = JSON.parse(text) as Envelope;
      const data = env.data as Record<string, Object>;
      return data['enabled'] === true;
    } catch (e) {
      return false;
    }
  }
}
