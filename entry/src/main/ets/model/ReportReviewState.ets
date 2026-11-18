import { TopicSession } from './TopicInterviewState';

export interface ReportReviewState {
  editable: boolean;
  confirmed: boolean;
  canManageItems: boolean;
  message: string;
}

export function reportReviewState(session: TopicSession): ReportReviewState {
  const state: ReportReviewState = { editable: false, confirmed: false, canManageItems: false, message: '' };
  if (session.scale !== 'TOPIC-INTERVIEW' || session.scoringEnabled !== false || session.workflow !== 'automatic') {
    state.message = '此入口仅支持七话题访谈报告。';
    return state;
  }
  if (session.safety.blocked || session.paused) {
    state.message = session.safety.blocked ? '存在未解决的安全事项，请先完成专业处置。' : '访谈已暂停，请先恢复。';
    return state;
  }
  if (['queued', 'processing'].indexOf(session.automation.status) >= 0) {
    state.message = '报告正在处理，请稍后刷新。';
    return state;
  }
  const ready = ['ready', 'edited'].indexOf(session.summary.status) >= 0 && session.summary.draft.trim().length > 0;
  if (!session.completed || !ready) {
    state.message = '请完成访谈并生成有效报告后再复核。';
    return state;
  }
  state.confirmed = session.summary.confirmedText !== null && session.summary.confirmedText === session.summary.draft &&
    session.confirmedRevision === session.revision;
  state.editable = !session.archived && session.precheckDone && session.canConfirm === true;
  state.canManageItems = state.confirmed || session.archived;
  state.message = session.archived ? '报告已归档，只读查看；跟进事项独立记录。' :
    (state.confirmed ? '报告已人工确认，可继续核对跟进事项。' : '请核对原话、来源和报告，再明确确认。');
  return state;
}

export interface FollowupItemEvidence { answerId: string; quote: string; }
export interface FollowupItem {
  id: string;
  revision: number;
  assessmentId: string;
  title: string;
  reason: string;
  action: string;
  assignee: string;
  evidence: FollowupItemEvidence[];
  state: string;
  stale: boolean;
}
export interface FollowupItemsView { status: string; items: FollowupItem[]; }

export function canDecideItem(item: FollowupItem, decision: string): boolean {
  if (item.stale) return false;
  if (decision === 'confirm') return item.state === 'draft';
  if (decision === 'dismiss') return ['draft', 'confirmed', 'following'].indexOf(item.state) >= 0;
  if (decision === 'following' || decision === 'resolved') return ['confirmed', 'following'].indexOf(item.state) >= 0;
  return false;
}
