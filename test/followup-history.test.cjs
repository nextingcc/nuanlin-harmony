const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function loadPage(api) {
  let source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/FollowupList.ets'), 'utf8');
  source = source.slice(0, source.indexOf('  build()')) + '}';
  source = source.replace(/@Entry\s*/g, '').replace(/@Component\s*/g, '')
    .replace(/@State\s*/g, '').replace(/@StorageProp\('[^']*'\)\s*/g, '')
    .replace('struct FollowupList', 'export class FollowupList');
  const exports = {};
  const saved = {};
  const routes = [];
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, AppStorage: { setOrCreate: (key, value) => { saved[key] = value; } },
    require(name) {
      if (name === '../model/Api') return { Api: api };
      if (name === '../model/UserPreferences') return { readableFont: n => n, readableLineHeight: n => n };
      if (name === '../model/Theme') {
        const stub = { pageBg: '#000', surface: '#000', border: '#000', ink: '#fff', ink2: '#fff', muted: '#aaa' };
        return { Theme: stub, palette: () => stub, Palette: {} };
      }
      if (name === '@kit.ArkUI') return { router: { pushUrl: route => routes.push(route) } };
      throw new Error(`unexpected dependency ${name}`);
    } });
  return { page: new exports.FollowupList(), saved, routes };
}

const record = (id, personId = 'fictional-person') => ({ id, personId, date: '2026-11-16',
  method: '电话', outcome: 'completed', notes: '虚构测试记录' });

test('history loads real pages, deduplicates records and retains the server cursor', async () => {
  const cursors = [];
  const { page } = loadPage({
    async followupHistory(cursor) {
      cursors.push(cursor);
      return cursor ? { items: [record('a'), record('b')], nextCursor: null } :
        { items: [record('a')], nextCursor: 'next' };
    },
    async person() { return { name: '虚构人员' }; }
  });
  await page.load(false);
  assert.equal(page.names['fictional-person'], '虚构人员');
  await page.load(true);
  assert.deepEqual(cursors, ['', 'next']);
  assert.equal(page.records.length, 2);
  assert.equal(page.nextCursor, '');
});

test('history failure preserves records and pagination for retry, never inserts sample rows', async () => {
  let fail = false;
  const { page } = loadPage({
    async followupHistory() {
      if (fail) throw new Error('offline');
      return { items: [record('saved')], nextCursor: 'next' };
    },
    async person() { throw new Error('name unavailable'); }
  });
  await page.load(false);
  fail = true;
  await page.load(true);
  assert.equal(page.records[0].id, 'saved');
  assert.equal(page.nextCursor, 'next');
  assert.equal(page.retryMore, true);
  assert.match(page.message, /读取失败/);
  assert.equal(page.loading, false);
  await page.load(false);
  assert.equal(page.retryMore, false);
});

test('history opens the clicked record person and does not navigate on failed lookup', async () => {
  const person = { id: 'clicked', name: '虚构人员' };
  const { page, saved, routes } = loadPage({ async person(id) {
    return id === 'clicked' ? person : null;
  } });
  await page.openPerson('clicked');
  assert.equal(JSON.parse(saved.selectedPerson).id, 'clicked');
  assert.equal(routes[0].url, 'pages/Profile');
  await page.openPerson('missing');
  assert.equal(routes.length, 1);
  assert.match(page.message, /无法打开/);
});

test('an empty history is a successful state rather than a fabricated list', async () => {
  const { page } = loadPage({ async followupHistory() { return { items: [], nextCursor: null }; } });
  await page.load(false);
  assert.equal(page.loaded, true);
  assert.equal(page.records.length, 0);
  assert.equal(page.message, '');
});
