# 101-probe-app — 设备侧回程探针载体（probe-app）技术方案（plan.md）

> **性质**：**实现特定（as-built）**。本模块的「实现」就是 `probe-app/` 现有代码；本文档逆向
> 记录真实实现（对照规格 [spec.md](./spec.md) 的 `FR-101-PROBE-001…011`）。
> **技术栈事实**：独立 Gradle 工程（不在根 settings.gradle 内——000 单模块红线不动，见
> `probe-app/build.gradle.kts:1-6`）；Gradle 9.4.1 + AGP 9.2.1（`probe-app/build.gradle.kts:4-6`）；
> 纯 Java（org.json 报告）；无 AndroidX（`probe-app/gradle.properties:2`）。
> **状态**：✅ as-built 归档；构建修齐（本批 2026-11-06）；设备实跑由编排者统一排队。

---

## 1. 技术上下文

| 项 | 取值 | 说明 |
|---|---|---|
| 载体模块 | `probe-app/app`（applicationId `org.fellow99.gitprobe`） | `app/build.gradle.kts:6-16`；`minSdk 24` / `targetSdk 35` / `compileSdk 36` |
| ABI | 仅 `arm64-v8a`（`abiFilters`） | `app/build.gradle.kts:16`；禁止判据 3（x86_64 模拟器不得冒充，翻译环境结果仅记录） |
| 依赖制品 | `app/libs/git-cli-release.aar`（CI Release 归档解包） | `app/build.gradle.kts:38`；本批下载落位（AAR 6,152,277 B ≈ 5.9 MiB） |
| exec 入口 | `nativeLibraryDir/libgit_cli.so` + helper `libgit_remote_curl.so` | `MainActivity.java:64-67`（gitExe = nativeDir/libgit_cli.so） |
| 物化目标 | `filesDir/git-bridge-tools` + `filesDir/gitexec` + `filesDir/home`/`tmp`/`ws` | `MainActivity.java:66-67, 197-210, 224-226` |
| 期望值 | git 2.56.0（派生于 lock `active.version`，判据内嵌 `"git version 2.56.0"`） | `app/gradle.properties:4`（PROBE_APP_VERSION）；`MainActivity.java:310` 等 |
| 设备跑批基线 | `specs/003-cli/test-cases.md` §F（2026-11-03：PASS 22 / FAIL 4 / SKIP 0，翻译模拟器） | 本批未重跑设备 |

## 2. 宪法合规

| 条目 | 落点 |
|---|---|
| C2 唯一事实源 | 预期版本 2.56.0 与 `git-cli.lock.json` `active.version` 一致（`gradle.properties:4`）；AAR 内 `.so` sha256 与 lock `releases[].sha256` 逐条比对（见 §5） |
| C3 二进制不入库 | `probe-app/.gitignore:4` 忽略 `app/libs/*.aar`；AAR 不提交（`git status` 确认 untracked） |
| C5 发布卫生 | 探针 App 不发布；`gradle.properties:1-2` 无发布凭据 |
| C6 未实测标 ⬜ | TC-003-17（16KB 页）/原生 arm64 复测标 ⬜；本批设备实跑 ⬜（编排者排队） |
| C7 未实测不得当已测 | 003 §F 的 4 项 FAIL 明确标「环境限制/真机补测」，不当作制品缺陷 |
| C8 先改文档再改实现 | 本模块 as-built 文档只逆向后补，不改 probe-app 代码 |

## 3. 实现结构（as-built 真实文件与行数）

| 文件 | 行数（实测 2026-11-06） | 职责 |
|---|---|---|
| `probe-app/app/src/main/java/org/fellow99/gitprobe/MainActivity.java` | 625 | 物化 / 农场 / 注入 / 执行器 / 探针表 / 报告（详见 §4） |
| `probe-app/app/build.gradle.kts` | 39 | application 配置 + 仅 arm64 ABI + `useLegacyPackaging=true` + AAR 依赖 |
| `probe-app/build.gradle.kts` | 6 | 根工程（`com.android.application` 插件声明 AGP 9.2.1 apply false，独立工程） |
| `probe-app/settings.gradle.kts` | 16 | pluginManagement / dependencyResolutionManagement(FAIL_ON_PROJECT_REPOS) / include ":app" |
| `probe-app/gradle.properties` | 4 | `org.gradle.jvmargs=-Xmx2g` · `android.useAndroidX=false` · `PROBE_APP_VERSION=2.56.0` |
| `probe-app/app/src/main/AndroidManifest.xml` | 20 | 仅 `INTERNET`；`extractNativeLibs=true`；单一 LAUNCHER activity |
| `probe-app/.gitignore` | 4 | `.gradle/`/`build/`/`local.properties`/`app/libs/*.aar` |

> 与参照工程（aosp-node-cli / aosp-pnpm-cli 的 probe-app）的差异：git 版无
> `androidResources { ignoreAssetsPattern = … }` 覆写——因本 AAR `assets/git-bridge-tools/**`
> **无 dot 文件**（`unzip -Z1` 校验 0 个以 `.` 开头的条目；`manifest.json` 列出的
> `templates/.gitignore` 实际未随包，AAR 内无此文件，见 §7）。故无需覆写也是可构建的。

## 4. 关键实现点（每条可回溯）

1. **物化（FR-101-PROBE-002）**：`materialize()`（`MainActivity.java:126-141`）先
   `assetsMarker()`（112-124）读 assets 内 `manifest.json` 的 `totalSha256`，与
   `SharedPreferences("probe").tools.sha` 比对；一致且 `toolsDir/manifest.json` 已存在则跳过，
   否则 `deleteRecursive` 清残留后 `copyAssetTree()`（143-166）递归物化。
2. **农场（FR-101-PROBE-003，D5/R2）**：`buildFarm()`（`MainActivity.java:168-187`）读
   `gitexec-manifest.json` 的 `farm` 表，`android.system.Os.symlink(nativeDir/<phys>, filesDir/gitexec/<name>)`
   先清后建；返回 `"farm=N 条（symlink → nativeDir）"`；含 `FAIL` 则 runAll 抛
   `IllegalStateException`（`MainActivity.java:546-548`）。
3. **注入（FR-101-PROBE-004）**：`baseEnv()`（`MainActivity.java:197-210`）构造规划 §7.1 全表；
   `exec()`（220-260）做进程 env 清空后 `putAll(baseEnv)` + `ANDROID_ROOT`/`ANDROID_DATA`/
   `LD_LIBRARY_PATH`（233-235）；`envOverride` 在 runAll 逐条应用（value null/empty → remove，
   `MainActivity.java:565-569`）。
4. **执行器（FR-101-PROBE-005）**：`ProcessBuilder(argv)` 直 exec 绝对路径
   `nativeDir/libgit_cli.so`（`git()` 组装，294-299）；`directory=filesDir/ws`；stdout/stderr
   双 pump 线程（262-272）；`waitFor(timeoutMs)` 超时 `destroyForcibly`（246-249）；异常折入
   `failReason` 不抛。
5. **探针表（FR-101-PROBE-006/007）**：`probes()`（`MainActivity.java:301-479`）返回 26 条
   `new Probe(...)`；TC-003-17 页大小采样由 runAll 内 `getconf PAGESIZE` 驱动
   （`MainActivity.java:596-603`）。工具：`arr()`（481-486）/`envKv()`（488-492）。
6. **判据形态**：runner 按 check 返回前缀归类 PASS/SKIP/BLOCKED/FAIL（`MainActivity.java:572-577`）；
   `SKIP:…` 出现在依赖 extras 或依赖前置的用例（详见 test-cases.md）；「如实记录」类
   （03 realpath 环境限制、15/16 已知限制）在 check 内返回对应形态字符串。
7. **报告（FR-101-PROBE-009）**：`runAll()` 尾部汇总四计数 + `runAt/device/pagesize/nativeDir/farm`
   头 + `probes[]`（逐条 id/title/verdict/detail/exit/ms/stdout/stderr，head() 截断 800）写
   `filesDir/probe-report.json`（`MainActivity.java:582-619`），UI 侧逐条 `log()`。
8. **脱敏（FR-101-PROBE-010）**：`sanitize()`（`MainActivity.java:495-504`）打码
   authPass/authUser、replace authUrl → redacted、credPattern `//***:***@`；报告/日志/UI 出口
   统一过此函数。
9. **无头触发（FR-101-PROBE-011）**：`onCreate`（`MainActivity.java:62-101`）读
   `--es git_public_url / git_auth_url / git_user / git_pass` 与 `--ez autorun true`（100 行），
   autorun 直接 `runAll()`。

## 5. AAR 获取与完整性校验（本批构建修齐核心动作）

- **下载**：`https://github.com/fellow99/aosp-git-cli/releases/download/v2.56.0/git-cli-v2.56.0-android-arm64-v8a-aar.aar`
  （6,152,277 B；经本机代理 `127.0.0.1:7890` 直连 github.com 超时，走代理成功）。
- **落位**：`probe-app/app/libs/git-cli-release.aar`（gitignored，不入库）。
- **校验（对 lock 逐条比对，`git-cli.lock.json`）**：

| 文件（AAR 内） | 大小 | sha256（实测） | lock 期望 | 结论 |
|---|---|---|---|---|
| `jni/arm64-v8a/libgit_cli.so` | 3,993,328 | `17171683…8bab` | `17171683…8bab`（releases[].sha256） | ✅ 一致 |
| `jni/arm64-v8a/libgit_remote_curl.so` | 8,450,536 | `fc25b57e…6afe27` | 非可复现（lock 注：b2d7a0a6@65118fa vs **fc25b57e@6da0c34** 为已知两值） | ✅ 属 lock 登记的已知两值之一（buildEvidence commit 6da0c34 一致） |

- Release 侧未提供 `.sha256` 资产（尝试 5 种命名均 404），故以 lock 字段 + AAR 内
  `manifest.json` 逐文件 sha256 为核验依据（后者为 provision 构建期生成，见资产 `manifest.json`）。
- **明文记录**：`git-cli.lock.json` `releases[].status="released"`，`builtFrom.buildEvidence` 与
  实测 sha 一致——AAR 为已发布真实产物。

## 6. 构建与部署命令（DEV 侧，本批已验证）

```bash
# 项目自带 Gradle 9.4.1 发行版（aosp-node-cli/.dist/gradle-dist/gradle-9.4.1/bin/gradle）
distGradle="/d/node-bridge-workspace/aosp-node-cli/.dist/gradle-dist/gradle-9.4.1/bin/gradle"
cd /d/node-bridge-workspace/aosp-git-cli/probe-app
"$distGradle" :app:assembleDebug --console=plain
# 结果：BUILD SUCCESSFUL in 1m 24s，35 tasks（2026-11-06；依赖经 ~/.gradle 代理 7890 解析）
# 产物：probe-app/app/build/outputs/apk/debug/app-debug.apk（7,416,309 B）
#   含 lib/arm64-v8a/libgit_cli.so + libgit_remote_curl.so + assets/git-bridge-tools 40 条目

# 设备侧（编排者后续排队执行，本批未跑）
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n org.fellow99.gitprobe/.MainActivity \
  --ez autorun true --es git_public_url <public> --es git_auth_url <url> --es git_user <u> --es git_pass <p>
adb shell run-as org.fellow99.gitprobe cat files/probe-report.json > probe-report.json
```

## 7. 不一致与风险登记（as-built 如实）

| # | 项 | 处置 |
|---|---|---|
| 1 | 期望版本 `"git version 2.56.0"` **内嵌**于判据串（`MainActivity.java:310/316/321/332` 等），未像 node 版以 lock 常量引用——版本升级需同步改判据与 `gradle.properties:4` | 与 `PROBE_APP_VERSION`/lock `active.version` 三方当前一致；未来换版时以 C2 纪律统一（本批不改动，规避无谓 diff） |
| 2 | Release AAR 的 `manifest.json` 列出 `templates/.gitignore`，但该文件**未随 AAR 打包**（zip 实测无此条目）——生产侧（001/002 assets 收集）疑似 aapt/dot 过滤丢了 1 件 | 属生产侧问题、不在 101 范围；本模块无树完整性判据，装上不影响任何探针；登记供 002 追踪 |
| 3 | 无 `ignoreAssetsPattern` 覆写（vs node 版） | 因本 AAR 无 dot 文件（zip 实测 0），默认过滤无影响，构建已证可（§5/§6） |
| 4 | TC-003-13 依赖 auth extras；未提供时按代码现行为 `git --version` 且判据返回 `FAIL(未还原)`（脚本未运行即「未还原」，可视为如实记录） | as-built 如实；若需 SKIP 口径由未来维护统一（本批只记录） |
| 5 | 翻译模拟器 ≠ 原生 arm64（003 §F 环境限定） | 正式 G3 需原生 arm64 复测；FAIL 4 项均为环境限制不属制品缺陷 |

## 8. FR 交叉引用

| FR | 落点 |
|---|---|
| FR-101-PROBE-001 | `probe-app/build.gradle.kts:1-6` + `app/build.gradle.kts:38` + settings.gradle.kts:16 |
| FR-101-PROBE-002 | `MainActivity.java:112-141`（materialize / assetsMarker） |
| FR-101-PROBE-003 | `MainActivity.java:168-187`（buildFarm，D5） |
| FR-101-PROBE-004 | `MainActivity.java:197-210`（baseEnv，§7.1） |
| FR-101-PROBE-005 | `MainActivity.java:220-260`（exec）+ `294-299`（git） |
| FR-101-PROBE-006 | `MainActivity.java:276-292`（Probe/Check）+ `572-581`（verdict） |
| FR-101-PROBE-007 | `MainActivity.java:301-479`（probes()）+ `596-603`（TC-003-17） |
| FR-101-PROBE-008 | 判据内 `"SKIP:…"` 分支（09/10/10b/11/12/13/19a/19b/19c） |
| FR-101-PROBE-009 | `MainActivity.java:582-619`（报告 JSON） |
| FR-101-PROBE-010 | `MainActivity.java:52-57, 92-99, 495-504`（sanitize） |
| FR-101-PROBE-011 | `MainActivity.java:89-100`（autorun intent） |

## 9. 文件清单（本模块，as-built 快照 2026-11-06）

- 新增（本批）：`spec.md` / `plan.md` / `test-cases.md` / `tasks.md`（`specs/101-probe-app/`）；
  `logs/20261105-1/DEV_CHECKLIST.md`（gitignored 证据）。
- 新增（本批非入库）：`probe-app/app/libs/git-cli-release.aar`（gitignored）。
- 既有（as-built 源，未改动）：`app/build.gradle.kts`（39 行）/ `probe-app/build.gradle.kts`（6）/
  `settings.gradle.kts`（16）/ `gradle.properties`（4）/ `AndroidManifest.xml`（20）/ `.gitignore`（4）/
  `MainActivity.java`（625）。
- 修改（本批）：`specs/SPECS_CHECKLIST.md`（+101 模块行）/ `specs/README.md`（+模块索引）。
- 未实现清单：无（本模块已是实现态；遗留仅为「原生 arm64 复测 / 16KB 设备 / 设备实跑」执行项，
  非文档缺口）。
