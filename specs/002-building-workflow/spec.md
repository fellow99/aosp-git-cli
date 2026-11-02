# 002 · 构建流水线（building-workflow）功能规格

> 模块：002-building-workflow · 状态：⬜ 规划已立项（规划 §10.2）· 所属工程：aosp-git-cli
> 规划基线：[`docs/000-工程规划.md`](../../docs/000-工程规划.md) §5.3（provision 门禁扩展）/§6（门禁 profile）/§9（CI 设计）/§10.1（发布模式）
> 覆盖任务：M1-T5（provision 扩展）/ M1-T6（CI 真实流水线 + Release + lock 回写）

## 1. 目的

把 001 产出的制品集**安全地**投放、校验、归档、发布：provision 从单文件门禁升级为
「主 + helper 全集 + assets」的门禁与白名单体系；CI 从配置期门禁升级为真实构建流水线，
Release 归档履行 GPLv2 对应源码义务，lock 回写闭环（draft → released）。

## 2. 功能需求（FR-002-xxx，RFC 2119；判据可证伪）

### 2.1 provision 门禁扩展（M1-T5，规划 §5.3/§6）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-002-001 | MUST | **helper 全集与主二进制同一 exec 门禁 profile**（七门禁逐个判定，无一豁免） | 投放时逐 helper 输出七门禁 ✔/✘；任一 ✘ ⇒ 整体拒绝（exit 2） |
| FR-002-002 | MUST | jniLibs 白名单升级：`--check` 允许的 `.so` 集合 = lock `matrix.jniLibsWhitelist`（主 + helper）；白名单外 `.so` 拒绝；`libnode.so` 禁入不变 | 白名单内多文件通过；混入白名单外文件 ⇒ exit 2 且列出非法文件（TC-000-07/08 转正） |
| FR-002-003 | MUST | gitexec-manifest 一致性校验：manifest 每个 farm 条目引用的物理件 ∈ 白名单；反向无孤儿（白名单内每个物理件都有 farm 条目或显式豁免记录） | 孤儿/悬空任一存在 ⇒ exit 2 并指出条目 |
| FR-002-004 | MUST | assets 纯数据校验（`--assets` 投放与校验）：树内无 `.so`、无可执行位文件；逐文件 sha256 与 manifest.json 一致；manifest 总 sha256 自洽 | 树内出现可执行位/`.so` ⇒ exit 2；篡改任一文件 ⇒ sha256 失配 exit 2 |
| FR-002-005 | MUST | 投放幂等与元数据扩展：多文件投放重复执行结果一致；`META-INF/git-cli.properties` 扩展 helper 清单与 deps 版本表 | 重复投放后目录清单与元数据一致；元数据含 helper 行 |
| FR-002-006 | MUST | 退出码契约不变：0 全过 / 2 门禁不合格·未投放 / 1 用法·IO（宪法 C4） | 三类场景实测退出码逐一对上 |

### 2.2 CI 真实流水线（M1-T6，规划 §9）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-002-010 | MUST | runner 装机清单钉定：ubuntu-24.04 + JDK21 + Gradle 9.4.1 + Node 20 + NDK（lock 对齐线）+ make/gcc/perl/tar/xz + ccache；autoconf 可选（config.mak 兜底） | workflow 装机步骤逐项可复现；缺 autoconf 不致失败 |
| FR-002-011 | MUST | 流水线顺序 = 规划 §9：resolve version → fetch（五输入 sha256）→ 静态依赖 → git configure/make → helper 探明 → strip → provision 全门禁 → 归档 → Release → lock 回写（PR 提示） | 单条 workflow 从 tag/dispitch 产出全部制品；任一步失败即红 |
| FR-002-012 | MUST | **退出码断言语义修复**（000-scaffold plan §7.0 缺陷）：断言写法保证「预期 2」与「意外 1」可区分 | `bash -e` 环境下 `--check` 未投放=2 通过、=1/其他失败（负例构造验证） |
| FR-002-013 | MUST | 归档 `git-cli-v<ver>-android-arm64-v8a.tar.gz` + `.sha256`：lib*.so 集 + assets + 双 METADATA + LICENSES/NOTICES + **四源 tarball 与构建脚本（GPLv2 对应源码，C7/D7）** | 归档清单核对逐项在；四源 tarball sha256 与 PINS 一致 |
| FR-002-014 | MUST | Release 触发：tag `v<gitver>` push（或 dispatch 输入版本）；tag 与 lock active 版本一致性校验 | tag 版本 ≠ lock ⇒ 流水线失败；成功 Release 含归档与 .sha256 |
| FR-002-015 | MUST | lock 回写闭环：构建成功后 `releases[]` 回写 size/sha256/helpers/gates=true/`status=released`（draft→released 单向，宪法 C2） | 回写后 `--check` ⑤⑥ 变硬比对且通过；status 非 draft |
| FR-002-016 | MUST NOT | PR/push（非 tag）**不得**发布 Release，只跑构建+门禁（发布卫生 C5） | 非 tag 触发的运行无 Release 产物 |

### 2.3 配置期门禁保留（M0 能力不回归）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-002-020 | MUST | 无二进制干净工程 `gradle :git-cli:tasks` 仍必须成功（FR-000-005/040 不回归） | CI 干净检出配置门禁步绿 |
| FR-002-021 | MUST | 语法门（node --check ×N + bash -n）覆盖全部新增脚本 | 语法步零告警通过 |

## 3. 边界（不在本模块）

- 源码钉选与交叉编译本身 → **001-building**（CI 只是调用者）；
- 设备上行为验证 → **003-cli**；
- Maven Central 发布（M3，两段式第二段）→ 规划 §10.1 runbook，非本模块里程碑（管线已由 publish.gradle.kts 内置）。

## 4. 验收场景

- 干净 runner 单条 workflow（tag 触发）产出归档 + Release，lock 回写 released，provision `--check` 全绿；
- 混入 `libnode.so` 或白名单外 `.so` ⇒ CI 红（负例）；
- 篡改 assets 任一文件 ⇒ `--assets` 校验 exit 2（负例）；
- 无 tag 的普通 push 只构建不发布。
