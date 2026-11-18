const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');
const model = path.join(__dirname, '../entry/src/main/ets/model');

function runtime(disk = new Map()) {
  const current = new Map();
  let pending;
  let failFlush = false;
  const app = {
    get: key => current.get(key),
    setOrCreate(key, value) {
      current.set(key, value);
    }
  };
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(model, 'UserPreferences.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, AppStorage: app, require(name) {
    if (name === './Theme') return { resolveDark: (mode, system) => mode === 'dark' || (mode === 'auto' && system) };
    assert.equal(name, '@kit.ArkData');
    return { preferences: { async getPreferences(context, options) {
      assert.equal(options.name, 'nuanlin_preferences');
      return {
        async get(key, fallback) { return disk.get(key) ?? fallback; },
        async put(key, value) { pending = [key, value]; },
        async flush() {
          if (failFlush) throw new Error('disk unavailable');
          disk.set(...pending);
        }
      };
    } } };
  } });
  return { prefs: exports, app, current, disk, failFlush() { failFlush = true; } };
}

test('saved preferences restore in a fresh app runtime before any page defaults', async () => {
  const first = runtime();
  await first.prefs.initializePreferences({});
  const desired = { voiceDialect: '武汉话', ttsRate: 0.75, textSize: 'extra', reduceMotion: true,
    themeMode: 'dark', followupDate: '2026-11-20' };
  await first.prefs.savePreferences({}, desired);
  first.app.setOrCreate('voiceConsent', true);
  const restarted = runtime(first.disk);
  await restarted.prefs.initializePreferences({});
  assert.deepEqual(JSON.parse(JSON.stringify(restarted.prefs.readPreferences())), desired);
  assert.equal(restarted.app.get('darkMode'), true);
  assert.equal(restarted.disk.has('voiceConsent'), false);
  assert.equal(restarted.app.get('voiceConsent'), undefined);
  assert.equal(restarted.disk.has('darkMode'), false);
});

test('invalid stored options are repaired rather than reused in voice and layout', async () => {
  const subject = runtime(new Map([['settings', JSON.stringify({ textSize: 'broken', ttsRate: 99, voiceDialect: 'unknown',
    reduceMotion: 'yes', themeMode: 'unknown', followupDate: '2026-02-31' })]]));
  await subject.prefs.initializePreferences({}, true);
  const restored = subject.prefs.readPreferences();
  assert.equal(restored.textSize, 'normal');
  assert.equal(restored.ttsRate, 1);
  assert.equal(restored.voiceDialect, '自动识别');
  assert.equal(restored.reduceMotion, false);
  assert.equal(restored.followupDate, '');
  assert.equal(subject.app.get('darkMode'), true);
});

test('theme follows system changes only when the saved selection is auto', async () => {
  const subject = runtime();
  await subject.prefs.initializePreferences({}, false);
  subject.prefs.applyPreferenceTheme(true);
  assert.equal(subject.app.get('darkMode'), true);
  subject.app.setOrCreate('themeMode', 'light');
  subject.prefs.applyPreferenceTheme(true);
  assert.equal(subject.app.get('darkMode'), false);
});

test('a disk flush failure keeps shared settings unchanged and reports failure', async () => {
  const subject = runtime();
  await subject.prefs.initializePreferences({});
  const changed = { ...subject.prefs.readPreferences(), textSize: 'extra' };
  subject.failFlush();
  await assert.rejects(subject.prefs.savePreferences({}, changed), /disk unavailable/);
  assert.equal(subject.prefs.readPreferences().textSize, 'normal');
  assert.equal(subject.disk.has('settings'), false);
});

test('font presets increase readability while keeping standard sizes and suitable line spacing', () => {
  const { prefs } = runtime();
  for (const base of [8, 10, 14, 16, 19, 22]) {
    assert.equal(prefs.readableFont(base, 'normal'), base);
    const large = prefs.readableFont(base, 'large');
    const extra = prefs.readableFont(base, 'extra');
    assert.ok(large >= 16 && large > base);
    assert.ok(extra >= 18 && extra >= large);
    assert.ok(prefs.readableLineHeight(base + 8, 'extra') > extra);
  }
});

test('reference date validation rejects impossible dates and accepts leap days', () => {
  const { prefs } = runtime();
  assert.equal(prefs.referenceDate('2024-02-29'), '2024-02-29');
  for (const bad of ['2026-02-29', '2026-13-01', '', 'not-date', 123]) {
    assert.equal(prefs.referenceDate(bad), '');
  }
});
