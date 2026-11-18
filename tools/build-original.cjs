// Build the original Unicode-path project without maintaining a source copy.
// NTFS hard links share the source file itself. Generated files stay in the
// ASCII build view; no SDK file or compiler validation is modified.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = fs.realpathSync.native(path.resolve(__dirname, '..'));
const view = path.join(path.parse(root).root, 'nl-harmony-build-view');
const staleDir = path.join(view, '.stale-links');
const marker = path.join(view, '.nuanlin-build-view.json');
const studio = process.env.DEVECO_STUDIO_HOME || 'D:\\HarmonyOS\\DevEcoStudio';
// build / node_modules 等任何层级都跳过；test、tools 只在工程根目录跳过，
// 否则 entry/src/ohosTest/ets/test 会被误伤。
const excluded = new Set(['node_modules', 'oh_modules', 'build', '.hvigor', '.cxx', '.git']);
const rootOnly = new Set(['test', 'tools']);
function skip(name, directory) {
  return excluded.has(name) || (directory === root && rootOnly.has(name)) ||
    /^(build|cache)-before-topic-/.test(name);
}
if (fs.existsSync(view)) {
  if (fs.realpathSync.native(view) !== view || !fs.existsSync(marker) ||
      JSON.parse(fs.readFileSync(marker, 'utf8')).source !== root) {
    throw new Error('Build view is not owned by this original project: ' + view);
  }
} else {
  fs.mkdirSync(view);
  fs.writeFileSync(marker, JSON.stringify({ source: root }, null, 2));
}

function synchronize(directory) {
  for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
    if (skip(item.name, directory)) continue;
    const source = path.join(directory, item.name);
    const destination = path.join(view, path.relative(root, source));
    if (!destination.startsWith(view + path.sep) || !source.startsWith(root + path.sep)) {
      throw new Error('Source alias is outside the project');
    }
    if (item.isSymbolicLink()) throw new Error('Unexpected link in source tree: ' + source);
    if (item.isDirectory()) {
      fs.mkdirSync(destination, { recursive: true });
      synchronize(source);
    } else if (item.isFile()) {
      if (fs.existsSync(destination)) {
        const a = fs.statSync(source, { bigint: true });
        const b = fs.statSync(destination, { bigint: true });
        if (a.dev === b.dev && a.ino === b.ino) continue;
        // Replaced alias: keep the stale link outside the resource tree, otherwise
        // restool treats "*.previous-*" files as duplicate resource declarations.
        const stale = path.join(staleDir, path.relative(view, destination) + '.previous-' + Date.now());
        fs.mkdirSync(path.dirname(stale), { recursive: true });
        fs.renameSync(destination, stale);
      }
      fs.linkSync(source, destination);
    }
  }
  // 源文件被删除（例如图片换成 WebP）时，视图里的旧链接也要清掉，否则会重复声明同名资源。
  const viewDirectory = path.join(view, path.relative(root, directory));
  const sourceNames = new Set(fs.readdirSync(directory));
  for (const name of fs.readdirSync(viewDirectory)) {
    if (sourceNames.has(name) || skip(name, directory) || name.startsWith('.')) continue;
    const stale = path.join(viewDirectory, name);
    if (fs.lstatSync(stale).isFile()) fs.unlinkSync(stale);
  }
}
synchronize(root);
const dependencies = path.join(view, 'node_modules');
if (!fs.existsSync(dependencies)) {
  fs.symlinkSync(path.join(root, 'node_modules'), dependencies, 'junction');
} else if (fs.realpathSync.native(dependencies) !== fs.realpathSync.native(path.join(root, 'node_modules'))) {
  throw new Error('Build view dependency path differs from the original');
}
// ohosTest 的 @ohos/hypium 装在工程根的 oh_modules，视图里同样需要指向它。
// ohosTest 的 @ohos/hypium 装在工程根的 oh_modules。这里复制而不是软链：
// hvigor 解析 OhmUrl 时要求依赖位于工程视图内，软链会让真实路径落到视图外。
const ohModules = path.join(view, 'oh_modules');
const sourceOhModules = path.join(root, 'oh_modules');
if (fs.existsSync(sourceOhModules)) {
  fs.rmSync(ohModules, { recursive: true, force: true });
  fs.cpSync(sourceOhModules, ohModules, { recursive: true, dereference: true });
}

// Read-only image assets can be copied as read-only by restool. Only generated
// output attributes are adjusted, never the linked source attributes.
function writableOutputs(directory) {
  if (!fs.existsSync(directory)) return;
  for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
    const output = path.join(directory, item.name);
    if (item.isSymbolicLink()) throw new Error('Unexpected link inside generated output');
    if (item.isDirectory()) writableOutputs(output);
    else fs.chmodSync(output, 0o666);
  }
}
writableOutputs(path.join(view, 'entry/build'));
// 默认构建主 HAP；传 entry@ohosTest 时构建测试 HAP。
const buildModule = process.argv[2] || 'entry@default';
const result = spawnSync(process.execPath, [
  path.join(view, 'node_modules/@ohos/hvigor/bin/hvigor.js'),
  '--mode', 'module', '-p', 'product=default', '-p', 'module=' + buildModule,
  'assembleHap', '--no-daemon'
], {
  cwd: view, stdio: 'inherit', env: {
    ...process.env,
    DEVECO_SDK_HOME: path.join(studio, 'sdk'),
    JAVA_HOME: path.join(studio, 'jbr'),
    PATH: path.join(studio, 'jbr/bin') + path.delimiter + path.join(studio, 'tools/node') + path.delimiter + process.env.PATH
  }
});
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status || 1);
if (buildModule !== 'entry@default') {
  const testOut = path.join(view, 'entry/build/default/outputs/ohosTest');
  console.log('Test HAP: ' + (fs.existsSync(testOut) ? fs.readdirSync(testOut).join(', ') : 'not found'));
  process.exit(0);
}
const relativeHap = 'entry/build/default/outputs/default/entry-default-unsigned.hap';
const hap = path.join(root, relativeHap);
fs.mkdirSync(path.dirname(hap), { recursive: true });
fs.copyFileSync(path.join(view, relativeHap), hap);
console.log('Original-project HAP: ' + hap);
