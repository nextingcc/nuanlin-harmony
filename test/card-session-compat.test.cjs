const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function card({ saved = 'v1.iv.cipher', decrypted = 'nuanlin_session=fictional', broken = false,
  replies = [{ count: 2 }, { count: 1 }] } = {}) {
  const requests = [];
  let releases = 0;
  let decrypts = 0;
  const modules = {
    '@kit.NetworkKit': { http: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
      createHttp: () => ({
        async request(url, options) {
          requests.push({ url, options });
          const reply = replies[requests.length - 1];
          if (reply.error) throw new Error('offline');
          return { responseCode: reply.status ?? 200,
            result: JSON.stringify(reply.body ?? { data: { items: Array(reply.count ?? 0).fill({}) } }) };
        },
        destroy() { releases++; }
      })
    } },
    '@kit.ArkData': { preferences: { getPreferences: async () => ({ get: async () => saved }) } },
    './SecureStore': {
      isEncryptedSession: value => value.startsWith('v1.'),
      async decryptSession() {
        decrypts++;
        if (broken) throw new Error('key unavailable');
        return decrypted;
      }
    },
    './ReminderRules': { reminderCountText: n => `${n} 件`, reminderSummary: (a, b) => `${a}/${b}` }
  };
  const exports = {};
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/CardData.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, require(name) { assert.ok(modules[name], name); return modules[name]; } });
  return { view: () => exports.reminderCard({}), requests, releases: () => releases, decrypts: () => decrypts };
}

test('encrypted card session is decrypted and sent in headers without persisting plaintext', async () => {
  const subject = card();
  assert.equal((await subject.view()).count, '3 件');
  assert.equal(subject.decrypts(), 1);
  assert.equal(subject.releases(), 2);
  for (const request of subject.requests) {
    assert.equal(request.options.header.Cookie, 'nuanlin_session=fictional');
    assert.ok(!request.url.includes('fictional'));
  }
});

test('legacy card session remains compatible', async () => {
  const subject = card({ saved: 'nuanlin_session=legacy' });
  assert.equal((await subject.view()).count, '3 件');
  assert.equal(subject.decrypts(), 0);
});

test('unreadable and invalid card sessions never send a network request', async () => {
  for (const options of [{ saved: '' }, { saved: 'invalid' }, { broken: true },
    { decrypted: 'nuanlin_session=x\r\nInjected: value' }]) {
    const subject = card(options);
    assert.equal((await subject.view()).detail, '打开暖邻登录后查看');
    assert.equal(subject.requests.length, 0);
  }
});

test('expired card session does not display a successful partial count', async () => {
  const subject = card({ replies: [{ status: 401 }, { count: 2 }] });
  assert.match((await subject.view()).detail, /登录已失效/);
});

test('partial errors and malformed data are not presented as zero reminders', async () => {
  for (const failed of [{ error: true }, { status: 500 }, { body: { data: {} } }]) {
    for (const replies of [[failed, { count: 0 }], [{ count: 2 }, failed]]) {
      const subject = card({ replies });
      const view = await subject.view();
      assert.equal(view.count, '—');
      assert.match(view.detail, /暂不可用/);
      assert.equal(subject.releases(), 2);
    }
  }
});
