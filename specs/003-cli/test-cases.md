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

- 设备快照：⬜（型号/ABI/API/页大小/SELinux/网络/制品 sha256/时间）
- 结果汇总：⬜（PASS x / FAIL x / SKIP x；FAIL 明细与缺陷编号）
- 首轮执行后逐条回填状态列；FAIL 项在 TEST_REPORT.md（devflow logs 目录）展开证据。
