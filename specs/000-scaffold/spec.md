# 000 · 工程搭建（scaffold）功能规格

> 模块：000-scaffold · 状态：已实现（scaffold 级）· 所属工程：aosp-git-cli
> 规划基线：[`docs/000-工程规划.md`](../../docs/000-工程规划.md)（pty 四件套折叠为三件）

## 1. 目的

确立 `aosp-git-cli`（Android `git` 命令行，exec 型 PIE，静态依赖）的仓库结构、构建系统、
版本纪律、exec 门禁工具与 CI（配置期），使 M1 交叉编译只需在骨架内填充实现。

## 2. 功能需求（摘要）

- FR-000-001：root 工程名 `aosp-git-cli`，仅 include `:git-cli`。
- FR-000-002：`:git-cli` Android library，namespace `org.fellow99.gitcli`，minSdk 24、
  compileSdk 36，ABI 仅 arm64-v8a。
- FR-000-003：坐标 `io.github.fellow99:git-cli:<CLI_VERSION>`；CLI_VERSION = git 上游版本，
  独立 semver。
- FR-000-004：**useLegacyPackaging = true**（exec 型硬要求）。
- FR-000-005：无 `.so` 时 Gradle 配置/任务求值必须成功。
- FR-000-010~013：lock 纪律（draft 不伪造哈希；builtFrom.deps 登记静态依赖版本表）。
- FR-000-030~036：provision（退出码 0/2/1；仅投放 `libgit_cli.so`；jniLibs 禁入 `libnode.so`）。
- FR-000-040~042：CI 配置期门禁（`gradle :git-cli:tasks`；provision `--check` 未投放=2；
  语法门）。

## 3. 验收场景

- 干净工程可配置；provision 未投放退出码 = 2；二进制不入库。
