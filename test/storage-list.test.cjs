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

test('lazy list source exposes items and notifies on reload', () => {
  const { BasicDataSource } = load('ListSource');
  const source = new BasicDataSource();
  source.setItems([{ id: 'a' }, { id: 'b' }]);
  assert.equal(source.totalCount(), 2);
  assert.equal(source.getData(1).id, 'b');

  let reloads = 0;
  const listener = { onDataReloaded() { reloads++; } };
  source.registerDataChangeListener(listener);
  source.setItems([{ id: 'c' }]);
  assert.equal(reloads, 1);
  assert.equal(source.totalCount(), 1);

  source.unregisterDataChangeListener(listener);
  source.setItems([]);
  assert.equal(reloads, 1);
});
