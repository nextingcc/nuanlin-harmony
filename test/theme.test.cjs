const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function loadTheme() {
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/Theme.ets'), 'utf8')
    .replace(/\r/g, '');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, AppStorage: { get: () => undefined }, Date, Math, console });
  return exports;
}

test('theme mode resolves auto against the system color mode', () => {
  const { resolveDark } = loadTheme();
  assert.equal(resolveDark('dark', false), true);
  assert.equal(resolveDark('dark', true), true);
  assert.equal(resolveDark('light', true), false);
  assert.equal(resolveDark('light', false), false);
  assert.equal(resolveDark('auto', true), true);
  assert.equal(resolveDark('auto', false), false);
  assert.equal(resolveDark('', true), true);
});

test('light palette keeps the original paper colors', () => {
  const { palette } = loadTheme();
  const light = palette(false);
  assert.equal(light.pageBg, '#F8E8E2');
  assert.equal(light.surface, '#FFFDF8');
  assert.equal(light.ink, '#4A3428');
  const dark = palette(true);
  assert.equal(dark.pageBg, '#151311');
  assert.equal(dark.ink, '#F0E6DA');
  assert.notEqual(light.ink, dark.ink);
});
