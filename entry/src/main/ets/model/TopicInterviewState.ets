export interface TopicTurn {
  id: string;
  question: string;
  verbatim: string;
}
export interface TopicRecord {
  id: string;
  name: string;
  phase: string;
  status: string;
  question: string | null;
  turns: TopicTurn[];
  descriptionStatus?: string;
  structuredState?: TopicDescription | null;
  review?: TopicReview | null;
}
export interface TopicDescription { manifestation: TopicFinding[]; }
export interface TopicFinding { kind: string; statement: string; }
export interface TopicReview { topicDecision?: TopicDecision; }
export interface TopicDecision { status: string; nextGap?: TopicGap | null; }
export interface TopicGap { aspect: string; reason: string; }
export interface TopicQuestion {
  id: string;
  topicId: string;
  text: string;
}
export interface TopicAutomation {
  status: string;
  stage?: string;
  jobId?: string | null;
  basedOnRevision?: number;
  progress?: TopicProgress;
  error?: TopicFailure | null;
}
export interface TopicProgress {
  step?: string;
  completedSteps?: TopicProgressStep[];
  ragEvents?: LiteratureEvent[];
}
export interface LiteratureSource { id?: string; document?: string; page?: number | null; section?: string; url?: string; }
export interface LiteratureEvent { phase: string; state: string; query?: string; count?: number; source?: LiteratureSource; }
export interface HistorySource { id: string; topicName?: string; startedAt?: string; }
export interface ReportRecall { status?: string; usedReferences?: HistorySource[]; }
export interface TopicProgressStep { step: string; }
export interface TopicFailure { message: string; }
export interface TopicSafety { blocked: boolean; }
export interface TopicSummary {
  status: string;
  draft: string;
  confirmedText: string | null;
  knowledgeReferences?: LiteratureSource[];
  ragStatus?: string;
  recall?: ReportRecall;
}
export interface TopicSession {
  supplementalFollowupId?: string;
  openingText?: string;
  openingSentences?: string[];
  id: string;
  nextFollowupId?: string | null;
  canConfirm?: boolean;
  confirmedRevision?: number | null;
  revision: number;
  scale: string;
  workflow: string;
  scoringEnabled: boolean;
  current: number;
  currentTopic: string | null;
  currentQuestion: TopicQuestion | null;
  topics: TopicRecord[];
  precheckDone: boolean;
  completed: boolean;
  archived: boolean;
  paused: boolean;
  safety: TopicSafety;
  automation: TopicAutomation;
  summary: TopicSummary;
}
export interface TopicView {
  total: number;
  done: number;
  current: number;
  topicId: string;
  questionId: string;
  question: string;
  topicName: string;
  pending: boolean;
  retry: boolean;
  canAnswer: boolean;
  completed: boolean;
  report: string;
  message: string;
}

// Present the web report's Markdown as readable native text. Keep the report
// data unchanged and never interpret report contents as executable HTML.
export function readableTopicReport(markdown: string): string {
  const lines: string[] = [];
  for (const raw of markdown.split('\n')) {
    let line = raw.trim();
    if (/^\|?[\s:-]+(?:\|[\s:-]+)+\|?$/.test(line)) continue;
    if (line.startsWith('|') && line.endsWith('|')) {
      const cells: string[] = line.slice(1, -1).split('|').map((cell: string) => cell.trim());
      if (cells.length > 1 && cells[0] === '项目' && cells[1].indexOf('结果') >= 0) continue;
      line = cells.length > 1 ? cells[0] + '：' + cells.slice(1).join('；') : cells[0];
    }
    line = line.replace(/^#{1,6}\s+/, '').replace(/\*\*(.*?)\*\*/g, '$1');
    lines.push(line);
  }
  return lines.join('\n');
}

// The backend owns progression. A follow-up question is not another topic.
export function topicView(session: TopicSession): TopicView {
  const view: TopicView = {
    total: 7, done: 0, current: 0, topicId: '', questionId: '', question: '',
    topicName: '心理关怀话题访谈', pending: false, retry: false,
    canAnswer: false, completed: false, report: '', message: ''
  };
  if (session.scale !== 'TOPIC-INTERVIEW' || session.scoringEnabled !== false ||
      session.topics.length !== 7 || session.workflow !== 'automatic') {
    view.message = '这是旧版访谈，请返回人员档案新建七话题访谈；原记录仍保留。';
    return view;
  }
  view.done = session.topics.filter((t: TopicRecord) => t.status !== 'open').length;
  view.current = session.current;
  view.completed = session.completed;
  view.pending = ['queued', 'processing'].indexOf(session.automation.status) >= 0;
  view.retry = ['failed', 'interrupted'].indexOf(session.automation.status) >= 0;
  const current = session.topics.find((t: TopicRecord) => t.id === session.currentTopic);
  if (current !== undefined) {
    view.topicId = current.id;
    view.topicName = current.name;
    view.question = current.question ?? '';
  }
  if (session.summary.status !== 'stale') {
    view.report = session.summary.confirmedText ||
      (['ready', 'edited'].indexOf(session.summary.status) >= 0 ? session.summary.draft : '');
  }
  if (session.archived || session.safety.blocked || session.paused) {
    view.retry = false;
    view.pending = false;
    view.message = session.archived ? '此访谈已归档，只读展示。' :
      (session.safety.blocked ? '访谈已因安全关注中断，请先完成安全处置。' : '访谈已暂停，请在工作台恢复后继续。');
    return view;
  }
  if (!session.precheckDone) {
    view.retry = false;
    view.message = '请先点击“开始前确认”，核实访谈同意、安全与沟通条件。';
    return view;
  }
  if (view.pending) {
    const hasAnswers = session.topics.some((t: TopicRecord) => t.turns.length > 0);
    view.message = session.completed ? '七个话题已结束，正在生成访谈报告…' :
      (hasAnswers ? '回答已保存，正在整理并准备追问或下一话题…' : '正在准备访谈问题，请稍候…');
    return view;
  }
  if (view.retry) {
    view.message = session.automation.error?.message || '处理暂未完成，已保存的回答不用重复提交，请重试处理。';
    return view;
  }
  if (session.completed) {
    view.message = view.report.length > 0 ? '访谈报告已生成，待复核。' : '七个话题已结束，报告暂未返回，可刷新状态。';
    return view;
  }
  const q = session.currentQuestion;
  if (current !== undefined && current.phase === 'question' && q !== null &&
      q.topicId === current.id && q.id.length > 0 && q.text.trim().length > 0) {
    view.questionId = q.id;
    view.question = q.text;
    view.canAnswer = true;
  } else {
    view.message = '正在等待下一问，请刷新状态；不会自动确认或计分。';
  }
  return view;
}
