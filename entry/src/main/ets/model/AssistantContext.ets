import { Api, Person } from './Api';

export interface AssistantContext {
  person: Person;
  assessmentId: string;
  topic: boolean;
  completed: boolean;
  overview: string;
}

// Only authoritative reads; the assistant never changes an interview or a task.
export async function readAssistantContext(personId: string): Promise<AssistantContext> {
  if (!personId) throw new Error('请先选择居民。');
  const person = await Api.person(personId);
  if (!person || person.id !== personId) throw new Error('无法核对居民，请重新登录或选择。');
  const assessments = await Api.assessments(personId);
  const latest = assessments.length > 0 ? assessments[0] : null;
  return {
    person: person,
    assessmentId: latest ? latest.id : '',
    topic: latest !== null && latest.scale === 'TOPIC-INTERVIEW',
    completed: latest !== null && (latest.status === 'completed' || latest.status === 'archived'),
    overview: latest ? '最近记录：' + latest.startedAt.slice(0, 10) + '\n类型：' +
      (latest.scale === 'TOPIC-INTERVIEW' ? '七话题访谈' : latest.scale) + '\n状态：' +
      (latest.status === 'archived' ? '已归档' : latest.status === 'completed' ? '已完成' : '进行中') :
      '该居民暂无访谈记录。可前往档案核对资料并开始访谈。'
  };
}
