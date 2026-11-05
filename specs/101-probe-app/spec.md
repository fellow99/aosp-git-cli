# 101-probe-app · 设备侧回程探针载体（probe-app）功能规格 —— as-built

> 模块：101-probe-app · 状态：✅ 已实现（specs-as-built：逆向 probe-app 现有代码，非新立需求）
> 所属工程：aosp-git-cli · 规划基线：[`docs/000-工程规划.md`](../../docs/000-工程规划.md)
> §3（消费方环境引导层）/§5.2（helper 农场）/§7.1（env 注入表）/§7.2（已知限制）/§7.3（回程探针 P1–P7）
> 上游用例正典：[`../003-cli/test-cases.md`](../003-cli/test-cases.md)（TC-003-00…19，L3）
> 里程碑对应：M1-T7（最小消费探针·App 域）+ M2-T1（环境引导层接入）
> 本批（2026-11-06）：probe-app 构建修齐（下载 Release AAR 落位 `app/libs/` + `:app:assembleDebug` 通过）与模块 as-built 归档；设备实跑由编排者统一排队，未在本批执行。

## 1. 目的

定义「probe-app」这一**设备侧回程探针载体 App** 的行为契约：作为 `003-cli` 主用例正典的
**可执行、可证伪的设备端子集**，把 `libgit_cli.so` + helper 农场 + assets 随包树装载到真实
Android（arm64）上，注入规划 §7.1 环境契约，逐条执行并给出 PASS/FAIL/SKIP/BLOCKED 判定，
产出机器可读 JSON 报告（`filesDir/probe-report.json`），供消费方环境引导层接入验收
（G3 真机判据的载体，对应 M1-T7 探针 1/2 与 M2-T1）。

本模块**不新增 git 产品能力**：git 本体行为（版本/本地链/https/CA/已知限制）由 `003-cli`
正典承载，本模块只做「App 域装载 + 注入 + 执行 + 判据 + 报告」，并事实化规划 §7.2 已知限制。

> 逆向事实源（as-built）：`probe-app/app/src/main/java/org/fellow99/gitprobe/MainActivity.java`
> （625 行）+ `probe-app/` 全部 Gradle/manifest 文件 + `specs/003-cli/*` + `docs/000-工程规划.md`
> §7/§10 + `git-cli.lock.json` + 工作区
> [`docs/20261105-cli-实测问题-修复设计.md`](../../../docs/20261105-cli-实测问题-修复设计.md)
> （§1/§7：git 功能面**零问题**、范围外不动作——故本模块无 git 修复项）。

## 2. 范围

**在范围内（101-probe-app）：** probe-app 的工程形态（独立 Gradle 工程 + CI 产物 AAR 输入）；
`assets/git-bridge-tools/**` 幂等物化；helper **symlink 农场**创建（D5）；规划 §7.1 env 全表注入；
探针执行框架（PASS/FAIL/SKIP/BLOCKED + JSON 报告）；`003-cli` 用例**逐条保留**（含 App 域
专项 TC-003-18a/18b 与链式 TC-003-05b/08b）；无头触发（`--ez autorun true`）；测试仓库
URL/凭证经 intent extras 注入、报告出口统一脱敏。

**不在范围内（101-probe-app）：** 二进制怎么编（→ 001/002）；git 行为语义本身（→ 003-cli）；
PTY/终端交互（归消费方终端 App，`MainActivity.java:39-43` 明确不判）；ssh 远程（初期无 ssh
二进制，规划 §7.2）；16KB 页设备全链复核（TC-003-17，P7，需 16KB 设备）。

## 3. 功能需求（FR-101-PROBE-xxx，RFC 2119，判据可证伪）

### 3.1 工程与装载域

- **FR-101-PROBE-001（MUST）**：独立工程——probe-app 为**独立 Gradle 工程**（不在
  aosp-git-cli 根 `settings.gradle.kts` 内，000 单模块红线不动，`probe-app/build.gradle.kts:1-6`）；
  `app` 模块 `implementation(files("libs/git-cli-release.aar"))` 依赖 CI 首产 AAR
  （`app/build.gradle.kts:38`）；`:app:assembleDebug` 产出可安装 APK（本批已验证，见 plan §6）。
- **FR-101-PROBE-002（MUST）**：payload 物化——`assets/git-bridge-tools/**` 幂等物化到
  `filesDir/git-bridge-tools`，以 `manifest.json` 的 `totalSha256` 为 marker（先读 assets 内
  manifest、与 `SharedPreferences("probe").tools.sha` 比对，一致则跳过；否则清残留重物化）
  （`MainActivity.java:112-141`）。
- **FR-101-PROBE-003（MUST）**：农场创建（D5）——物化后依
  `git-bridge-tools/gitexec-manifest.json` 的 `farm` 表，在 `filesDir/gitexec` 用
  `android.system.Os.symlink` 建**原名 symlink**（`git-remote-http`/`-https`/`-ftp`/`-ftps` →
  `<nativeLibraryDir>/libgit_remote_curl.so`、`git` → `libgit_cli.so` 等）；先清后建幂等；
  失败即终止（农场是 https/PATH 直呼的前提，R2 出口）。（`MainActivity.java:168-187`）

### 3.2 环境与执行域

- **FR-101-PROBE-004（MUST）**：env 环境注入——执行前注入规划 §7.1 全表：
  `GIT_EXEC_PATH`(农场)/`GIT_TEMPLATE_DIR`(物化 templates)/`GIT_CONFIG_GLOBAL`(注入 HOME 下
  .gitconfig)/`GIT_CONFIG_NOSYSTEM=1`/`GIT_SSL_CAINFO` 与 `SSL_CERT_FILE`(物化 cacert.pem)/
  `GIT_PAGER=cat`/`PATH`(nativeLibraryDir:gitexec:/system/bin)/`HOME`/`TMPDIR`
  （`MainActivity.java:197-210` baseEnv）。
- **FR-101-PROBE-005（MUST）**：执行器——`ProcessBuilder` 直 exec
  `<nativeLibraryDir>/libgit_cli.so`（argv[0] 绝对路径，不依赖 PATH 查找的 realpath 环节）；
  进程环境清空后注入 baseEnv + `ANDROID_ROOT`/`ANDROID_DATA`/`LD_LIBRARY_PATH`；stdout/stderr
  分流（独立 pump 线程）、退出码采集、超时 `destroyForcibly` + `timedOut` 标记。
  （`MainActivity.java:220-260`）
- **FR-101-PROBE-006（MUST）**：探针框架——`Probe` 声明式（id/title/argv/envOverride/stdin/
  timeoutMs/check）；`Check.check(Out)` 返回 `null`=PASS、`SKIP:`=SKIP、`BLOCKED:`=BLOCKED、
  `PASS-`=PASS（带事实备注）、其余=FAIL（`MainActivity.java:276-292`；verdict 归类
  `MainActivity.java:572-581`）。**运行器不预判 FAIL**：预期失败类（TCP-003-15/16 等）由各
  check 判据承载。

### 3.3 判据与报告域

- **FR-101-PROBE-007（MUST）**：用例正典映射——探针 id 与 `003-cli` test-cases 一一对应：
  版本/基础命令（01/02/02b/03/04）、本地仓库全链（05/05b/06/07/07b/08/08b）、https 传输
  （09/10/10b/11/12/13）、带账号仓库（19a/19b/19c）、已知限制事实化（14/15/16）、16KB 页
  采样（17）、App 域专项（18a/18b）。（`MainActivity.java:301-479`，全表见
  [`test-cases.md`](./test-cases.md)）
- **FR-101-PROBE-008（MUST）**：SKIP 口径——依赖 `git_public_url`/`git_auth_url` extras 的
  用例，未提供端点/凭证时**如实 SKIP**（不伪造 PASS/FAIL）：TC-003-09/10（public）、
  10b/11/12（依赖克隆）、13（auth 端点对照）、19a/19b/19c（auth 凭证）——判据首行即 SKIP
  判定分支（判据内 return `"SKIP:…"`，见 test-cases.md 口径表）。
- **FR-101-PROBE-009（MUST）**：结构化报告——每次 runAll 汇总 PASS/FAIL/SKIP/BLOCKED，写
  `filesDir/probe-report.json`（`runAt`/`device`/`pagesize`/`nativeDir`/`farm`/`probes[]`，
  逐条 id/title/verdict/detail/exit/ms/stdout/stderr，stdout/stderr 截断 800 字符），供
  `adb run-as org.fellow99.gitprobe` 取回。（`MainActivity.java:582-619`）
- **FR-101-PROBE-010（MUST）**：敏感信息不落盘——测试仓库 URL/凭证仅经 intent extras
  （`git_public_url`/`git_auth_url`/`git_user`/`git_pass`）传入；报告/日志/UI 出口统一过
  sanitize（密码/用户名打码 + credUrl 脱敏），源码/报告/文档零敏感信息。
  （`MainActivity.java:52-57, 92-99, 495-504`）
- **FR-101-PROBE-011（MUST）**：无头自动化——onCreate 读 launcher intent，`--ez autorun true`
  时自动 runAll（无需点 UI，便于 CI/脚本）；`--es git_*` 同步读入。（`MainActivity.java:89-100`）

## 4. 用户故事

- 作为 **测试/QA**，我需要在真实设备上按 003 正典一键跑批，得到可证伪的 PASS/FAIL/SKIP/
  BLOCKED 与机器可读 JSON，从而在 M2 窗口给出 G3 判据（P1–P7 的 App 域等价）。
- 作为 **构建/流水线实现者**，我需要在 CI 首产后把 Release AAR 部署到探针 App，验证
  物化/农场/注入/exec 四链无回归，避免把「host 能编」当成「设备能跑」。
- 作为 **消费者方开发（环境引导层）**，我需要一个可复现的载体观察 git 在 App 域的事实
  （nativeLibraryDir 落盘、targetSdk≥29 app 域 SELinux 放行、农场 symlink exec、CA 装载路径），
  以决定 dsh 侧如何注入 §7.1 env。

## 5. 实体表

| 实体 | 字段 | 说明 | as-built |
|---|---|---|---|
| `Probe` | `id`/`title`/`argv`/`envOverride`/`stdin`/`timeoutMs`/`check` | 一条探针完整定义；`envOverride` value=null/empty 表示删除该变量 | `MainActivity.java:280-292` / `567-569` |
| `Out` | `stdout`/`stderr`/`exit`/`ms`/`timedOut`/`failReason` | 单次执行采集结果 | `MainActivity.java:212-218` |
| `Check` | `String check(Out o)` | 判据：null=PASS；`SKIP:`/`BLOCKED:`/`PASS-` 前缀特殊判定 | `MainActivity.java:276-278, 572-577` |
| 报告 JSON | `runAt`/`device`/`pagesize`/`nativeDir`/`farm`/`probes[]` | `filesDir/probe-report.json` | `MainActivity.java:606-619` |
| `git-cli-release.aar` | jni/arm64-v8a 两件 + assets 全树 | 探针输入（CI Release 归档；本批下载落位 `probe-app/app/libs/`，gitignored） | `app/build.gradle.kts:38` |
| `filesDir/gitexec/` | farm symlink 树 | FR-101-PROBE-003 产物（`git-remote-*`/`git` 原名 symlink） | `MainActivity.java:168-187` |

## 6. 验收场景（Given/When/Then，as-built 已满足/待设备侧验证）

1. **物化幂等**：Given AAR 已就位、首装；When 点 RUN ALL PROBES（或 `--ez autorun true`）；
   Then assets 物化到 `filesDir/git-bridge-tools` 且二次运行 marker 一致时跳过。
2. **App 域落盘 + exec**：Given APK 已装（useLegacyPackaging=true，D1）；When TC-003-18a；
   Then `nativeLibraryDir/libgit_cli.so` 物理件存在可读且 `--version` 回程（
   `git version 2.56.0`）。
3. **农场 symlink exec（P5）**：Given 农场已建；When TC-003-18b（`filesDir/gitexec/git --version`）；
   Then 经 symlink exec 回程同版本（app 域 SELinux 放行事实，R2）。
4. **env 契约生效（§7.1）**：Given baseEnv 注入；When TC-003-02（`--exec-path`）/07/07b/14；
   Then `GIT_EXEC_PATH` 指向农场、`GIT_CONFIG_GLOBAL` 落注入 HOME、钩子视为无钩子。
5. **端点 SKIP 口径**：Given 未提供 `git_public_url`/`git_auth_url` extras；When
   TC-003-09/10/19a…；Then 判据返回 `SKIP:`（如实，不伪造）。
6. **无头报告**：Given `am start --ez autorun true --es git_public_url …`；When 自动跑批结束；
   Then `filesDir/probe-report.json` 存在，可 `adb run-as org.fellow99.gitprobe` 拉回。

## 7. NFR

- **性能**：本地探针默认 timeout 30–60s；clone/fetch/push/CA 类 90–300s（`probes()` 逐条
  timeoutMs）；超时 `destroyForcibly` + 记 timedOut，不中断整体。
- **可靠性**：物化幂等（marker 一致跳过）；农场先清后建；任一探针超时/崩溃不中断其余
  （外层 try/catch，`runAll` `MainActivity.java:536` 起）。
- **平台覆盖**：仅 arm64-v8a（`app/build.gradle.kts:16` abiFilters）；x86_64 模拟器经
  ndk_translation 可装可跑但**非原生判据**——翻译环境结果仅记录，正式 G3 需原生 arm64 复测
  （003 禁止判据 3）。
- **安全/卫生**：探针 App 不发布、仅 INTERNET 权限（`AndroidManifest.xml:4`）；凭证不落盘
  （FR-101-PROBE-010）；报告 UTF-8 JSON，stdout/stderr 截断 800 字符。
- **可维护性**：探针为声明式 `new Probe(...)` 数组，新增用例只加记录 + 判据 lambda。

## 8. 依赖

| 依赖 | 锚点 | 说明 |
|---|---|---|
| `003-cli` 用例正典 | [`../003-cli/test-cases.md`](../003-cli/test-cases.md) | TC-003-00…19 判据源（本模块可执行子集 + App 域 18a/18b/05b/08b） |
| `git-cli.lock.json` | [`../../git-cli.lock.json`](../../git-cli.lock.json) | 唯一事实源：active 2.56.0 / arm64-v8a；jniLibsWhitelist（`libgit_cli.so`+`libgit_remote_curl.so`）、assets/gitexec-manifest 语义 |
| CI 产物 AAR | `probe-app/app/libs/git-cli-release.aar`（gitignored） | Release `v2.56.0` AAR；本批下载（sha 校验见 plan §5） |
| 消费方环境引导层契约 | [`docs/000-工程规划.md`](../../docs/000-工程规划.md) §7/§7.1/§7.3 | env 注入表与 P1–P7 判据 |
| 20261105 修复设计 | 工作区 [`docs/20261105-cli-实测问题-修复设计.md`](../../../docs/20261105-cli-实测问题-修复设计.md) | §1/§7：git 功能面零问题、范围外——本模块不修 git，只承载判据 |

## 9. 状态与遗留

- **构建**：本批（2026-11-06）AAR 落位 + `:app:assembleDebug` **BUILD SUCCESSFUL**
  （Gradle 9.4.1，1m24s；APK `probe-app/app/build/outputs/apk/debug/app-debug.apk` 7.4MB，
  lib/arm64-v8a 两件 + assets 40 条目合入）——见 `logs/20261105-1/DEV_CHECKLIST.md`。
- **设备跑批**：已存在 2026-11-03 App 域首轮记录（003-cli test-cases §F：PASS 22 / FAIL 4 /
  SKIP 0，翻译模拟器 + 真机待补测）；**本批未实跑设备**（编排者统一排队）。
- **遗留执行项 ⬜**：TC-003-17 16KB 页设备采样（P7）；原生 arm64 复测（FAIL 4 项均为翻译
  环境限制：03/06/19c realpath、12 CA 反证，见 003-cli §F）；PTY 终端交互（终端 App）。
