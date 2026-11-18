# 从克隆到在模拟器运行

本仓库是 HarmonyOS 客户端源码，包含全部 26 个页面与资源，但**不包含**依赖、构建产物、签名证书和后端服务。

## 1. 环境

- DevEco Studio 6.0.2（HarmonyOS SDK API 22）
- Node.js（DevEco 自带即可）
- 后端：本仓库上级项目的 FastAPI 服务（`src/`、`scripts/dev_server.py`），或使用比赛提交的后端冻结包

## 2. 安装依赖

在仓库根目录执行（需 DevEco 的 ohpm）：

```bash
ohpm install
```

## 3. 构建

```bash
node tools/build-original.cjs
```

脚本会把源码同步到同盘的 ASCII 构建视图（默认 `nl-harmony-build-view`），生成：

```
entry/build/default/outputs/default/entry-default-unsigned.hap
```

脚本需要 `DEVECO_STUDIO_HOME`，默认 `D:\HarmonyOS\DevEcoStudio`。

## 4. 签名与安装

在 DevEco 中打开工程，配置自动签名（或使用自己的证书），生成 signed HAP，然后：

```bash
hdc install -r entry-default-signed.hap
```

未签名 HAP 不能直接安装到模拟器/真机。

## 5. 后端

```bash
python -m scripts.dev_server --port 8010 --document-synthetic
hdc rport tcp:8010 tcp:8010
```

没有后端时，登录、人员、回访、助手、OCR、访谈都会报网络错误；页面本身仍可打开。

## 6. 已知问题

- 访谈自动化的模型输出校验在弱模型上可能连续失败，导致自动化任务失败或后端退出；演示前建议先用测试账号完整彩排一次。
- 模拟器应用市场无法连接华为服务，原生花瓣地图无法安装；导航会退回浏览器高德网页地图。
- OCR 图片需为“姓名：王秀兰”这种逐行冒号格式，表格版容易被判为多人。

## 7. 比赛提交建议

源码之外，同时提交：

- 已签名 HAP
- 后端冻结包与演示数据库
- 演示脚本、OCR 图片、录屏
