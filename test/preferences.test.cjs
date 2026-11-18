const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function loadPreferences() {
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/UserPreferences.ets'), 'utf8')
    .replace(/\r/g, '');
  const exports = {};
  const storage = {};
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    exports, JSON, Date, Math, isNaN, console,
    AppStorage: {
      get: key => storage[key],
      setOrCreate: (key, value) => { storage[key] = value; }
    },
    require: name => name === './Theme' ? { resolveDark: (mode, system) => mode === 'dark' || (mode !== 'light' && system) } :
      name === '@kit.ArkData' ? { preferences: { getPreferences: async () => ({ get: async () => '', put: async () => {}, flush: async () => {} }) } } :
      name === '@kit.AbilityKit' ? {} : {}
  });
  return { prefs: exports, storage };
}

test('reference date rejects impossible or malformed dates', () => {
  const { prefs } = loadPreferences();
  assert.equal(prefs.referenceDate('2026-11-16'), '2026-11-16');
  assert.equal(prefs.referenceDate('2026-02-30'), '');
  assert.equal(prefs.referenceDate('2026-13-01'), '');
  assert.equal(prefs.referenceDate('2026-1-6'), '');
  assert.equal(prefs.referenceDate(''), '');
});

test('invalid preference values fall back to safe defaults', () => {
  const { prefs } = loadPreferences();
  const value = prefs.normalizePreferences({
    voiceDialect: '火星话', ttsRate: 3, textSize: 'huge', reduceMotion: false,
    themeMode: 'sepia', followupDate: 'not-a-date'
  });
  assert.equal(value.voiceDialect, '自动识别');
  assert.equal(value.ttsRate, 1);
  assert.equal(value.textSize, 'normal');
  assert.equal(value.themeMode, 'auto');
  assert.equal(value.followupDate, '');

  const kept = prefs.normalizePreferences({
    voiceDialect: '武汉话', ttsRate: 1.25, textSize: 'large', reduceMotion: true,
    themeMode: 'dark', followupDate: '2026-11-16'
  });
  assert.equal(kept.voiceDialect, '武汉话');
  assert.equal(kept.ttsRate, 1.25);
  assert.equal(kept.textSize, 'large');
  assert.equal(kept.reduceMotion, true);
  assert.equal(kept.themeMode, 'dark');
});

test('readable font scales up only for large text settings', () => {
  const { prefs } = loadPreferences();
  assert.equal(prefs.readableFont(10, 'normal'), 10);
  assert.equal(prefs.readableFont(10, 'large'), 16);
  assert.equal(prefs.readableFont(10, 'extra'), 18);
  assert.equal(prefs.readableLineHeight(20, 'normal'), 20);
  assert.equal(prefs.readableLineHeight(20, 'large'), 24);
  assert.equal(prefs.readableLineHeight(20, 'extra'), 28);
});
