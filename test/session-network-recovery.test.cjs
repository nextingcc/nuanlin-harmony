const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('./ts');

test('a transient restore failure preserves encrypted login; an actual 401 deletes it', async () => {
  let mode = 'offline';
  const disk = new Map([['session', 'encrypted-fictional-session']]);
  const preferences = {getPreferences: async () => ({
    get: async (key, fallback) => disk.get(key) ?? fallback,
    put: async (key, value) => disk.set(key, value), delete: async key => disk.delete(key), flush: async () => {}
  })};
  const modules = {
    '@kit.ArkData': {preferences},
    '@kit.NetworkKit': {http: {RequestMethod: {GET: 'GET'}, HttpDataType: {STRING: 0}, createHttp: () => ({
      request: async () => {
        if (mode === 'offline') throw Object.assign(new Error('offline'), {code: 1});
        return {responseCode: mode === 'unauthorized' ? 401 : 200, cookies: '', result: mode === 'unauthorized' ?
          '{"error":{"message":"请先登录"}}' : '{"data":{"id":"fictional-user","organizationId":"fictional-org","csrfToken":"fictional-csrf"}}'};
      }, destroy() {}
    })}},
    '@kit.PerformanceAnalysisKit': {hilog: {info() {}, warn() {}, error() {}}},
    './SecureStore': {isEncryptedSession: () => true, decryptSession: async () => 'nuanlin_session=fictional',
      encryptSession: async () => 'encrypted-fictional-session'}
  };
  const exports = {};
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/Api.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020}}).outputText, {exports, require: name => modules[name] || {},
    AppStorage: {setOrCreate() {}}, setTimeout: resolve => {resolve(); return 1;}});
  assert.equal(await exports.Api.restoreSession({}), false);
  assert.equal(disk.get('session'), 'encrypted-fictional-session');
  mode = 'online'; assert.equal(await exports.Api.restoreSession({}), true);
  mode = 'unauthorized'; assert.equal(await exports.Api.restoreSession({}), false);
  assert.equal(disk.has('session'), false);
});
