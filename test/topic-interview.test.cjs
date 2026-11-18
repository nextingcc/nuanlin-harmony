const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function loadState() {
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/TopicInterviewState.ets'), 'utf8')
    .replace(/\r/g, '');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, Date, Math, JSON, Array, console });
  return exports;
}

function session(overrides = {}) {
  const topics = Array.from({ length: 7 }, (_, i) => ({
    id: 't' + i,
    name: '话题' + (i + 1),
    phase: '',
    status: i < 3 ? 'done' : 'open',
    question: i === 3 ? '最近睡得好吗' : null,
    turns: []
  }));
  return {
    id: 's1', revision: 1, scale: 'TOPIC-INTERVIEW', workflow: 'automatic', scoringEnabled: false,
    current: 3, currentTopic: 't3', currentQuestion: { id: 'q1', topicId: 't3', text: '最近睡得好吗' },
    topics, precheckDone: true, completed: false, archived: false, paused: false,
    safety: { blocked: false },
    automation: { status: 'idle' },
    summary: { status: 'none', draft: '', confirmedText: null },
    ...overrides
  };
}

test('topic view counts finished topics and keeps the current one', () => {
  const { topicView } = loadState();
  const view = topicView(session());
  assert.equal(view.total, 7);
  assert.equal(view.done, 3);
  assert.equal(view.topicName, '话题4');
  assert.equal(view.question, '最近睡得好吗');
  assert.equal(view.report, '');
  assert.equal(view.completed, false);
});

test('archived or old sessions are read-only and explained', () => {
  const { topicView } = loadState();
  const archived = topicView(session({ archived: true }));
  assert.equal(archived.retry, false);
  assert.equal(archived.pending, false);
  assert.ok(archived.message.length > 0);

  const legacy = topicView(session({ scale: 'SCL-90' }));
  assert.equal(legacy.total, 7);
  assert.ok(legacy.message.includes('旧版'));
});

test('report markdown is flattened without tables or emphasis', () => {
  const { readableTopicReport } = loadState();
  const text = readableTopicReport('# 访谈报告\n**重点**：睡眠\n| 项目 | 结果 |\n| --- | --- |\n| 睡眠 | 一般 |');
  assert.equal(text, '访谈报告\n重点：睡眠\n睡眠：一般');
});
