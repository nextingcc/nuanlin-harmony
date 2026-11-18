const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');
const root = path.join(__dirname, '../entry/src/main/ets');

function load(file, modules = {}, globals = {}, component = '') {
  let source = fs.readFileSync(path.join(root, file), 'utf8');
  if (component) {
    source = source.slice(0, source.indexOf('  build()')) + '}';
    source = source.replace(/@Entry\s*/g, '').replace(/@Component\s*/g, '').replace(/@State\s*/g, '')
      .replace(/@Builder\s*/g, '')
      .replace(/@StorageProp\('[^']*'\)\s*/g, '').replace('struct ' + component, 'export class ' + component);
  }
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, ...globals, require: name => modules[name] ?? {} });
  return exports;
}

const reportRules = load('model/ReportReviewState.ets');
const snapshot = (patch = {}) => ({ id: 'assessment', revision: 10, scale: 'TOPIC-INTERVIEW', workflow: 'automatic',
  scoringEnabled: false, completed: true, canConfirm: true, precheckDone: true, archived: false, paused: false,
  safety: { blocked: false }, automation: { status: 'idle' }, confirmedRevision: 10,
  summary: { status: 'ready', draft: '人工已复核的虚构报告', confirmedText: '人工已复核的虚构报告' }, ...patch });

function workflow(api = {}) {
  return load('model/RescreenWorkflow.ets', { './Api': { Api: api }, './ReportReviewState': reportRules });
}

const task = (patch = {}) => ({ id: 'task', personId: 'person', kind: 'periodic_rescreen', revision: 2,
  state: 'due', activeAssessmentId: null, person: { id: 'person', name: '虚构人员', age: 72,
    gender: null, community: null }, ...patch });

function queue(api) {
  const stored = {}, routes = [];
  const { FollowupQueue } = load('pages/FollowupQueue.ets', {
    '../model/Api': { Api: api }, '../model/RescreenWorkflow': workflow(),
    '@kit.ArkUI': { router: { pushUrl: value => routes.push(value) } }
  }, { AppStorage: { setOrCreate(key, value) { stored[key] = value; } } }, 'FollowupQueue');
  return { page: new FollowupQueue(), stored, routes };
}

test('queue preserves real person identity and rejects contradictory or missing IDs', () => {
  const rules = workflow();
  assert.equal(rules.queueSelection(task()).id, 'person');
  assert.equal(rules.queueSelection(task()).gender, '');
  assert.throws(() => rules.queueSelection(task({ personId: 'other' })), /不一致/);
  assert.throws(() => rules.queueSelection(task({ personId: '', person: { name: '虚构', age: 72 } })), /不一致/);
  assert.equal(rules.contactRecordAllowed('periodic_rescreen', null), false);
  assert.equal(rules.contactRecordAllowed('manual', 'active-session'), false);
  assert.equal(rules.contactRecordAllowed('manual', null), true);
});

test('follow-up deadlines display in Beijing time independently of device timezone', () => {
  const rules = workflow();
  assert.equal(rules.displayFollowupTime('2027-05-15T16:00:00Z'), '2027-05-16 00:00（北京时间）');
  assert.equal(rules.displayFollowupTime('2027-05-16T00:00:00+08:00'), '2027-05-16 00:00（北京时间）');
  assert.equal(rules.displayFollowupTime('2027-05-16'), '2027-05-16（北京时间）');
  assert.equal(rules.displayFollowupTime('2027-02-31'), '');
  assert.equal(rules.displayFollowupTime('unavailable'), '');
});

test('continuing a session revalidates with the server and prevents duplicate starts', async () => {
  let resolve;
  const calls = [];
  const { page, stored, routes } = queue({ startFollowup(id, revision) {
    calls.push([id, revision]);
    return new Promise(done => { resolve = done; });
  } });
  const current = task({ activeAssessmentId: 'old-session' });
  const first = page.open(current);
  await page.open(current);
  assert.equal(calls.length, 1);
  resolve({ taskId: 'task', personId: 'person', assessmentId: 'server-session' });
  await first;
  assert.equal(stored.sessionId, 'server-session');
  assert.equal(JSON.parse(stored.selectedPerson).id, 'person');
  assert.equal(routes[0].url, 'pages/Interview');
});

test('mismatched server identity and safety blocks never navigate into an interview', async () => {
  const { page, routes } = queue({ async startFollowup() {
    return { taskId: 'task', personId: 'other', assessmentId: 'session' };
  } });
  await page.open(task());
  assert.equal(routes.length, 0);
  assert.match(page.message, /不一致/);
  await page.open(task({ blockedReason: '请先处理安全事项' }));
  assert.match(page.message, /安全事项/);
  assert.equal(routes.length, 0);
});

test('periodic records link to the exact active report instead of a contact form', () => {
  const { page, stored, routes } = queue({});
  page.record(task({ state: 'awaiting_confirmation', activeAssessmentId: 'current-assessment' }));
  assert.equal(routes[0].url, 'pages/Profile');
  assert.equal(routes[0].params.assessmentId, 'current-assessment');
  assert.equal(JSON.parse(stored.selectedPerson).id, 'person');
});

test('queue refresh failure retains prior tasks and does not imply an empty success', async () => {
  const { page } = queue({ async followups() { return null; } });
  page.tasks = [task()];
  await page.load();
  assert.equal(page.tasks.length, 1);
  assert.match(page.message, /读取失败/);
  assert.equal(page.loading, false);
});

test('unreviewed or blocked reports cannot trigger risk writes or archiving', async () => {
  for (const change of [{ confirmedRevision: null }, { paused: true }, { safety: { blocked: true } },
    { summary: { status: 'stale', draft: '旧报告', confirmedText: '旧报告' } }]) {
    const rules = workflow({ async getInterview() { return snapshot(change); } });
    await assert.rejects(rules.confirmRiskAndArchive('assessment', 'low'));
  }
});

test('archive uses the revision returned after risk confirmation and verifies saved state', async () => {
  const calls = [];
  let reads = 0;
  const rules = workflow({
    async getInterview() { return snapshot(reads++ === 0 ? {} : reads === 2 ? { revision: 11 } : { revision: 12, archived: true }); },
    async confirmRisk(id, revision, level) { calls.push(['risk', revision, level]); },
    async archiveReviewedInterview(id, revision) { calls.push(['archive', revision]); }
  });
  const saved = await rules.confirmRiskAndArchive('assessment', 'low');
  assert.deepEqual(calls, [['risk', 10, 'low'], ['archive', 11]]);
  assert.equal(saved.archived, true);
});

test('concurrent report changes stop archiving after risk submission', async () => {
  let reads = 0, archives = 0;
  const rules = workflow({ async getInterview() { return reads++ === 0 ? snapshot() : snapshot({ revision: 11,
    summary: { status: 'stale', draft: '另一工作人员已修改', confirmedText: null } }); },
  async confirmRisk() {}, async archiveReviewedInterview() { archives++; } });
  await assert.rejects(rules.confirmRiskAndArchive('assessment', 'low'), /状态已变化/);
  assert.equal(archives, 0);
});

test('archive conflict is reported without claiming the task has completed', async () => {
  const rules = workflow({ async getInterview() { return snapshot(); }, async confirmRisk() {},
    async archiveReviewedInterview() { throw new Error('任务已被替代'); } });
  await assert.rejects(rules.confirmRiskAndArchive('assessment', 'low'), /任务已被替代/);
});

test('a direct contact-form route cannot complete a periodic rescreen', async () => {
  const { FollowupRecord } = load('pages/FollowupRecord.ets', {
    '../model/Api': { Api: { async followupContext() { return {
      task: { id: 'task', revision: 4, kind: 'periodic_rescreen' }, person: { id: 'person', name: '虚构复筛' }
    }; } } }, '../model/RescreenWorkflow': workflow()
  }, {}, 'FollowupRecord');
  const page = new FollowupRecord();
  page.taskId = 'task'; page.notes = '不能用联系记录代替复筛';
  await page.verifyTask();
  assert.equal(page.verified, false);
  assert.match(page.message, /不能用联系记录/);
  await page.save();
});

test('a legacy contact record uses verified task revision and name rather than stale route data', async () => {
  const { FollowupRecord } = load('pages/FollowupRecord.ets', {
    '../model/Api': { Api: { async followupContext() { return {
      task: { id: 'task', revision: 9, kind: 'manual', state: 'due' }, person: { id: 'person', name: '真实返回的虚构人员' }
    }; } } }, '../model/RescreenWorkflow': workflow()
  }, {}, 'FollowupRecord');
  const page = new FollowupRecord();
  page.taskId = 'task'; page.revision = 1; page.personName = '旧路由名字';
  await page.verifyTask();
  assert.equal(page.verified, true);
  assert.equal(page.revision, 9);
  assert.equal(page.personName, '真实返回的虚构人员');
});
