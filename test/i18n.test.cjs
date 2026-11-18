const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const RES = path.join(__dirname, '../entry/src/main/resources');
const LOCALES = ['base', 'zh_CN', 'en_US'];

function readStrings(locale) {
  const file = path.join(RES, locale, 'element/string.json');
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  const map = {};
  for (const item of data.string) map[item.name] = item.value;
  return map;
}

test('every locale declares the same string keys', () => {
  const base = readStrings('base');
  for (const locale of LOCALES) {
    const map = readStrings(locale);
    assert.deepEqual(Object.keys(map).sort(), Object.keys(base).sort(), `${locale} keys differ from base`);
  }
});

test('translations are non-empty and English is actually translated', () => {
  const zh = readStrings('zh_CN');
  const en = readStrings('en_US');
  for (const [key, value] of Object.entries(en)) {
    assert.ok(value.trim().length > 0, `${key} is empty in en_US`);
    if (!key.startsWith('Entry') && !key.includes('label')) {
      assert.notEqual(value, zh[key], `${key} is still Chinese in en_US`);
    }
  }
});

test('the shell strings used by Dock and Tools exist', () => {
  const en = readStrings('en_US');
  for (const key of ['tab_home', 'tab_tools', 'tab_assistant', 'tab_settings', 'tools_title', 'tools_subtitle', 'tools_footer']) {
    assert.ok(en[key], `${key} missing`);
  }
  assert.equal(en.tab_home, 'Home');
});
