const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');
const theme = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/Theme.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, { exports: theme, AppStorage: { get: () => false } });

function controller(name, api) {
  let dialog;
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages', name + '.ets'), 'utf8')
    .replace(/\r/g, '').split('  @Builder')[0]
    .replace('@Entry\n@Component\nstruct ' + name, 'export class ' + name).replaceAll('@State ', '')
    .replace(/@StorageProp\('[^']*'\)\s*/g, '') + '\n}';
  const exports = {};
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    exports, Date, Promise, Math, Error,
    $r: value => value,
    setInterval: () => 1, clearInterval() {}, setTimeout: () => 1, clearTimeout() {},
    CanvasRenderingContext2D: class {}, RenderingContextSettings: class {}, Scroller: class {},
    Curve: { EaseInOut: 'ease' },
    AlertDialog: { show(options) { dialog = options; } },
    require: name => name === '../model/Api' ? { Api: api } : name === '../model/Voice' ? { VoiceRecorder: class { cancel() {} } } :
      name === '../model/Theme' ? theme :
      name === '../model/MemoReminders' ? { readMemoItems: () => [] } : { promptAction: { showToast() {} } }
  });
  return { page: new exports[name](), dialog: () => dialog };
}

test('weekly review follows the diary date rather than the previously browsed week', async () => {
  const requests = [];
  const { page } = controller('Journal', { async journal(start, end) { requests.push([start, end]); return []; } });
  page.selected = new Date(2026, 10, 16);
  page.week = new Date(2026, 10, 9);
  page.setTab(2);
  await Promise.resolve();
  assert.equal(page.week.getDate(), 16);
  assert.deepEqual(requests, [['2026-11-16', '2026-11-22']]);
});

test('unsaved diary is saved before leaving for the weekly review and failed saves retain input', async () => {
  const writes = [];
  let fail = false;
  const { page, dialog } = controller('Journal', {
    async saveJournal(day, diary) { if (fail) throw new Error('模拟保存失败'); writes.push([day, diary]); },
    async journal() { return [{ date: '2026-11-16', diary: '新写的虚构日记', mood: '', comfort: null }]; }
  });
  page.selected = new Date(2026, 10, 16);
  page.savedDraft = '之前的虚构日记';
  page.drawChart = () => {};
  page.draft = '新写的虚构日记';
  page.setTab(2);
  assert.equal(page.tab, 0);
  assert.equal(writes.length, 0);
  await dialog().secondaryButton.action();
  assert.deepEqual(writes, [['2026-11-16', '新写的虚构日记']]);
  assert.equal(page.tab, 2);
  await page.load();
  page.tab = 0;
  page.draft = '另一篇尚未保存的虚构日记';
  fail = true;
  page.setTab(2);
  await dialog().secondaryButton.action();
  assert.equal(page.tab, 0);
  assert.equal(page.draft, '另一篇尚未保存的虚构日记');
  assert.match(page.error, /保存失败/);
});
