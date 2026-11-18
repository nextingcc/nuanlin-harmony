const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');
function load(api) {
  let source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/FollowupRecord.ets'), 'utf8');
  source = source.slice(0, source.indexOf('  @Builder')) + '}';
  source = source.replace(/@Entry\s*|@Component\s*|@State\s*/g, '').replace(/@StorageProp\('[^']*'\)\s*/g, '').replace('struct FollowupRecord', 'export class FollowupRecord');
  const exports = {};
  const routes = [];
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, {
    exports, require(name) {
      if (name === '../model/Api') return { Api: api };
      if (name === '@kit.ArkUI') return { router: { replaceUrl: route => routes.push(route) }, promptAction: { showToast() {} } };
      if (name === '../model/ReminderRules') return { reminderDay: () => '2026-11-18' };
      if (name === '../model/RescreenWorkflow') return { contactRecordAllowed: () => true };
      return {};
    }
  });
  return { page: new exports.FollowupRecord(), routes };
}
test('saving sends the changed method and outcome, retaining draft after server failure', async () => {
  let sent;
  const { page, routes } = load({ async addFollowupRecord(...args) { sent = args; return false; } });
  Object.assign(page, { verified: true, taskId: 'fictional-task', revision: 8, method: '上门', outcome: 'ongoing', notes: '  fictional test  ' });
  await page.save();
  assert.deepEqual(sent, ['fictional-task', 8, '上门', 'ongoing', 'fictional test', '2026-11-18']);
  assert.equal(page.saving, false);
  assert.equal(page.method, '上门');
  assert.equal(page.outcome, 'ongoing');
  assert.equal(routes.length, 0);
});
test('empty notes and unverified tasks do not submit a contact record', async () => {
  let calls = 0;
  const { page } = load({ async addFollowupRecord() { calls++; return true; } });
  page.notes = 'fictional'; await page.save();
  page.verified = true; page.notes = ' '; await page.save();
  assert.equal(calls, 0);
  assert.ok(page.message);
});
