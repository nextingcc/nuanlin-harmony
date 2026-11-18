const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function load() {
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/JournalMemo.ets'), 'utf8')
    .replace(/\r/g, '');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, console });
  return exports;
}

function memoText(overrides = {}) {
  const item = {
    title: '给情绪留个位置',
    text: '先留意它像什么。',
    steps: ['坐下', '命名情绪', '慢慢呼吸'],
    category: '正念练习',
    createdAt: '2026-11-17T01:00:00+08:00',
    source: 'Doing What Matters in Times of Stress (2020).txt',
    page: 128,
    section: 'Document body',
    ...overrides
  };
  const { suggestionMemoText } = load();
  return suggestionMemoText(item.title, item.text, item.steps, item.category, item.createdAt,
    item.source, item.page, item.section);
}

test('suggestion memo text keeps title, steps and citation', () => {
  const text = memoText();
  assert.match(text, /^心情调节建议 · 给情绪留个位置/);
  assert.ok(text.includes('先留意它像什么。'));
  assert.ok(text.includes('坐下\n命名情绪\n慢慢呼吸'));
  assert.ok(text.includes('分类：正念练习'));
  assert.ok(text.includes('参考资料：Doing What Matters in Times of Stress (2020).txt · 第128页 · Document body'));
});

test('memo text omits page and section when absent', () => {
  const text = memoText({ page: 0, section: '' });
  assert.ok(text.includes('参考资料：Doing What Matters in Times of Stress (2020).txt\n') ||
    text.endsWith('参考资料：Doing What Matters in Times of Stress (2020).txt'));
  assert.ok(!text.includes('第undefined页'));
});

test('memo id is stable and prefixed for duplicate detection', () => {
  const { suggestionMemoId } = load();
  assert.equal(suggestionMemoId('fictional-1'), 'advice-fictional-1');
  assert.equal(suggestionMemoId('x'), 'advice-x');
});
