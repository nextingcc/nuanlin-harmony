import { Api } from './Api';
import { TopicSession } from './TopicInterviewState';

export interface QueuePerson {
  id?: string;
  name: string;
  age: number;
  gender: string | null;
  community: string | null;
}

export interface QueueTask {
  id: string;
  personId?: string;
  kind?: string;
  revision: number;
  state: string;
  status: string;
  dueAt: string;
  plannedDate: string;
  activeAssessmentId: string | null;
  blockedReason?: string;
  person: QueuePerson;
}

export interface QueueSelection {
  id: string;
  name: string;
  age: number;
  gender: string;
  community: string;
  status: string;
}

export function queueSelection(task: QueueTask): QueueSelection {
  const id = task.personId || task.person.id || '';
  if (!id || (task.personId && task.person.id && task.personId !== task.person.id)) {
    throw new Error('任务与人员资料不一致，请刷新名单后重试。');
  }
  return { id, name: task.person.name, age: task.person.age, gender: task.person.gender ?? '',
    community: task.person.community ?? '', status: task.kind === 'periodic_rescreen' ? '周期复筛' : '回访任务' };
}

export function canRecordContact(task: QueueTask): boolean {
  return contactRecordAllowed(task.kind, task.activeAssessmentId);
}

export function contactRecordAllowed(kind: string | undefined, activeAssessmentId: string | null | undefined): boolean {
  return kind !== 'periodic_rescreen' && !activeAssessmentId;
}

export function displayFollowupTime(value: string): string {
  if (!value) return '';
  const time = new Date(value).getTime();
  if (!Number.isFinite(time)) return '';
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return new Date(time).toISOString().slice(0, 10) === value ? value + '（北京时间）' : '';
  }
  return new Date(time + 8 * 60 * 60 * 1000).toISOString().slice(0, 16).replace('T', ' ') + '（北京时间）';
}

function requireSession(session: TopicSession | null, id: string): TopicSession {
  if (!session || session.id !== id) throw new Error('无法核对当前访谈，请重新读取。');
  return session;
}

// 人工操作入口：风险确认和归档是两个有版本保护的步骤，不从访谈自动推进触发。
export async function confirmRiskAndArchive(id: string, level: string): Promise<TopicSession> {
  const before = requireSession(await Api.getInterview(id) as TopicSession | null, id);
  if (!['none', 'low', 'medium', 'high'].includes(level)) throw new Error('请选择明确的人工风险等级。');
  if (before.safety.blocked || before.paused) throw new Error('请先处理安全事项或恢复访谈。');
  if (before.canConfirm === false) throw new Error('访谈仍有未明确或拒答项，请复核报告并安排补充回访，不能直接确认完整筛查风险。');
  await Api.confirmRisk(id, before.revision, level, '工作人员在人员档案核对并确认风险等级');
  const updated = requireSession(await Api.getInterview(id) as TopicSession | null, id);
  if (!before.archived) {
    if (updated.archived || !updated.completed || updated.safety.blocked || updated.paused ||
      updated.summary.status === 'stale') {
      throw new Error('风险已提交，但访谈状态已变化，请刷新后重新确认；本次未继续归档。');
    }
    await Api.archiveReviewedInterview(id, updated.revision);
  }
  const saved = requireSession(await Api.getInterview(id) as TopicSession | null, id);
  if (!saved.archived) throw new Error('暂未确认归档成功，请刷新档案核对，不要重复提交。');
  return saved;
}
