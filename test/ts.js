// 统一解析 TypeScript：本地开发用 DevEco 自带的 typescript，CI 用 npm 安装的版本。
const fs = require('node:fs');
const path = require('node:path');

function resolveTypeScript() {
  const bundled = path.join(__dirname, '..', 'node_modules', '@ohos', 'hvigor', 'node_modules', 'typescript');
  if (fs.existsSync(bundled)) return require(bundled);
  try {
    return require('typescript');
  } catch (error) {
    throw new Error('typescript not found: run npm install typescript in harmony/NuanlinHarmony');
  }
}

module.exports = resolveTypeScript();
