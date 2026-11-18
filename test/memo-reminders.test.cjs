const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function load(name) {
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model', name + '.ets'), 'utf8')
    .replace(/\r/g, '');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, Date, Math, isNaN, parseFloat, console, AppStorage: { get: () => undefined } });
  return exports;
}

test('memo date and minute keep two-digit fields', () => {
  const { memoDate, memoMinute } = load('MemoReminders');
  assert.equal(memoDate(new Date(2026, 0, 5)), '2026-01-05');
  assert.equal(memoMinute(new Date(2026, 0, 5, 9, 3)), '2026-01-05 09:03');
});

test('memos become overdue only at the selected minute and while incomplete', () => {
  const { isMemoOverdue } = load('MemoReminders');
  const item = { id: 'm1', text: '虚构待办', done: false, dueAt: '2026-11-16 09:30' };
  assert.equal(isMemoOverdue(item, '2026-11-16 09:29'), false);
  assert.equal(isMemoOverdue(item, '2026-11-16 09:30'), true);
  assert.equal(isMemoOverdue(item, '2026-11-16 10:00'), true);
  assert.equal(isMemoOverdue({ ...item, done: true }, '2026-11-16 10:00'), false);
  assert.equal(isMemoOverdue({ ...item, dueAt: '' }, '2026-11-16 10:00'), false);
  assert.equal(isMemoOverdue({ ...item, dueAt: '2026-11-16' }, '2026-11-16 10:00'), false);
});
