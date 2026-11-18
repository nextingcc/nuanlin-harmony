import { Api } from './Api';
import { isMemoOverdue, readMemoItems } from './MemoReminders';

export interface StaffReminder {
  id: string;
  title: string;
  tag: string;
  detail: string;
  route: string;
  activationVersion?: number;
  read?: boolean;
}

interface ReminderPerson {
  name: string;
}

interface DueFollowup {
  id: string;
  kind: string;
  plannedDate: string;
  person?: ReminderPerson;
}

interface CareReminder {
  id: string;
  stage: number;
  dueAt?: string;
  person?: ReminderPerson;
  activationVersion: number;
  read: boolean;
}

interface FollowupPage {
  items: DueFollowup[];
}

interface CareReminderPage {
  items: CareReminder[];
}

export interface ServerReminders {
  items: StaffReminder[];
  unavailable: boolean;
}

export function memoReminders(now: string): StaffReminder[] {
  return readMemoItems().filter(item => isMemoOverdue(item, now))
    .sort((first, second) => first.dueAt.localeCompare(second.dueAt))
    .map((item): StaffReminder => ({
      id: item.id, title: item.text, tag: '备忘录超时', detail: `计划时间 ${item.dueAt}`, route: 'pages/Memo'
    }));
}

export async function loadServerReminders(): Promise<ServerReminders> {
  const responses = await Promise.all([Api.followups(), Api.notifications()]);
  const due = responses[0];
  const care = responses[1];
  const careItems = (care as CareReminderPage | null)?.items ?? [];
  const followups = (due as FollowupPage | null)?.items ?? [];
  const items: StaffReminder[] = careItems.map((item): StaffReminder => ({
    id: item.id, title: item.person?.name ?? '居民',
    tag: item.stage === 7 ? '重点关怀 · 未就医' : '重点关怀 · 就医待核实',
    detail: `第 ${item.stage} 天提醒${item.dueAt ? ` · 到期 ${item.dueAt.slice(0, 10)}` : ''}`,
    route: 'pages/CareList', activationVersion: item.activationVersion, read: item.read
  }));
  for (const item of followups) {
    items.push({
      id: item.id, title: item.person?.name ?? '居民', tag: '到期回访',
      detail: `${item.kind === 'periodic_rescreen' ? '阶段复筛' : '常规回访'}${item.plannedDate ? ` · 计划 ${item.plannedDate}` : ''}`,
      route: 'pages/FollowupQueue'
    });
  }
  return { items: items, unavailable: due === null || care === null };
}
