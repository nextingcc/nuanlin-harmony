const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('./ts');

function load() {
  const text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/AvatarCrop.ets'), 'utf8')
    .replace(/\r/g, '');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, console });
  return exports;
}

test('cover crop centers a landscape image at scale 1', () => {
  const { avatarCropRegion } = load();
  const r = avatarCropRegion(1000, 800, 300, 1, 0, 0);
  assert.equal(r.size, 800);
  assert.equal(r.x, 100);
  assert.equal(r.y, 0);
});

test('zoom shrinks the source region around the center', () => {
  const { avatarCropRegion } = load();
  const r = avatarCropRegion(1000, 800, 300, 2, 0, 0);
  assert.equal(r.size, 400);
  assert.equal(r.x, 300);
  assert.equal(r.y, 200);
});

test('dragging right moves the crop window left and stays inside the image', () => {
  const { avatarCropRegion } = load();
  const moved = avatarCropRegion(1000, 800, 300, 2, 100, 0);
  assert.ok(moved.x < 300);
  assert.ok(moved.x >= 0);
  const extreme = avatarCropRegion(1000, 800, 300, 2, 100000, 0);
  assert.equal(extreme.x, 0);
  assert.equal(extreme.size, 400);
});

test('scale is clamped to 1..3', () => {
  const { clampAvatarScale } = load();
  assert.equal(clampAvatarScale(0.2), 1);
  assert.equal(clampAvatarScale(2.5), 2.5);
  assert.equal(clampAvatarScale(9), 3);
  assert.equal(clampAvatarScale(NaN), 1);
});
