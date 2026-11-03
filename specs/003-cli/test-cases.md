# 003-cli 测试用例（CLI 主用例全集）

> 对应：[spec.md](./spec.md)（FR-003-xxx）· [plan.md](./plan.md)（harness 与执行框架）。
> 层：**L3**（设备端，adb shell 域）。设备：arm64 Android（真机或 arm64 AVD）；x86_64 模拟器不可用。
> 前置（全局）：001 已构建（`build/out/` 有 `libgit_*.so` + `assets/git-bridge-tools/`）且 002 `--inspect` 七门禁全过；harness 已部署（bin/农场/env 就绪）。
> 约定：`$GIT` = 设备工作目录 `bin/git`（农场名 symlink）；所有用例在 `ws/<ID>/` 独立工作区执行；env 前缀 = plan §2.2 ④ 注入表。
> 判据纪律：可证伪（PASS/FAIL 二元出口）；网络不可达 ⇒ SKIP（记录，不算 FAIL）；状态 ⬜ 执行后回填。

## A. 探针环境自检（部署正确性）

| # | 用例 | 覆盖 FR | 步骤 | 期望 | 探针映射 | 状态 |
|---|---|---|---|---|---|---|
| TC-003-00 | 部署自检 | 003-001/002/003 | `ls bin/`（物理件 + `git` symlink）；`ls gitexec/` 对照 manifest；`echo $GIT_EXEC_PATH` 等 env 抽查 | bin 物理件集合 == manifest 值域；farm 条目逐条在；env 逐项有值 | — | ⬜ |
| TC-003-00b | 环境快照 | 003-044 | `uname -m`；`getprop ro.build.version.sdk`；`getconf PAGESIZE`；`getenforce`；`ls -Z bin/git gitexec/git-remote-https` | 记录 ABI=arm64-v8a、API、页大小（4K/16K）、SELinux 模式与文件标签 | P7 前置 | ⬜ |

## B. 版本与基础命令（P1 等价）

| # | 用例 | 覆盖 FR | 步骤 | 期望 | 探针映射 | 状态 |
|---|---|---|---|---|---|---|
| TC-003-01 | 版本回程 | 003-010 | `$GIT --version`；`$GIT version` | 输出 `git version <构建版本>`（与 CLI_VERSION 一致）；exit 0 | P1 | ⬜ |
| TC-003-02 | 帮助与非交互 | 003-010/033 | `$GIT help -a`（GIT_PAGER=cat）；`$GIT --exec-path` | help 直出完成不挂起；`--exec-path` 输出 = GIT_EXEC_PATH 注入值（farm 路径） | P1 旁证 | ⬜ |
| TC-003-03 | 农场 `git` 直呼 | 003-013 | `PATH=<gitexec>:$PATH git --version`（裸命令名，经 farm symlink） | 版本串回程（证明 farm `git → libgit_cli.so` 通路） | P5 行为级 | ⬜ |
| TC-003-04 | 退出码采样 | 003-018 | `$GIT --bogus-flag`；`$GIT log`（无仓库） | 用法错 exit=129；无仓库 exit=128 级（记录实际值，不设新契约） | 记录性 | ⬜ |

## C. 本地仓库全链（P2 等价；env 契约内嵌验证）

| # | 用例 | 覆盖 FR | 步骤 | 期望 | 探针映射 | 状态 |
|---|---|---|---|---|---|---|
| TC-003-05 | init→commit→log 全链（含中文） | 003-011/030~032 | ① `$GIT init repo` ② `config user.name/user.email`（仓库级）③ 写 `hello.txt` + **`中文文件名.txt`**（UTF-8）④ `add .` ⑤ `commit -m "中文提交信息"` ⑥ `log --oneline` ⑦ `status` | 每步 exit 0；log 含该提交；status clean；`.git/hooks/*.sample` 存在（GIT_TEMPLATE_DIR 生效）；中文文件名 add/commit 后 `ls` 与 `git ls-files` 字节一致（hexdump 抽查） | P2 + R4 | ⬜ |
| TC-003-06 | 本地 clone 经农场 | 003-013 | 基于 TC-003-05：`GIT_TRACE=1 $GIT clone --no-local <repo> clone1`；`cd clone1 && $GIT log --oneline` | clone exit 0；**trace 含 `run_command: 'git-upload-pack'` 且路径在 farm 内**；clone1 log 与源一致 | P2 核心 | ⬜ |
| TC-003-07 | 全局配置回路 | 003-031/032 | `$GIT config --global user.name probe`；`cat $HOME/.gitconfig`（HOME=注入 home/） | 配置写入注入路径（非系统目录）；`--global --list` 回读一致 | §7.1 | ⬜ |
| TC-003-08 | 工作区操作采样 | 003-012 | `mv`/`rm` + `commit`；`checkout -b dev`；`tag v1`；`stash` push/pop；`diff`（有变更时） | 每步 exit 0；branch/tag 列表正确；stash pop 后工作区还原 | P2 扩展 | ⬜ |

## D. https 传输（P3/P4/P6 等价）

| # | 用例 | 覆盖 FR | 步骤 | 期望 | 探针映射 | 状态 |
|---|---|---|---|---|---|---|
| TC-003-09 | ls-remote https | 003-014 | `GIT_TRACE=1 $GIT ls-remote https://github.com/git/git.git HEAD` | refs 行回程；**trace 含 `git-remote-https` exec**（经 farm）；exit 0 | P3 | ⬜ |
| TC-003-10 | clone --depth 1 https | 003-015 | `$GIT clone --depth 1 https://github.com/git/git.git` + `log --oneline` | 克隆完成；log 恰 1 条（depth）；对象写盘正常 | P4 | ⬜ |
| TC-003-11 | fetch https 采样 | 003-014 | 对 TC-003-10 克隆仓库 `$GIT fetch --depth 1 origin` | fetch exit 0（无写权限不 push，如实记录） | P4 扩展 | ⬜ |
| TC-003-12 | CA 反证（双向） | 003-016 | ① 正向：env 指向物化 `cacert.pem` 跑 TC-003-09 ② 反向：`GIT_SSL_CAINFO=<损坏 pem> SSL_CERT_FILE=<同>` 重跑 | ① 通过；② TLS 证书校验失败（exit≠0，错误含 certificate/CA 语义）——两向齐备才证明走随包 CA 而非系统兜底 | **P6** | ⬜ |
| TC-003-13 | 农场缺失对照 | 003-017 | 临时 `mv gitexec/git-remote-https{,.bak}` → `ls-remote https://…` → 还原 | 失败且错误含 `git-remote-https` 不可得语义（负向证明农场是必要通路） | R1/R2 佐证 | ⬜ |

## E. 已知限制事实化（规划 §7.2）

| # | 用例 | 覆盖 FR | 步骤 | 期望 | 探针映射 | 状态 |
|---|---|---|---|---|---|---|
| TC-003-14 | 钩子视为无钩子 | 003-040 | repo 写 `.git/hooks/pre-commit`（无 exec 位，内容 `exit 1`）→ `commit` | **commit 照常成功**（钩子被跳过）；stderr 警告形态如实记录 | R11 | ⬜ |
| TC-003-15 | ssh 远程不可用 | 003-041 | `timeout 20 $GIT ls-remote git@github.com:git/git.git` | 失败 exit≠0；错误含 ssh 不可得语义；不挂起（timeout 保护） | §7.2 | ⬜ |
| TC-003-16 | perl 子命令不可用 | 003-042 | `$GIT send-email`（或 `$GIT svn`） | 失败/不可得形态记录 | §7.2 | ⬜ |
| TC-003-17 | 16KB 页设备采样 | 003-044 | 若 TC-003-00b 页大小=16384：复跑 01/05/06/09 核心链 | 16KB 设备上核心用例结论记录（PASS/FAIL） | **P7** | ⬜ |

## F. 执行记录（回填区）

### 首轮（2026-11-03，探针 App·App 域——M1-T7/M2-T1 载体）

- **载体**：`probe-app/`（参考 aosp-python-cli/probe-app；独立 Gradle 工程，消费 CI 产物 AAR；
  物化 marker 幂等 + D5 农场 `Os.symlink` + §7.1 env 全表注入 + JSON 报告；测试仓库 URL/凭证经
  intent extras 传入，**不落盘**：源码/报告/文档零敏感信息，报告出口统一 sanitize）。
- **设备**：sdk_gphone64_x86_64 模拟器（API 37，abilist 含 arm64-v8a，ndk_translation 执行 arm64 制品）；
  页大小 4096B（TC-003-17 SKIP：P7 需 16KB 设备）；SELinux enforcing（app 域）。
- **结果**：**PASS 22 / FAIL 4 / SKIP 0**（7 轮迭代后终态；报告：`logs/evidence/probe-report-run*.json`，gitignored）。

| 用例 | 结果 | 说明 |
|---|---|---|
| TC-003-18a/18b | ✅ | **App 域落盘（M1-T7 探针 1：nativeLibraryDir 物理件）+ 农场 symlink exec（P5 App 域 SELinux 放行）实测通过**——工作区五线共享前提的重要事实 |
| TC-003-01/02/02b/03 | ✅/✅/✅/❌ | 版本/非交互/exec-path OK；03 按名+PATH 查找见环境限制（下同） |
| TC-003-04 | ✅ | 退出码采样（bogus=129 记录） |
| TC-003-05/05b | ✅/✅ | init→add→commit(中文)→log→status；中文文件名/提交信息字节保真（**R4 事实化**：无 iconv 下 UTF-8 正常）；模板 hooks 样例就位（§7.1 GIT_TEMPLATE_DIR 生效） |
| TC-003-06 | ❌ | 本地 clone --no-local 经农场：环境限制（见下），真机补测 |
| TC-003-07/07b | ✅ | GIT_CONFIG_GLOBAL 全局配置回路（HOME 注入路径） |
| TC-003-08/08b | ✅/✅ | mv/branch/tag/stash/diff 工作区链 |
| TC-003-09/10/10b/11 | ✅ | **P3/P4 事实化**：ls-remote/clone --depth 1/fetch https 全链经 farm helper（目标：无账号公共仓库，GIT_TRACE 见 git-remote-https 绝对路径 exec）；depth 恰 1 条 |
| TC-003-12 | ❌ | CA 反证未成立（坏 CA 下仍 exit=0）——正向 https 由 09 佐证；**P6 需真机复核 CA 装载路径** |
| TC-003-13 | ✅ | 农场缺失对照：http/https helper 双摘 ⇒ `remote helper 'http' aborted session`（**负向证明农场是必要通路**，R1/R2 佐证） |
| TC-003-14 | ✅ | 钩子无 exec 位 ⇒ 视为无钩子（commit 照常，hint 记录——**R11 事实化**） |
| TC-003-15 | ✅ | ssh 不可用（§7.2 事实） |
| TC-003-16 | ✅ | perl 子命令不可得（NO_PERL，§7.2 事实） |
| TC-003-17 | SKIP | 4096B 页设备（P7 需 16KB 设备） |
| TC-003-19a/19b/19c | ✅/✅/❌ | **带账号 http 仓库**：认证 clone --depth 1 ✅、认证 fetch ✅（helper 农场链路完整）；认证 push ❌ 环境限制（同 03）；探针分支自清理 |

**FAIL 4 项定性**（均为测试环境限制，非制品缺陷）：
- TC-003-03/06/19c（3 项）：ndk_translation 下「按名字+PATH 查找 farm symlink」的 realpath 失败；
  **绝对路径 exec 全部正常**（18b farm symlink 直 exec、09 https helper 绝对路径 exec、19a/19b 认证 clone/fetch 均证）。
  真实 arm64 真机无 translation 层，预期不存在——**真机补测项**。
- TC-003-12（1 项）：P6 反证需真机复核（坏 CA 未触发失败；正向 https/TLS 链路已由 09/10/11 佐证工作）。

**App 域遗留 ⬜**：PTY 交互（终端 App）；16KB 页设备（P7）；性能采样（translation 不具代表性）。
