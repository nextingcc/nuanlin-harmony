const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function loadRules() {
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/ReminderRules.ets'), 'utf8')
    .replace(/\r/g, '');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, Date, Math, isNaN, parseFloat });
  return exports;
}

function loadCard({ cookie = 'nuanlin_session=fictional', counts = [2, 1], offline = false } = {}) {
  const rules = loadRules();
  const requests = [];
  const http = {
    RequestMethod: { GET: 'GET' },
    HttpDataType: { STRING: 'STRING' },
    createHttp() {
      return {
        async request(url) {
          if (offline) throw new Error('offline');
          requests.push(url);
          const count = counts[requests.length - 1] === undefined ? 0 : counts[requests.length - 1];
          return { responseCode: 200, result: JSON.stringify({ data: { items: Array.from({ length: count }, () => ({})) } }) };
        },
        destroy() {}
      };
    }
  };
  const preferencesModule = {
    getPreferences: async () => ({
      async get(key, fallback) { return key === 'session' ? cookie : fallback; }
    })
  };
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/CardData.ets'), 'utf8').replace(/\r/g, '');
  const exports = {};
  const secureStore = {
    isEncryptedSession: (value) => typeof value === 'string' && value.startsWith('v1.'),
    decryptSession: async (value) => 'nuanlin_session=fictional'
  };
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    exports, JSON, Array, Promise, Error, console, Object,
    require: name => name === '@kit.NetworkKit' ? { http } :
      name === '@kit.ArkData' ? { preferences: preferencesModule } :
      name === '@kit.AbilityKit' ? {} :
      name === './SecureStore' ? secureStore : rules
  });
  return { card: exports, requests };
}

test('card counts follow-ups and priority care together', async () => {
  const { card, requests } = loadCard();
  const view = await card.reminderCard({});
  assert.equal(view.count, '3 件');
  assert.equal(view.detail, '回访 2 条 · 重点关怀 1 条 今天到期');
  assert.equal(requests.length, 2);
  assert.ok(requests[0].includes('/followups?view=due'));
  assert.ok(requests[1].includes('/care-cases'));
});

test('card asks for login when the session is missing', async () => {
  const { card } = loadCard({ cookie: '' });
  const view = await card.reminderCard({});
  assert.equal(view.count, '—');
  assert.equal(view.detail, '打开暖邻登录后查看');
});

test('card degrades quietly when the backend is unreachable', async () => {
  const { card } = loadCard({ offline: true });
  const view = await card.reminderCard({});
  assert.equal(view.count, '—');
  assert.equal(view.detail, '暂时读不到，点开暖邻查看');
  assert.equal(card.loadingCard().count, '…');
});
