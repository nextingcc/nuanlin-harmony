const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('./ts');
function load(api) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/AssistantContext.ets'), 'utf8');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS}}).outputText,
    {exports, require: () => ({Api: api})});
  return exports.readAssistantContext;
}
test('assistant rejects missing, inaccessible or mismatched resident before reading records', async () => {
  let reads = 0;
  const read = load({person: async () => ({id: 'other'}), assessments: async () => {reads++; return [];}});
  await assert.rejects(read(''), /选择/);
  await assert.rejects(read('resident'), /核对/);
  assert.equal(reads, 0);
  await assert.rejects(load({person: async () => null})('resident'), /核对/);
});
test('assistant exposes only actual record identity and never invents a risk or a score', async () => {
  const read = load({person: async id => ({id, name: '虚构居民'}), assessments: async () => [
    {id:'actual-session', scale:'TOPIC-INTERVIEW', status:'completed', startedAt:'2026-11-16T00:00:00Z'}]});
  const result = await read('resident');
  assert.equal(result.assessmentId, 'actual-session');
  assert.equal(result.topic, true);
  assert.equal(result.completed, true);
  assert.match(result.overview, /2026-11-16/);
  assert.doesNotMatch(result.overview, /风险|72小时|16 \/ 24/);
});
test('assistant keeps empty records distinct from failed reads and retains legacy scale identity', async () => {
  const person = async id => ({id});
  const empty = await load({person, assessments: async () => []})('resident');
  assert.equal(empty.assessmentId, '');
  assert.match(empty.overview, /暂无/);
  await assert.rejects(load({person, assessments: async () => {throw new Error('登录失效')}})('resident'), /登录失效/);
  const legacy = await load({person, assessments: async () => [{id:'legacy', scale:'PHQ-9', status:'archived', startedAt:'2026-11-01'}]})('resident');
  assert.equal(legacy.topic, false);
  assert.match(legacy.overview, /PHQ-9/);
});
