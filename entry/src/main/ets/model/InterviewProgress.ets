import { TopicAutomation, TopicRecord, TopicSession, TopicSummary, LiteratureEvent } from './TopicInterviewState';

export interface InterviewEvent {
  type: string;
  interviewId: string;
  streamId: string;
  seq: number;
  jobId?: string | null;
  basedOnRevision?: number;
  revision?: number;
  automation?: TopicAutomation;
  session?: TopicSession;
  target?: string;
  text?: string;
  preview?: string;
}

export class InterviewEventParser {
  private buffer: string = '';

  feed(chunk: string, receive: (event: InterviewEvent) => void): void {
    const frames = (this.buffer + chunk).split(/\r?\n\r?\n/);
    this.buffer = frames.pop() ?? '';
    if (this.buffer.length > 8000000) throw new Error('访谈进度事件过长。');
    for (const frame of frames) {
      let type = '';
      const data: string[] = [];
      for (const line of frame.split(/\r?\n/)) {
        if (line.startsWith('event:')) type = line.slice(6).trim();
        if (line.startsWith('data:')) data.push(line.slice(5).trimStart());
      }
      if (!['snapshot', 'stage', 'delta', 'committed', 'failed', 'interrupted'].includes(type) || data.length === 0) continue;
      const event = JSON.parse(data.join('\n')) as InterviewEvent | null;
      if (event !== null && event.type === type && typeof event.streamId === 'string' &&
        Number.isInteger(event.seq) && event.seq >= 0) receive(event);
    }
  }
}

const labels: Map<string, string> = new Map<string, string>([
  ['initial', '准备本话题首问'], ['review', '分析本轮回答'], ['memory', '整理本轮回答要点'],
  ['necessity', '判断是否需要追问'], ['question', '组织访谈问题'], ['recall', '核对历史与回访参考'],
  ['validating', '核对结果与原话依据'], ['saving', '保存本轮结果'], ['summary', '整理访谈报告']
]);

export function analysisSteps(job: TopicAutomation): string[] {
  const steps: string[] = [];
  const current = job.progress?.step ?? '';
  const active = job.status === 'processing' || job.status === 'queued';
  for (const item of job.progress?.completedSteps ?? []) {
    const label = labels.get(item.step);
    if (label && !(active && item.step === current) && !steps.includes(label)) steps.push(label);
  }
  const lines = steps.slice(-4).map((step: string) => '✓ ' + step);
  if (active) {
    const label = labels.get(current) ?? labels.get(job.stage ?? '') ?? '分析本轮回答';
    lines.push(job.status === 'queued' ? '· 等待开始' + label : '· 正在' + label + '…');
  }
  return lines;
}

export function analysisSummary(session: TopicSession): string[] {
  const current = session.topics.find((topic: TopicRecord) => topic.id === session.currentTopic);
  if (current?.descriptionStatus !== 'stale' && current?.review?.topicDecision) return describe(current);
  const previous = session.topics.slice(0, session.current).reverse().find((topic: TopicRecord) =>
    topic.descriptionStatus !== 'stale' && !!topic.review?.topicDecision);
  return previous ? ['上一话题 · ' + previous.name, ...describe(previous)] : [];
}

function describe(topic: TopicRecord): string[] {
  const lines: string[] = [];
  for (const finding of topic.structuredState?.manifestation ?? []) {
    if (finding.kind !== 'reported' || !finding.statement.trim()) continue;
    const text = '回答要点：' + finding.statement.trim();
    if (!lines.includes(text)) lines.push(text);
    if (lines.length === 2) break;
  }
  const decision = topic.review?.topicDecision;
  if (decision?.status === 'needs_more' && decision.nextGap) {
    lines.push('还需了解：' + decision.nextGap.aspect);
    lines.push('追问依据：' + decision.nextGap.reason);
  } else if (decision?.status === 'sufficient') {
    lines.push('本话题已有足够信息，可以继续下一话题。');
  }
  return lines;
}

export function retrievalSteps(job: TopicAutomation): string[] {
  const phases: Map<string, string> = new Map<string, string>([
    ['planning', '整理检索问题'], ['search', '检索文献'], ['merge', '合并资料'],
    ['rerank', '排序资料'], ['coverage', '核对适用范围'], ['source', '文献来源'], ['complete', '检索结束']
  ]);
  const states: Map<string, string> = new Map<string, string>([
    ['started', '进行中'], ['completed', '已完成'], ['ok', '已完成'], ['partial', '部分证据可用'],
    ['empty', '暂无相关资料'], ['unavailable', '暂不可用'], ['disabled', '未启用'], ['missing', '证据不足']
  ]);
  return (job.progress?.ragEvents ?? []).slice(-16).map((event: LiteratureEvent) => {
    let line = (phases.get(event.phase) ?? '处理资料') + ' · ' + (states.get(event.state) ?? '已更新');
    if (event.query) line += '\n检索词：' + event.query;
    if (typeof event.count === 'number') line += ' · ' + event.count + ' 条';
    if (event.source?.document) line += '\n' + event.source.document +
      (event.source.page ? ' · 第 ' + event.source.page + ' 页' : '');
    return line;
  });
}

export function reportSources(summary: TopicSummary): string[] {
  const lines: string[] = [];
  if (summary.status === 'stale') return lines;
  if (summary.ragStatus === 'partial') lines.push('部分问题的文献证据不足，请结合原话和来源复核。');
  for (const source of summary.knowledgeReferences ?? []) {
    lines.push('[' + (source.id ?? '文献') + '] ' + (source.document ?? '文献资料') +
      (source.page ? ' · 第 ' + source.page + ' 页' : '') + (source.section ? '\n' + source.section : '') +
      (/^https?:\/\//.test(source.url ?? '') ? '\n' + source.url : ''));
  }
  for (const source of summary.recall?.usedReferences ?? []) {
    lines.push('[' + source.id + '] 历史记录 · ' + (source.startedAt?.slice(0, 10) ?? '日期待核实') +
      (source.topicName ? ' · ' + source.topicName : ''));
  }
  return lines;
}
