// 一键验证鸿蒙端：单元测试 → 主 HAP 构建 →（可选）测试 HAP 构建。
// 用法：node harmony/NuanlinHarmony/tools/verify.cjs [--with-test-hap]
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const root = path.resolve(__dirname, '..');
const node = process.execPath;

function run(label, args) {
  console.log(`\n== ${label} ==`);
  const result = spawnSync(node, args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}

const testDir = path.join(root, 'test');
const tests = fs.readdirSync(testDir).filter(name => name.endsWith('.test.cjs')).sort()
  .map(name => path.join(testDir, name));
if (tests.length === 0) throw new Error('No Harmony unit tests found');
run('unit tests', ['--test', ...tests]);
run('build main HAP', [path.join(__dirname, 'build-original.cjs')]);
const hap = path.join(root, 'entry/build/default/outputs/default/entry-default-unsigned.hap');
if (fs.existsSync(hap)) {
  const mb = fs.statSync(hap).size / 1024 / 1024;
  console.log(`\nHAP size: ${mb.toFixed(2)} MB`);
}
if (process.argv.includes('--with-test-hap')) {
  run('build test HAP', [path.join(__dirname, 'build-original.cjs'), 'entry@ohosTest']);
}
console.log('\nverify ok');
