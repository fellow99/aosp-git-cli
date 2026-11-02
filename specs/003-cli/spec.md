# 003 · CLI 运行期验证（cli）功能规格

> 模块：003-cli · 状态：⬜ 规划已立项（规划 §10.2）· 所属工程：aosp-git-cli
> 规划基线：[`docs/000-工程规划.md`](../../docs/000-工程规划.md) §7（运行期契约：env 注入表/已知限制/回程探针 P1–P7）
> 覆盖任务：M1-T7（最小消费探针·本仓可执行部分）/ M2-T2（真机回程 P1–P7·不依赖消费方 App 的判据）

## 1. 目的

回答一个问题：**`libgit_cli.so` + helper 集在真实 Android（arm64）上，作为命令行到底能不能用、好用成什么样**。
以 adb shell 域（`/data/local/tmp` 可 exec）为本仓可执行的验证载体：物化随包数据、建 symlink 农场、
注入 env 契约（规划 §7.1），逐用例验证 CLI 行为并把结果回写为**事实**（⬜ → ✅/❌）。

**边界声明（防过度承诺）**：adb 探针验证的是 **shell 域**的二进制本体行为；App 域结论
（nativeLibraryDir 落盘、targetSdk≥29 app 域 SELinux、PTY 交互）仍归消费方（M1-T7 对照/M2-T1）⬜。

## 2. 功能需求（FR-003-xxx，RFC 2119；判据可证伪）

### 2.1 探针环境（test harness，本仓交付）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-003-001 | MUST | 提供设备部署工具：推送 `libgit_*.so` 全集 + assets（templates/cacert/manifest）到设备工作目录，设置可执行位 | 部署后设备目录清单与制品集一致；主二进制可执行 |
| FR-003-002 | MUST | 提供**农场创建器**：按 gitexec-manifest.json 在设备工作目录 `gitexec/` 下建原名 symlink（幂等：先清后建） | farm 内 symlink 名与 manifest 条目一致；重复执行结果一致 |
| FR-003-003 | MUST | 提供 **env 契约注入器**：按规划 §7.1 表生成 env（GIT_EXEC_PATH/GIT_TEMPLATE_DIR/GIT_CONFIG_GLOBAL/GIT_CONFIG_NOSYSTEM/GIT_SSL_CAINFO/SSL_CERT_FILE/PATH/HOME/TMPDIR/GIT_PAGER） | `git env` 级验证：`GIT_EXEC_PATH` 生效（trace 走 farm）；缺省 HOME/TMPDIR 时命令不落 /system 分区 |
| FR-003-004 | MUST | 用例可单跑可全跑；每条输出结构化结果（编号/结论/证据摘录） | 运行器产出逐用例 PASS/FAIL 汇总与证据文件 |
| FR-003-005 | MUST NOT | 探针不得修改设备系统分区/全局配置；全部活动限制在 `/data/local/tmp` 工作目录 | 探针运行后无系统目录写入痕迹（只读系统） |

### 2.2 CLI 主行为（核心用例族）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-003-010 | MUST | `git --version` 回程（对应 P1 的 shell 域等价） | 输出版本串=构建版本；exit 0 |
| FR-003-011 | MUST | 基础仓库操作全链：`init` → `config user.*` → `add`（含**中文文件名**）→ `commit` → `log` → `status` → `branch` → `tag` | 每步 exit 0；`log` 含提交记录；中文文件名字节保真（R4 事实化） |
| FR-003-012 | MUST | 工作区操作：`mv`/`rm`/`checkout`/`restore`/`diff`/`stash`（采样） | 每步 exit 0 且状态转移正确 |
| FR-003-013 | MUST | **本地 clone/fetch/push 经农场**（dashed 子进程）：`git clone <本地路径>` 且 `GIT_TRACE=1` 证据含 `git-upload-pack`/`git-receive-pack` 经 `GIT_EXEC_PATH` | clone 成功；trace 行落在 farm 路径；push 后远端 log 一致 |
| FR-003-014 | MUST | **https 传输经 helper**：`git ls-remote https://github.com/git/git.git`（P3 等价） | refs 回程；trace 含 `git-remote-https` exec 记录 |
| FR-003-015 | MUST | `git clone --depth 1 https://…`（GitHub 公共库，P4 等价）+ `git log` | 克隆完成；HEAD 提交与远端一致 |
| FR-003-016 | MUST | **CA 随包生效反证**（P6 等价）：注入 `GIT_SSL_CAINFO`/`SSL_CERT_FILE`（指向物化 cacert.pem）时 https 通过；指向损坏 CA 时 TLS 失败 | 正反两向都成立（证明走随包 CA 而非系统兜底） |
| FR-003-017 | SHOULD | 农场缺失对照：删掉 farm 中 `git-remote-https` ⇒ https 报 helper 不可得（负向证明农场是必要通路） | 错误形态记录（R1/R2 佐证） |
| FR-003-018 | SHOULD | 退出码契约采样：成功=0；用法错=129 级；not-found=1（与上游 git 一致口径采样记录） | 采样结果记录（记录性，不设新契约） |

### 2.3 环境契约逐项（规划 §7.1 的可证伪化）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-003-030 | MUST | `GIT_TEMPLATE_DIR` 生效：init 产物含模板 hooks 样例文件 | `.git/hooks/*.sample` 存在（仅样例，不可执行） |
| FR-003-031 | MUST | `GIT_CONFIG_GLOBAL` 生效：全局配置读写落在注入路径 | `git config --global user.name` 读写回路 |
| FR-003-032 | MUST | `HOME`/`TMPDIR` 生效：临时文件与配置不落系统目录 | 注入目录出现 .gitconfig/临时文件痕迹；/system 无写入 |
| FR-003-033 | MUST | `GIT_PAGER=cat`（或等价）：`log`/`diff` 非交互直出 | 命令立即完成不挂起（无 tty 交互依赖） |
| FR-003-034 | SHOULD | `GIT_CONFIG_NOSYSTEM=1`：系统配置不可读不影响行为（Android 无 /etc/gitconfig） | 设置与否行为一致（记录性） |

### 2.4 已知限制的事实化（规划 §7.2 → 探针记录）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-003-040 | MUST | 仓库钩子不可执行 ⇒ git 视为无钩子：装 `pre-commit` 钩子（无 exec 位）后 commit 照常 | commit 成功；输出/警告形态记录（R11） |
| FR-003-041 | MUST | ssh 远程不可用：`git ls-remote git@github.com:…` 失败形态记录（无 ssh 二进制） | 失败 exit≠0；错误信息记录（不设超时挂起） |
| FR-003-042 | MUST | perl/tcl 子命令不可用：`git send-email`/`git svn` 报不可得 | 失败形态记录 |
| FR-003-043 | SHOULD | 输出英文（NO_GETTEXT）：`git help -a`/错误消息为英文 | 记录性 |
| FR-003-044 | SHOULD | 16KB 页设备全链采样（若测试设备支持）：version/本地链/https 在 16KB 设备复跑核心用例 | 设备页大小记录（`getconf PAGESIZE`）；核心用例结论 |

## 3. 边界（不在本模块）

- 构建/门禁/CI → 001/002；
- App 域探针（APK 落盘、PTY 交互、app 域 SELinux）→ 消费方（M1-T7/M2-T1）；
- 性能基准（R3 regex）→ 记录性采样即可，不设门禁。

## 4. 验收场景

- 一台 arm64 Android（真机或模拟器）+ adb：部署 → 建农场 → 注 env → 全量用例跑完出报告；
- 任一 MUST 用例 FAIL ⇒ 003 模块不达标，缺陷登记并回写规划（C8）；
- 全部 PASS 的用例在 test-cases.md 回填 ✅（含设备/页大小/时间等环境快照）。
