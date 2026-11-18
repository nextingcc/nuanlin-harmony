# 暖邻 · HarmonyOS 手机端（ArkTS / ArkUI）

比赛鸿蒙工程本体，后端为同仓库 `src/`（FastAPI + Agent + MCP/RAG），网页前端为 `frontend/`。用 DevEco Studio 6.0.2 打开 `harmony/NuanlinHarmony`。

## 已连接的正式后端

- 代码位置：`D:\暖邻\nuan-lin`（本工程同一仓库）
- 本机启动：`python -m scripts.dev_server --port 8010`
  - 8000 在本机被 `Manager.exe` 占用，因此用 8010；换端口时同步改 `model/Api.ets` 的 `BASE`。
  - 本地开发账号密码读取 `.local-dev/LOGIN.txt`，不要写入代码、文档或提交。
  - **唯一例外**：`pages/Login.ets` 里的「演示账号 · 一键填入」常量，仅用于评审现场快速进入本机虚构环境；正式部署前必须删除该常量与入口。
- 手机端访问：`hdc rport tcp:8010 tcp:8010`，应用内基址 `http://127.0.0.1:8010/api/v1`。
- 登录方式：`POST /auth/login`（Cookie + `csrfToken`），写请求带 `X-CSRF-Token` 与 `Idempotency-Key`。
- 已实测：登录、人员列表（5 条，含真实分数/风险/复筛状态）、人员详情、新建/删除人员；写接口 201/200 正常。

## 页面

```
pages/Welcome          启动
pages/Home             首页（轮播、四入口、今日提醒）
pages/ResidentList     筛查工作台
pages/PersonForm       手工建档
pages/ImportPerson     资料识别（OCR + 模型）
pages/Interview        七话题心理关怀访谈（语音 / 文字）
pages/Profile          人员档案
pages/ReportReview     七话题报告人工复核与跟进事项
pages/Followup         回访与关怀
pages/FollowupQueue    回访名单（真实任务）
pages/FollowupList     真实回访历史记录（分页、重试、查看人员档案）
pages/FollowupRecord   回访记录
pages/CareList         重点关怀
pages/Notifications    通知
pages/Assistant        暖邻助手
pages/Widgets          万能卡片（页面内预览）
pages/Login            社区工作账号登录
pages/Tools            工具（备忘录 / 呼吸 / 日志）
pages/Memo             备忘录
pages/Breathe          呼吸放松
pages/Journal          日记、心情与一周回顾（含建议便签覆盖层）
pages/Settings         设置
pages/ResidenceEdit    住址与居住信息编辑
pages/MapLocation      地图选点与位置确认
```

## AI 助手「小暖」

- 助手人设：小暖，18 岁，活泼开朗、办事高效；全身像用于历史侧栏，头部裁剪用于聊天头像。
- 主页面：暖白背景 `#FFF7EA`、棕色文字、粉绿黄图标；AI 气泡浅粉半透明，用户气泡更浅；输入栏含 `＋`、`Message…`、绿色麦克风与发送箭头。
- 历史侧栏：全身像 + 新对话 + 历史会话搜索/列表（本地 Preferences 记录，最多 30 条，可删除）+ 返回；返回键优先关闭侧栏。
- 功能选项与草稿卡按粉/绿/黄着色；涉及诊断、用药、违法或伤害他人的请求会被拒绝并建议寻求专业帮助。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [架构说明](../../docs/ARCHITECTURE.md) | 分层图、数据流、25 个页面清单、原生能力位置、已知边界 |
| [技术实现评分对照](../../docs/SCORE-MAPPING.md) | 原生能力 / 分布式 / 工程化 / 结构 / 性能 / 安全 / 稳定逐条对应代码与数字 |
| [演示脚本](../../docs/DEMO-SCRIPT.md) | 3–5 分钟演示流程、每步指认点、备用方案 |
| [CI 说明](../../docs/CI.md) | 托管单测 + 自建 Windows 构建 HAP、runner 前置条件 |

## 架构速览

```
pages（25 个页面） → components/Common（NavBar / Dock / Tag / Avatar）
                  → model（Api / SecureStore / Theme / 状态机 / 提醒规则 / ErrorGuard）
                  → 系统能力（ArkUI、HUKS、preferences、NotificationKit、FormKit、mediaquery、Canvas）
                  → 后端 FastAPI /api/v1（会话、人员、访谈、报告、回访、日记与 RAG 建议）
```

- **会话**：HUKS AES-256 加密后写 `preferences`，启动时解密并 `GET /me` 校验。
- **请求**：统一 `Api.request`，带 Cookie + CSRF + 幂等键，网络异常与 5xx 自动重试一次。
- **建议**：后端 RAGFlow 检索 + 模型生成 5 条，返回文献出处；手机端以便签覆盖层展示。

## 个人资料

- 设置 → 个人资料 →「更换」调用系统图库选择器（`PhotoViewPicker`），选图后进入方形裁剪框（双指缩放 / 拖动 / ± 按钮），确认后按取景裁成 256×256 JPEG 存到 `filesDir/avatar.jpg`，以 PixelMap 呈现；首页右上角头像同步。
- 头像仅存本机，不随账号同步；未设置时回退内置头像。

## 原生能力与一多

- **服务卡片**：`EntryFormAbility` + `resources/base/profile/form_config.json`（2×2 / 4×4），桌面显示「今日到期回访 + 重点关怀」数量，点击 `wantAgent` 打开应用。数据复用 App 会话 Cookie（Preferences），3 秒超时，失败时显示「点开暖邻查看」。
  - 卡片复用 HUKS 解密读取加密会话，兼容旧会话，不写入明文；支持系统定时刷新回调。登录过期与部分接口失败分别提示，不将失败计为零；FormExtension 上下文的解密效果仍需设备验收。
- **系统通知**：`model/Notifier.ets` 在首页检测到到期提醒时按自然日去重推送，点击回到应用；设置页「运行配置 → 提醒测试」可手动发一条，用于演示与排障。
- **一多适配**：`model/Layout.ets` 统一 sm/md/lg 断点（600 / 840vp），Home、Tools 在 ≥600vp 起双栏，ResidentList 在 ≥840vp 起双栏；`deviceTypes` 为 phone / tablet / 2in1。
- **卡片与通知的验证**：`hdc shell bm dump -n com.nuanlin.care` 可确认 `extensionTypeName: form`；通知权限由系统弹窗授予，拒绝后入口会提示「通知未开启或被拒绝」。

## 安全、性能与工程化

- **启动耗时（模拟器冷启动，5 次）**：中位 314 ms（267–341 ms）；分阶段 prefs 51–97 ms、系统栏 17–26 ms、会话恢复 140–181 ms。`EntryAbility` 输出 `startup_ms` 埋点，可按同样方法复测。

- **本机偏好**：`model/UserPreferences.ets` 使用独立的 ArkData Preferences 保存方言、播报语速、字号、减少动效、主题和参考日期；首屏加载前恢复，保存等待 `flush` 成功。语音授权仍按本次运行核实，不随普通偏好持久保存。
- **字号范围**：设置、筛查名单、人员档案、回访名单/历史/记录、重点关怀、报告人工复核和共享状态标签支持大字/特大；访谈沿用既有字号设置。大字至少16fp、特大至少18fp，正文行距同步增加。首页插画、日记等其余页面未在本轮全面适配。
- **设置语义**：本机参考日期仅供查看，不改变正式回访排期；减少动效关闭首页轮播自动播放。正式回访日期仍在人员档案流程安排。

- **会话加密**：`model/SecureStore.ets` 用 HUKS 生成不可导出的 AES-256 密钥，Preferences 只保存 `v1.<IV>.<密文>`；`Api.restoreSession` 解密失败即清空会话。块模式用 CBC + PKCS7：HUKS 的 GCM 解密在模拟器上对 `HUKS_TAG_AE_TAG` 处理不稳定（init 直接失败），CBC 行为可预期。
- **隐私模式（未启用）**：`window.setWindowPrivacyMode` 需要系统级权限，普通应用调用返回 201（permission denied），因此档案页未启用防截屏，依赖应用沙箱与系统文件加密。
- **媒体体积**：大图统一转 WebP（质量 82，按展示尺寸缩放），`resources/base/media` 从 15.1 MB 降到 2.85 MB；文件名不变，`$r('app.media.xxx')` 无需改动。
- **列表虚拟化**：`model/ListSource.ets` 提供 `BasicDataSource<T>`，筛查名单改为 `List + LazyForEach`，平板宽屏用 `lanes(2)` 分栏。
- **静态检查**：工程根目录新增 `code-linter.json5`（性能 / 安全规则集），可用 DevEco 的 Code Linter 执行。
- **字体子集**：`tools/subset-font.py` 从 `tools/fonts/JournalHandwriting-full.ttf` 生成 GB2312 子集（7,834 字形），rawfile 字体 25.3 MB → 3.37 MB，HAP 29.45 MB → 8.49 MB；生僻字回退系统字体。
- **设备端测试**：`entry/src/ohosTest`（hypium 1.0.18）覆盖断点 / 提醒去重 / 文案，`build-original.cjs entry@ohosTest` 构建测试 HAP，`aa test -m entry_test` 运行，实测 3/3 通过。
- **一键验证**：`node harmony/NuanlinHarmony/tools/verify.cjs`（单测 → 主 HAP），加 `--with-test-hap` 再构建测试 HAP；CI 见 `.github/workflows/harmony-checks.yml`。

## 心情调节建议（便签覆盖层）

- 在「一周回顾」点「心情调节建议」不再跳页：全屏压暗 + 中央便签，5 条建议左右切换；首/末条自动隐藏对应方向。
- 便签图片用 `ImageFit.Contain` 不裁切；「生成备注」写入备忘录（`advice-<id>`）；点遮罩关闭。
- 生成仍用 `Api.journalAnalysis` + `Api.journalSuggestions`，接口与旧页一致。

## 设置与深色模式

- **设置分组**：运行配置 / 外观 / 提醒 / 使用设置 / 安全与数据 / 关于；深色模式、字号、动效在「外观」，测试通知在「提醒」，退出登录与清除本地备忘录在「安全与数据」，版本与服务卡片说明在「关于」。
- **深色模式**：三档「跟随系统 / 浅色 / 深色」，`Theme.resolveDark(themeMode, systemDark)` 决定结果，`mediaquery` 监听系统变化；持久化 `themeMode`，旧的 `darkMode` 布尔自动迁移。`palette(dark)` 的浅色值逐项等于原颜色；首页 / 工具 / 助手 / 呼吸 / 备忘 / 通知 / 档案 / 筛查名单 / 回访与关怀 / 回访队列 / 回访记录 / 回访登记 / 重点关怀 / 日记（含心情日历与一周回顾）/ 心情调节建议 / 访谈 / 报告复核 / 新建人员 / 导入人员 / 设置与 `Dock` 已接入，背景图页面在深色下加暗色遮罩。日记、一周回顾、建议、访谈与报告复核也已接入（纸质底图在深色下压暗并叠遮罩）；全站页面均可深色。
- **退出登录**：`Api.logout()` 清空内存会话并删除 HUKS 密文，二次确认后回登录页；清除备忘录只影响本机。
- **系统栏**：`model/WindowTheme.ets` 在启动、切主题、系统深色变化时同步状态栏/导航栏底色与图标颜色，深色下不露白边。
- **国际化（第一批）**：底部导航与工具页文案已改用 `$r('app.string.*')`，`resources/base|zh_CN|en_US` 三套文案齐备；`test/i18n.test.cjs` 校验三套 key 一致、英文非空且确实翻译。其余页面仍为中文，未做全量 i18n。
- **PATCH 兼容**：`http.RequestMethod` 无 PATCH，`Api.patchMethod()` 用字符串转换透传，服务端报告复核接口仍按 PATCH 调用。

## 后端对接约定

- 人员：`GET /people`、`GET /people/{id}`、`POST /people`、`PATCH/DELETE /people/{id}`
- 评估：`GET /people/{id}/assessments`、`POST /people/{id}/assessments`
- 当前访谈创建 `TOPIC-INTERVIEW`，使用 `automatic` 工作流。七个话题不计分，没有频率选项；同一话题的追问不增加话题数。
- 手机端访谈：`GET /interviews/{id}` → `PUT precheck` → `POST turns`。提交 202 后，问题卡下方通过 `/interviews/{id}/events` 实时显示分析阶段和报告草稿，完成后从已保存的状态读取问题、追问依据和报告。流断开期间继续轮询，恢复后从新快照接续。处理失败时可 `POST retry`。
- 当前问题取 `currentQuestion.id/topicId/text`，写请求带服务端 `revision` 和 `If-Match`。只提交核对后的居民原话；记录暂停、安全中断或归档时停止采集和提交。
- 语音复用 `/voice/config`、`POST /voice/sessions` 和服务端返回的 WebSocket 路径，收到 `ready` 后才采集 16 kHz 单声道 S16LE。录音状态卡在点击麦克风后显示于输入区上方，切换问题时收起。识别文字须核对后提交。播报复用 `/voice/tts`，播放器按 initialized → prepared → play 顺序启动，并应用设置中的倍速。
- 历史量表记录仍保留，进入旧记录时提示新建七话题访谈，不将旧记录改成七话题。
- 资料识别：`/document-imports`（capabilities → create → upload → run → poll），仅 synthetic
- 回访：`GET /followups?view=due`、`POST /followups/{id}/start-assessment`、`POST /followups/{id}/records`
- 关怀：`GET /care-cases`、`POST /care-cases/{id}/close`
- 通知：`GET /notifications`、`POST /notifications/{id}/read`
- 首页「今日提醒」和「通知」合并显示本机备忘录超时、后端到期回访及重点关怀提醒。备忘录按设备时间在指定分钟进入超时，完成或删除后从提醒中移除。备忘录页保持打开时，新超时事项会提示一次。
- 档案页“人工复核报告与跟进事项”进入 ReportReview：核对居民原话、文献与历史来源，保存修订后重新核对并明确确认。使用报告 `/summary`、`/confirm` 接口；不会自动确认或归档。
- 报告确认后接入 `/interviews/{id}/followup-items`、`/followup-items/draft` 和 `/followup-items/{id}`：整理建议，人工逐条采用、不采用、开始跟进或标记完成；事项采用不等于回访排期，排期仍由档案页原有风险确认流程处理。建议生成期间轮询，离页停止。
- `/interviews/{id}/recheck` 仅适用于进行中的自动访谈当前话题，不用于已完成报告的人工复核；此接口尚未接入手机端。
- API 22 的 PATCH 请求使用原生 RemoteCommunicationKit RCP，沿用会话、CSRF、幂等键、If-Match 和错误处理；其他 HTTP 请求继续使用 NetworkKit。零售真机仍待验收，模拟器验证范围见下。
  - 2026-11-16已在模拟器使用隔离虚构案例完成报告PATCH修订、人工确认、事项采用→开始跟进→完成，服务端版本与处理说明均已核对；开始跟进/完成/不采用均需说明。尚未零售真机和真实模型质量验收，详情见 `docs/harmony-optimization-step4-2026-11-16.md`。

## 构建

2026-11-17新增“暖邻语音助手”规则开场：安全确认后完整文字弹层，按武汉时间和已确认沟通偏好拼接60～90字，讯飞逐句播放/暂停续播/重播/开始答题及真实播放句高亮；失败保留文字。89项鸿蒙检查、35项开场语音及3项人员保护回归通过。本轮未安装/操作设备，需负责设备的agent统一构建签名与真机验收。见 `docs/harmony-opening-introduction-2026-11-17.md`。

2026-11-17增加武汉地图位置核验与单站导航代码：Profile→MapLocation，华为原生地图搜索/选点、人员版本保护的位置保存、步行/驾车导航调起。78项鸿蒙、16项位置API、43项人员/回访回归通过。当前未配置地图身份与匹配签名，仅模拟器失败保护已验收，真实地图选点和导航成功仍待开通后验证；尚无整天路线优化。见 `docs/harmony-optimization-step9-2026-11-17.md` 与 `docs/harmony-wuhan-map-setup.md`。

住所资料链已贯通：识别核对带入、建档保存、档案展示、已有档案版本保护的住所补录（ResidenceEdit）。地图位置尚未核验，暂不能导航。72项检查及3项后端人员接口保护回归通过，模拟器虚构住所保存/回显已验收。见 `docs/harmony-optimization-step8-2026-11-16.md`；路线与导航技术方案见 `docs/harmony-map-routing-research-2026-11-16.md`。

助手第一阶段已去除固定演示数据：重新核验当前居民、选择居民并读取真实访谈列表，可进入档案和对应报告核对原话/来源。自由问答、助手RAG生成尚未接入，页面明确标注；不会通过聊天直接修改风险、报告或任务。见 `docs/harmony-optimization-step7-2026-11-16.md`。

2026-11-16周期复筛闭环已在隔离虚构案例的模拟器验证：队列开始/继续复筛→七话题访谈→当前版本报告人工复核→明确风险并确认归档→旧任务完成及历史→下一次排期。周期任务禁止用普通联系记录完成；档案显示服务端下一次复筛时间（北京时间），从记录进入后可返回原记录页。鸿蒙65项与后端回访23项回归通过；详情见仓库 `docs/harmony-optimization-step5-2026-11-16.md`。零售真机、真实模型质量与旧量表复筛兼容仍待验证。

`hvigor` 不接受中文工程路径。使用原工程提供的构建入口，在同一磁盘创建英文路径的 NTFS 硬链接编译视图；源文件与原工程是同一份文件，构建产物单独生成，SDK 无需修改：

```powershell
& "D:\HarmonyOS\DevEcoStudio\tools\node\node.exe" harmony/NuanlinHarmony/tools/build-original.cjs
& "D:\HarmonyOS\DevEcoStudio\tools\node\node.exe" harmony/NuanlinHarmony/tools/verify.cjs
& "D:\HarmonyOS\DevEcoStudio\tools\node\node.exe" harmony/NuanlinHarmony/tools/build-original.cjs entry@ohosTest
```

从仓库根目录运行；DevEco 安装在其他位置时设置 `DEVECO_STUDIO_HOME`。构建入口会校验编译视图的归属，更新源文件链接，并自动将 HAP 放回原工程 `entry/build/default/outputs/default/entry-default-unsigned.hap`。视图默认在同一盘的 `nl-harmony-build-view`，其中只链接代码和资源，`build` 是生成内容。被替换的旧链接会移到视图内的 `.stale-links/`，不会留在 `resources/` 里造成重复资源。仅在模拟器使用未签名包；真机沿用 DevEco 的正式签名流程。

档案页支持继续同一七话题访谈及显示服务端报告；无评分的记录显示话题进度，不将空分数当成零分，也不以话题数量推断四档压力状态。设置返回访谈后继续刷新，离开页面时释放录音、播放器和轮询。
