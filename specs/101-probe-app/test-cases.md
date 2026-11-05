# 101-probe-app 测试用例（probe-app 实际实现的探针正典，as-built）

> 对应：[spec.md](./spec.md)（FR-101-PROBE-001…011）· 上游判据源：[`../003-cli/test-cases.md`](../003-cli/test-cases.md)
> （TC-003-01…19，L3）· 规划判据：`docs/000-工程规划.md` §7.1（env 表）/§7.3（P1–P7）。
> **本表 = `probe-app/app/src/main/java/org/fellow99/gitprobe/MainActivity.java` `probes()` 实际
> 实现清单**（as-built，行号 = 2026-11-06 快照）。
> **环境口径**：`device` = 装载 AAR 并可注入 env 的 arm64 设备；`host` = 构建机。
> **设备判据纪律**：arm64 真机/arm64 模拟器；x86_64 模拟器经 ndk_translation 可装可跑但**仅记录**、
> 正式 G3 需原生 arm64 复测（003 禁止判据 3）。
> **期望值**：git `<ver>=2.56.0`（`gradle.properties:4` PROBE_APP_VERSION = lock `active.version`；
> 判据判 `git version 2.56.0`）。

## 一、探针全表（device，MainActivity.probes() 26 条 + runAll 内 TC-003-17 共 27 判据点）

| # | 用例 | 前置 | 命令（argv） | 期望（可证伪 / 判据） | FR | 端点/SKIP 口径 | 状态 |
|---|---|---|---|---|---|---|---|
| TC-003-18a | App 域落盘：nativeLibraryDir 物理件 | AAR 就位装 APK | `libgit_cli.so --version`（绝对路径） | `nativeLibraryDir/libgit_cli.so` isFile && canRead && exit 0 && stdout 含 `git version 2.56.0` | FR-101-PROBE-007 | 无 | ⬜ 设备待跑（2026-11-03 模拟器 ✅） |
| TC-003-18b | App 域农场：gitexec symlink exec（P5） | 农场已建 | `filesDir/gitexec/git --version` | exit 0 && stdout 含 `git version 2.56.0`（app 域 SELinux 放行事实，R2） | FR-101-PROBE-003/007 | 无 | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-01 | 版本串回程 | env 注入 | `git --version` | exit 0 && stdout 含 `git version 2.56.0` | FR-101-PROBE-007 | 无 | ⬜ 设备待跑 |
| TC-003-02 | `--exec-path` 指向注入农场 | env 注入 | `git --exec-path` | exit 0 && stdout.trim() == `filesDir/gitexec`（GIT_EXEC_PATH 生效） | FR-101-PROBE-004/007 | 无 | ⬜ 设备待跑 |
| TC-003-02b | `help -a` 非交互直出（GIT_PAGER=cat） | env 注入 | `git help -a` | exit 0 && stdout.length() > 100（不挂起） | FR-101-PROBE-004/007 | 无 | ⬜ 设备待跑 |
| TC-003-03 | farm `git` PATH 直呼（裸命令经 gitexec） | 农场已建 | `sh -c "PATH=<gitexec>:/system/bin git --version"` | exit 0 && stdout 含版本；**环境限制**：输出含 `Unable to get realpath` ⇒ FAIL(ndk_translation 特判，真机补测) | FR-101-PROBE-003/007 | 无 | ⬜ 设备待跑（2026-11-03 ❌ 环境限制） |
| TC-003-04 | 退出码采样（用法错） | env 注入 | `git --bogus-flag` | exit ∈ {129, 1}（记录性，不设新契约） | FR-101-PROBE-007 | 无 | ⬜ 设备待跑 |
| TC-003-05 | init→add→commit→log 全链 + 模板 hooks | 工作区 ws | `git init <ws>/repo` | exit 0（或 stdout 含 `already exists` 复跑容忍）；链式断言由 05b 完成 | FR-101-PROBE-007 | 无 | ⬜ 设备待跑 |
| TC-003-05b | 中文文件名/提交信息 + status + hooks sample（P2+R4） | TC-003-05 后 | `sh -c "G=<gitExe>; …add 中文文件名… commit -m '中文提交信息'… log… status… ls hooks/pre-commit.sample… ls-files 计数=2… echo CJK_OK"` | exit 0 && stdout 含 `中文提交信息`/`STATUS_OK`/`HOOKS_OK`/`CJK_OK`（UTF-8 字节保真，R4 事实化） | FR-101-PROBE-007 | 无 | ⬜ 设备待跑 |
| TC-003-06 | 本地 clone --no-local 经农场（GIT_TRACE） | repo 已 init | `git clone --no-local <repo> <ws>/clone1`（env GIT_TRACE=1） | exit 0 && stderr 含 `upload-pack`（trace 见 dashed 子进程经农场）；`Unable to get realpath` ⇒ 环境限制 FAIL | FR-101-PROBE-003/007 | 无 | ⬜ 设备待跑（2026-11-03 ❌ 环境限制） |
| TC-003-07 | 全局配置回路（GIT_CONFIG_GLOBAL） | env 注入 | `git config --global user.name probe` | exit 0（写入注入 HOME/.gitconfig） | FR-101-PROBE-004/007 | 无 | ⬜ 设备待跑 |
| TC-003-07b | 全局配置 user.email | TC-003-07 后 | `git config --global user.email probe@test.local` | exit 0 | FR-101-PROBE-004/007 | 无 | ⬜ 设备待跑 |
| TC-003-08 | 工作区操作采样（branch/tag/stash，init 起点） | 工作区 ws | `git init <ws>/wsrepo` | exit 0 或 stdout 含 `already exists`；后续链式由 08b | FR-101-PROBE-007 | 无 | ⬜ 设备待跑 |
| TC-003-08b | 工作区链：mv/branch/tag/stash/diff | TC-003-08 后 | `sh -c "…add/commit/mv/commit/checkout -b dev/tag v1/stash/pop/diff --stat/branch --show-current/tag… echo WS_OK"` | exit 0 && stdout 含 `WS_OK` && `v1` | FR-101-PROBE-007 | 无 | ⬜ 设备待跑 |
| TC-003-09 | ls-remote https 经 farm helper（P3） | env 注入 | `git ls-remote <pubUrl> HEAD`（env GIT_TRACE=1） | exit 0 && stdout 匹配 `(?s)[0-9a-f]{40}.*HEAD.*`；`Could not connect` ⇒ SKIP（网络环境特定） | FR-101-PROBE-003/004/007 | **SKIP**：未提供 `git_public_url` extra | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-10 | clone --depth 1 https（P4） | env 注入 | `git clone --depth 1 <pubUrl> <ws>/gclone` | exit 0；`Could not connect` ⇒ SKIP | FR-101-PROBE-003/004/007 | **SKIP**：未提供 `git_public_url` extra | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-10b | clone 后 log 恰 1 条（depth 生效） | TC-003-10 成功 | `git log --oneline`（GIT_DIR=<ws>/gclone/.git） | 若 gclone/.git 不存在 ⇒ `SKIP:依赖 TC-003-10 克隆成功`；否则 exit 0 && stdout 行数 == 1 | FR-101-PROBE-007 | **SKIP**：依赖 TC-003-10 | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-11 | fetch https（origin 采样） | TC-003-10 成功 | `git fetch --depth 1 origin`（GIT_DIR=gclone/.git） | 若 gclone/.git 不存在 ⇒ SKIP；否则 exit 0 | FR-101-PROBE-007 | **SKIP**：依赖 TC-003-10 | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-12 | CA 反证：损坏 CA ⇒ TLS 失败（P6） | TC-003-10 + pubUrl | `git ls-remote <pubUrl> HEAD`（env GIT_SSL_CAINFO/SSL_CERT_FILE=<bad-ca.pem>） | 若 gclone/.git 不存在 ⇒ `SKIP:依赖 TC-003-10`；否则 exit != 0 且 stderr 含 certificate/ssl/ca 语义；exit==-1 ⇒ FAIL(超时) | FR-101-PROBE-004/007 | **SKIP**：依赖 TC-003-10（需可连 https 端点） | ⬜ 设备待跑（2026-11-03 ❌ 真机复核） |
| TC-003-13 | 农场缺失对照：helper 双摘 ⇒ 不可得（自恢复） | auth 端点 | `sh -c "cd <gitexec> && mv git-remote-http .b1 && mv git-remote-https .b2; git -C <ws> ls-remote <credUrl> …; mv 还原; echo RESTORED; echo RC=$RC"` | exit 0 && stdout 含 `RESTORED`；`RC=0` ⇒ `意外成功`（FAIL）；`RC=128||1` ⇒ PASS（负向证明农场必要，R1/R2）；未含 RESTORED ⇒ FAIL(未还原) | FR-101-PROBE-003/007 | **依赖** `git_auth_url` extras（credUrl 构造）；未提供时按现状记录 FAIL(未还原) | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-19a | 带账号 clone --depth 1（http 认证） | auth extras | `git clone --depth 1 <credUrl> <ws>/arepo` | `!authReady` ⇒ `SKIP:未提供 git_auth_url/git_user/git_pass extras`；否则 exit 0 | FR-101-PROBE-007/008 | **SKIP**：缺 auth extras | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-19b | 带账号 fetch（origin 采样） | TC-003-19a 成功 | `git fetch --depth 1 origin`（GIT_DIR=arepo/.git） | `!authReady` ⇒ SKIP；arepo/.git 不存在 ⇒ `SKIP:依赖 TC-003-19a`；否则 exit 0 | FR-101-PROBE-007/008 | **SKIP**：缺 auth extras / 依赖 19a | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-19c | 带账号 push（推探针分支 + 自清理） | TC-003-19a 成功 | `sh -c "git -C <arepo> push origin HEAD:refs/heads/probe-gitcli-test && git -C <arepo> push origin --delete probe-gitcli-test && echo PUSH_OK"` | `!authReady` ⇒ SKIP；arepo/.git 不存在 ⇒ SKIP；exit 0 && stdout 含 `PUSH_OK`；realpath 特判 FAIL(环境限制) | FR-101-PROBE-007/008 | **SKIP**：缺 auth extras / 依赖 19a | ⬜ 设备待跑（2026-11-03 ❌ 环境限制） |
| TC-003-14 | 钩子不可 exec ⇒ 视为无钩子（commit 照常，R11） | repo + 无 exec 位 pre-commit 钩子 | `git commit --allow-empty -m hookless`（GIT_DIR=repo/.git） | exit 0（钩子跳过；警告形态如实记录） | FR-101-PROBE-004/007 | 无 | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-15 | ssh 远程不可用（无 ssh 二进制，记录性） | env 注入 | `git ls-remote git@github.com:octocat/Hello-World.git` | exit != 0（或 failReason != null）⇒ PASS（§7.2 事实）；`意外成功` ⇒ FAIL | FR-101-PROBE-007 | 无 | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-16 | perl 子命令不可得（send-email 未编译，记录性） | env 注入 | `git send-email` | exit != 0 && stderr 含 `not a git command`/`send-email` ⇒ PASS（§7.2 事实） | FR-101-PROBE-007 | 无 | ⬜ 设备待跑（2026-11-03 ✅） |
| TC-003-17 | 16KB 页设备采样（P7） | runAll 内独立驱动 | `/system/bin/getconf PAGESIZE` | `16384` ⇒ PASS（核心链本报告已全执行）；否则 SKIP（P7 需 16KB 设备复跑） | FR-101-PROBE-007 | 无（环境页大小判定） | ⬜ 设备待跑（2026-11-03 SKIP，4096B） |

> **说明**：
> 1. TC-003-17 不在 `probes()` 内，由 runAll 末尾 `getconf PAGESIZE` 判定（`MainActivity.java:596-603`）。
> 2. 判据体（check lambda）首行即 SKIP 分支的用例 = TC-003-09/10（pubUrl）、10b/11/12（依赖
>    10）、19a/19b/19c（authReady 与依赖）——未满足条件时返回 `"SKIP:…"`，runner 归类 SKIP
>    （`MainActivity.java:572-577`），**不伪造 PASS/FAIL**。
> 3. 「已知限制事实化」探针（15/16）在 check 内以「预期失败即 PASS + 记录性」承载，与 003 正典
>    禁止判据 1/4 一致（只记录事实，不断言上游文案逐字）。
> 4. 探索性 FAIL 特判：TC-003-03/06/19c 的 `Unable to get realpath` 为 ndk_translation 环境限制
>    分支（绝对路径 exec 均正常，03 → 18b 印证），如实返回 FAIL(环境特定:…真机补测)。

## 二、端点依赖 extras 的 SKIP 口径说明（FR-101-PROBE-008，§7）

测试仓库端点/凭证**仅经 launch intent extras 注入、不落盘**（`MainActivity.java:52-57, 92-99`）：

| extra | 用例依赖 | 未注入时的处置 |
|---|---|---|
| `git_public_url`（无账号 https 仓库） | TC-003-09 / 10（端点本体），10b/11/12（依赖克隆） | 判据返回 `SKIP:未提供 git_public_url extra` / `SKIP:依赖 TC-003-10` |
| `git_auth_url` + `git_user` + `git_pass`（带账号 http(s) 仓库） | TC-003-13（农场缺失对照，credUrl 构造）、19a/19b/19c | 判据返回 `SKIP:未提供凭证 extras`（19a/b/c）；TC-003-13 按 as-built 现行为 `git --version` + `FAIL(未还原)`（见 plan §7#4） |
| 无 extras（纯本地） | 其余全部 | 不依赖端点，正常执行（本地全链/已知限制闭环） |

> 判据纪律：SKIP 是**如实声明**（端点不可得/网络不可达/依赖前置失败），不当作 PASS 也不当作 FAIL；
> 网络「Could not connect」专分支（TC-003-09/10）同样走 SKIP（003 判据纪律：网络不可达 ⇒ SKIP）。

## 三、host 侧用例（构建机——载体 App 本身）

| # | 用例 | 环境 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|
| TC-101-PROBE-16 | probe-app 编译产出 | host | `gradle :app:assembleDebug --console=plain`（Gradle 9.4.1，AAR 已落位） | `app/build/outputs/apk/debug/app-debug.apk` 产出；exit 0 | ✅ 2026-11-06（BUILD SUCCESSFUL 1m24s） |
| TC-101-PROBE-17 | 探针实现与正典映射核对 | host | Grep `probes()` 各 `new Probe(id,…)` | id 全集 = 本表（18a/18b/01…08/09…13/19a/b/c/14/15/16 + 05b/08b + 17） | ✅ 2026-11-06（26 条 + 17） |
| TC-101-PROBE-18 | AAR 完整性与 lock 对照 | host | 解 AAR，`sha256sum` 两件 `.so` 比对 `git-cli.lock.json` | 与 lock 逐条一致（libgit_cli 精确匹配；libgit_remote_curl 为 lock 登记的已知两值之一） | ✅ 2026-11-06 |
| TC-101-PROBE-19 | AAR 不入库检查 | host | `git check-ignore app/libs/git-cli-release.aar` + `git status` | 返回 ignore（`probe-app/.gitignore:4`），AAR 为 untracked 不入库 | ✅ 2026-11-06 |

## 四、事实记录区（回填处，C6）

| 项 | 值 | 记录时间 |
|---|---|---|
| 构建产物 | `app-debug.apk` 7,416,309 B；lib/arm64-v8a 两件 + assets 40 条目合入 | 2026-11-06 host |
| AAR 校验 | main 二进制 sha256 与 lock 精确一致；helper 为 lock 已知两值之一（fc25b57e @ commit 6da0c34） | 2026-11-06 |
| 设备首轮跑批（App 域，翻译模拟器） | PASS 22 / FAIL 4 / SKIP 0（003-cli test-cases §F；FAIL 3 项 realpath + 1 项 CA 反证，均环境限制真机补测） | 2026-11-03 |
| TC-003-17 页大小 | 4096B ⇒ SKIP（P7 需 16KB 设备） | 2026-11-03 |

## 五、禁止的判据

1. 不得在 x86_64 模拟器上执行 arm64 产物探针并记录为通过——翻译环境结果仅记录，正式 G3 需
   原生 arm64 复测（003 禁止判据 3）。
2. 依赖 `git_public_url`/`git_auth_url` extras 的用例未提供端点/凭证时**不得**伪造 PASS 或
   臆断 FAIL——必须走判据内的 SKIP 分支（FR-101-PROBE-008）。
3. CA 反证（TC-003-12）正反两向齐备才证明走随包 CA；单向（正向由 09/10 佐证）不得下 P6 结论。
4. 「记录性/事实化」条目（TC-003-04 退出码、15/16 已知限制、03/06/19c 环境限制）不得事后改写
   为硬断言。
5. TEST 仓库 URL/凭证（extras）不得写入源码、报告、日志或本文档——报告出口统一 sanitize
   （FR-101-PROBE-010）。

## 附、统一队列跑批记录（2026-11-06）

- 载体：`emulator-5554`（sdk_gphone64_x86_64 API 37 × ndk_translation；App 域 ABI=arm64）；由编排者统一排队串行执行（安装→`--ez autorun true`→`run-as cat` 回读报告）。
- 报告：`logs/20261105-1/report-git.json`（工程内留档，不入库）。
- 汇总：26 探针：PASS 15 / FAIL 3 / SKIP 8（FAIL=TC-003-03/06 realpath 环境限制 + TC-003-13 无 auth extras 按现状 FAIL(未还原)；SKIP=缺 extras/依赖）。
- 判读纪律：翻译模拟器结果**仅记录**，正式 G3 需原生 arm64 复测；FAIL/BLOCKED 均按本节/Spec 既有分类如实记录，未伪造 PASS。
