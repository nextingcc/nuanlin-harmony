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
  }).outputText, { exports, Date, Math, isNaN, parseFloat, console });
  return exports;
}

test('breakpoints follow the HarmonyOS sm / md / lg scale', () => {
  const { Layout } = load('Layout');
  assert.equal(Layout.isWide(599), false);
  assert.equal(Layout.isWide(600), true);
  assert.equal(Layout.columns(390), 1);
  assert.equal(Layout.columns(600), 2);
  assert.equal(Layout.columns(840), 3);
});

test('layout width parsing ignores invalid area widths', () => {
  const { Layout } = load('Layout');
  assert.equal(Layout.parseWidth('393'), 393);
  assert.equal(Layout.parseWidth(393.5), 393.5);
  assert.equal(Layout.parseWidth('abc'), 0);
  assert.equal(Layout.parseWidth(-1), 0);
  assert.equal(Layout.cardRatio(2, 2.4), '48.8%');
});

test('daily reminders only fire once per day', () => {
  const { reminderDay, shouldNotify } = load('ReminderRules');
  assert.equal(reminderDay(new Date(2026, 10, 16)), '2026-11-16');
  assert.equal(shouldNotify('', '2026-11-16'), true);
  assert.equal(shouldNotify('2026-11-16', '2026-11-16'), false);
  assert.equal(shouldNotify('2026-11-15', '2026-11-16'), true);
});

test('reminder summary separates follow-ups and priority care', () => {
  const { reminderSummary, reminderCountText, reminderTag } = load('ReminderRules');
  assert.equal(reminderSummary(0, 0), '今天没有到期提醒');
  assert.equal(reminderSummary(2, 0), '回访 2 条 今天到期');
  assert.equal(reminderSummary(0, 3), '重点关怀 3 条 今天到期');
  assert.equal(reminderSummary(2, 3), '回访 2 条 · 重点关怀 3 条 今天到期');
  assert.equal(reminderCountText(5), '5 件');
  assert.equal(reminderCountText(0), '0 件');
  assert.equal(reminderTag(2), '有 2 件待处理');
});
