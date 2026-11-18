const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');
const model = path.join(__dirname, '../entry/src/main/ets/model');

function load(file, modules, transform = text => text) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(transform(fs.readFileSync(path.join(model, file), 'utf8')), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, require(name) { return modules[name] ?? {}; } });
  return exports;
}

test('native PATCH transport preserves method, body, headers and closes on all outcomes', async () => {
  let closed = 0;
  let fail = false;
  const requests = [];
  class Request {
    constructor(url, method, headers, content) { Object.assign(this, { url, method, headers, content }); }
  }
  const transport = load('PatchTransport.ets', { '@kit.RemoteCommunicationKit': { rcp: {
    Request, createSession() { return {
      async fetch(request) {
        requests.push(request);
        if (fail) throw new Error('offline');
        return { statusCode: 409, toString: () => '{"error":{"message":"版本冲突"}}' };
      }, close() { closed++; }
    }; }
  } } });
  const reply = await transport.patchRequest('https://fictional.invalid/report', { Cookie: 'fictional' }, '{"revision":4}', 8000);
  assert.equal(reply.responseCode, 409);
  assert.equal(requests[0].method, 'PATCH');
  assert.equal(requests[0].headers.Cookie, 'fictional');
  assert.equal(requests[0].content, '{"revision":4}');
  assert.equal(requests[0].configuration.transfer.timeout.transferMs, 8000);
  fail = true;
  await assert.rejects(transport.patchRequest('https://fictional.invalid/report', {}, '{}', 8000), /offline/);
  assert.equal(closed, 2);
});

test('report and item writes carry session, CSRF, idempotency and the displayed revision', async () => {
  const calls = [];
  let status = 200;
  const modules = {
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0 },
      createHttp: () => ({ async request(url, options) {
        calls.push({ url, headers: options.header, body: options.extraData, method: options.method });
        return { responseCode: status, cookies: '', result: '{"data":{}}' };
      }, destroy() {} }) } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } },
    './PatchTransport': { async patchRequest(url, headers, body) {
      calls.push({ url, headers, body, method: 'PATCH' });
      return { responseCode: status, cookies: '', result: '{"error":{"message":"版本冲突"}}' };
    } }
  };
  const { Api } = load('Api.ets', modules, text => text
    .replace("let cookie: string = '';", "let cookie: string = 'nuanlin_session=fictional';")
    .replace("let csrf: string = '';", "let csrf: string = 'fictional-csrf';"));
  Api.ensureSession = async () => true;
  await Api.editReport('fictional', 7, '人工修改');
  await Api.confirmReport('fictional', 8);
  await Api.draftFollowupItems('fictional', 9);
  await Api.decideFollowupItem('item', 3, 'resolved', '已核实');
  assert.deepEqual(calls.map(call => call.method), ['PATCH', 'POST', 'POST', 'PATCH']);
  assert.deepEqual(calls.map(call => call.headers['If-Match']), ['"7"', '"8"', '"9"', '"3"']);
  for (const call of calls) {
    assert.equal(call.headers.Cookie, 'nuanlin_session=fictional');
    assert.equal(call.headers['X-CSRF-Token'], 'fictional-csrf');
    assert.ok(call.headers['Idempotency-Key']);
  }
  assert.equal(JSON.parse(calls[0].body).editedText, '人工修改');
  assert.equal(JSON.parse(calls[1].body).reviewedRevision, 8);
  assert.equal(JSON.parse(calls[3].body).note, '已核实');
  status = 409;
  await assert.rejects(Api.editReport('fictional', 7, '保留修订'), /版本冲突/);
});

test('people endpoints normalize nullable optional fields without inventing resident information', async () => {
  const person = { id: 'fictional', name: '虚构验收', age: 72, gender: null, community: null,
    phone: null, address: null, assessmentCount: 1, lastAssessmentAt: null };
  const { Api } = load('Api.ets', {
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 },
      createHttp: () => ({ async request(url) {
        return { responseCode: 200, cookies: '', result: JSON.stringify({
          data: url.includes('?') ? { items: [person] } : person }) };
      }, destroy() {} }) } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } }
  });
  Api.ensureSession = async () => true;
  for (const loaded of [(await Api.people())[0], await Api.person('fictional')]) {
    for (const key of ['gender', 'community', 'phone', 'address']) assert.equal(loaded[key], '');
    assert.equal(loaded.name, '虚构验收');
    assert.equal(loaded.lastAssessmentAt, null);
  }
});

test('rescreen starts preserve server task/person identity and expose a new or reused assessment', async () => {
  let data = { taskId: 'task', personId: 'person', assessmentId: 'assessment' };
  const calls = [];
  const { Api } = load('Api.ets', {
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0 },
      createHttp: () => ({ async request(url, options) {
        calls.push({ url, options });
        return { responseCode: 201, cookies: '', result: JSON.stringify({ data }) };
      }, destroy() {} }) } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } }
  });
  Api.ensureSession = async () => true;
  const started = await Api.startFollowup('task', 4);
  assert.equal(started.personId, 'person');
  assert.equal(started.assessmentId, 'assessment');
  assert.equal(calls[0].options.header['If-Match'], '"4"');
  assert.equal(JSON.parse(calls[0].options.extraData).revision, 4);
  data = { taskId: 'other', personId: 'person', assessmentId: 'assessment' };
  await assert.rejects(Api.startFollowup('task', 4), /资料不完整/);
});
