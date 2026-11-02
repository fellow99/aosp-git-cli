# 000-scaffold — 模块计划（plan.md，as-built）

> **模块**：000-scaffold 工程搭建 · **性质**：技术实现计划（as-built：只写已建成事实；M1/M2 规划以「规划引用」标注）。
> **依据**：[`../constitution.md`](../constitution.md)（C1–C8）· [`../../docs/000-工程规划.md`](../../docs/000-工程规划.md)（唯一规划基线，下称「规划 §」）· 本模块 [`spec.md`](./spec.md)（需求与验收）· [`tasks.md`](./tasks.md)（任务，T1–T8 全勾）· [`test-cases.md`](./test-cases.md)（TC-01~05 执行记录）。
> **标记**：✅实测（行号即本仓 2026-11-02 实读行号）/ 🔶沿用 / ⬜未实测 / ⚠️冲突或风险。
> **版本**：v1.1 · 2026-11-02 · 状态：**实现已落地**（T1–T8 完成；T9 残留收口 ⬜；git 本体未构建，属 001-building ⬜）。v1.1：NC-1 定稿关闭、登记 T9、模块编号 001/002/003 分裂（规划 §10.2）。

---

## 1. 技术上下文

### 1.1 运行环境与版本

| 项 | 值 | 证据 |
|---|---|---|
| Gradle | **9.4.1**（仓库无 wrapper；CI `gradle/actions/setup-gradle@v4` 钉版 `.github/workflows/build-git-cli-android.yml:29-32`；本地 `.gradle/9.4.1/` 佐证） | ✅ |
| AGP | **9.2.1**（`gradle/libs.versions.toml:2`，版本目录唯一条目） | ✅ |
| 发布插件 | `com.vanniktech.maven.publish.base` **0.37.0**（`settings.gradle.kts:3`，经 pluginManagement 加载；`publish.gradle.kts:9-10` 注明） | ✅ |
| JDK | Temurin **21**（CI `:23-27`） | ✅ |
| Node（host 工具） | 本机 **v24.7.0**（脚本只用内置模块，≥18 即可） | ✅ |
| 模块 | `:git-cli` Android library；`namespace=org.fellow99.gitcli`、`compileSdk=36`、`minSdk=24`、`abiFilters=[arm64-v8a]`、`useLegacyPackaging=true`（`git-cli/build.gradle.kts:29-43`）；**零源码**（无 `src/` 树） | ✅ |
| 坐标/版本 | `io.github.fellow99:git-cli:<CLI_VERSION>`；`CLI_VERSION=2.51.0`（draft，`gradle.properties:7`）；缺失即 error（`git-cli/build.gradle.kts:16-17`） | ✅ |

### 1.2 依赖（零第三方）

| 侧 | 依赖 | 用途 | 缺失后果 |
|---|---|---|---|
| `tools/provision.mjs` | `node:fs` / `node:path` / `node:crypto`（createHash）/ `node:url`（fileURLToPath） | 读写、哈希、定位仓库根 | 工具不可用（`provision.mjs:27-30`） |
| `scripts/fetch-git-cli-source.mjs` | `node:path` / `node:url` | 接口固化（实现 ⬜ M1） | — |
| Gradle 侧 | 无 application/library 依赖（模块零源码；`FAIL_ON_PROJECT_REPOS`，`settings.gradle.kts:13`） | — | — |
| 发布凭据 | Central Portal Token / GPG —— **仅用户级** `~/.gradle/gradle.properties` | 仅 `RELEASE=true` 时 | 保持发布任务禁用（防误发，C5） |

---

## 2. 宪法符合性检查（逐条）

| 原则 | 判定 | 依据 |
|---|---|---|
| **C1 fetch 不改源** | ✅ 纪律已固化 / ⬜ 执行待 M1 | 骨架脚本文件头（`fetch:9`、`build:5-11`）明文 `NO_*`/静态链入/16KB 纪律；仓库无补丁痕迹 |
| **C2 lock 唯一事实源** | ✅ 符合 | provision 只从 lock 取版本/ABI/名字/白名单（`provision.mjs:177-197`）；draft 不伪造（`git-cli.lock.json:13-14,35`）；⚠️ `gates` 语义见 §7 NC-1 |
| **C3 二进制不入库** | ✅ 符合 | `.gitignore:23-24,27-28`；`git-cli/src/` 整树不存在 ✅ |
| **C4 门禁强制** | ✅ 符合 | 七门禁（`:146-167`）+ draft 只记录（`:156-159`）+ 单文件白名单（`:222-228`）+ 禁入检查（`:38,246-250`）；⚠️ 兜底白名单缺 `liblog.so`（`:184`，STRUCTURE §5-3） |
| **C5 发布卫生** | ✅ 符合 | `RELEASE=false`（`gradle.properties:19`）+ 任务禁用门禁（`publish.gradle.kts:133-139`）+ 凭据仅用户级（`:75-113`）+ local.example 模板 |
| **C6 未实测标 ⬜** | ✅ 符合 | 本文件与项目级规格全程区分 ✅/🔶/⬜/⚠️；骨架 exit 2 是诚实信号而非缺陷 |
| **C7 GPLv2 对应源码义务** | ✅ 已登记 / ⬜ 交付待 M1-T6 | `git-cli/THIRD-PARTY-NOTICES.md:16-17`；Release 归档随附四源 tarball + 构建脚本（规划 §10.1，R5 措辞 ⬜） |
| **C8 先改文档再改实现** | ✅ 符合 | 规划 v2.0 先行；本 plan 为 as-built 回写；偏差回写规划 |

---

## 3. `git-cli.lock.json` 数据模型（53 行，逐字段）

### 3.1 顶层

| 字段 | 类型 | 含义 / 约束 | 当前值（行号） | 谁读 |
|---|---|---|---|---|
| `$comment` | string | 文件自述：唯一事实源 + draft 占位说明 | `:2` | 人读 |
| `active` | object | 当前选用制品 `{version, abi}`；换版本 = 改这一行 | `2.51.0` / `arm64-v8a`（`:3-6`） | `provision.mjs:185-186` |
| `releases[]` | array | 每个制品条目一条（见 3.2） | 1 条（`:7-37`） | `provision.mjs:187` |
| `matrix` | object | 门禁/打包矩阵（见 3.3） | 见 3.3（`:38-52`） | `provision.mjs:184` |

### 3.2 `releases[i]` 字段表

| 字段 | 类型 | 含义 | 当前值（行号） | 谁读 |
|---|---|---|---|---|
| `version` | string | = git 上游版本（独立 semver） | `2.51.0`（`:9`） | `provision.mjs:187` |
| `abi` | string | 目标 ABI | `arm64-v8a`（`:10`） | `provision.mjs:187` |
| `androidApi` | number | 交叉编译 API level（build 脚本 `--api` 默认同值） | `24`（`:11`） | ⬜ M1（build 脚本实现时） |
| `name` | string | 投放文件名（Android 只认 `lib*.so`） | `libgit_cli.so`（`:12`） | `provision.mjs:194`（缺省回落 `DEFAULT_BINARY`） |
| `size` | number | 字节数；**draft=0 表示未构建** | `0`（`:13`） | 门禁⑥（`:142,158`；0 值不比对） |
| `sha256` | string | 64 hex；**draft="" 表示未构建** | `""`（`:14`） | 门禁⑤（`:141,156`；空值不比对） |
| `builtFrom.source` | string | 上游出处（不改源声明） | 文本描述（`:16`） | 人读；⬜ M1-T1 升级 |
| `builtFrom.deps` | string | 静态依赖登记（现为**文本描述**；M1 升级为 `{zlib,curl,openssl:{version,sha256}}` 版本表） | `:17` | 人读 |
| `builtFrom.assets` | string | 随包数据计划 | `:18` | 人读 |
| `builtFrom.ndk` | string | NDK 线 | `TBD`（`:19`） | ⬜ M1 回写 |
| `builtFrom.flags` | string | 构建参数 | `TBD`（`:20`） | ⬜ M1 回写 |
| `gates` | object | 七门禁**存档**（7 个 bool，`:22-30`） | 全 `true` | ⚠️ **无工具读**（§7 NC-1） |
| `mavenCentral.coordinates` | string | 发布坐标 | `io.github.fellow99:git-cli:2.51.0`（`:32`） | 人读 |
| `mavenCentral.published` | bool | Maven 阶段闭环标志 | `false`（`:33`） | ⬜ M3 回写 |
| `status` | string | `draft` → `released` 单向 | `draft`（`:35`） | `provision.mjs:197`（draft 告警） |

### 3.3 `matrix` 字段表

| 字段 | 含义 | 当前值（行号） | 谁读 |
|---|---|---|---|
| `minSdk` | 最低系统版本 | `24`（`:39`） | 人读（与模块配置一致 ✅） |
| `abi[]` | 支持的 ABI | `["arm64-v8a"]`（`:40-42`） | 人读 |
| `allowedNeeded[]` | **DT_NEEDED 白名单**：libc/libm/libdl/libz/liblog（`libz.so` 为防御性允许，M1 复核 ⬜） | `:43-49` | `provision.mjs:184`（门禁④） |
| `execPackaging` | exec 打包口径说明（落盘 + SELinux 理由） | `:50` | 人读 |
| `note` | 版本独立、CA env 注入、ssh 范围外说明 | `:51` | 人读 |

> M1 扩展（规划引用 ⬜）：`matrix.jniLibsWhitelist`（主二进制 + helper 集）与 gitexec-manifest 语义说明；
> `releases[].builtFrom` 登记 helper 清单 + 逐个 sha256（规划 §8）。

---

## 4. provision CLI 与退出码契约（`tools/provision.mjs`，276 行，as-built）

### 4.1 命令面

| 命令 | 行为 | 行号 | 退出码 |
|---|---|---|---|
| `--check`（或无 `--out`） | 校验 `<module>/src/main/jniLibs/<abi>/<name>`：七门禁 + jniLibs 兄弟文件白名单；**未投放 ⇒ 打印路径并 exit 2** | `:208-229` | 0 / 2 |
| `--out <dir> --from <file>` | 先跑七门禁，不过 ⇒ 拒绝投放（exit 2）；过 ⇒ 拷到 `<ROOT>/<out>/<abi>/<name>` + 禁入检查 + 写 `META-INF/git-cli.properties` | `:231-268` | 0 / 1 / 2 |
| `--inspect <file>` | 对任意文件跑七门禁并打印 | `:199-206` | 0 / 2 |
| `--version <v>` / `--abi <a>` | 覆盖 lock `active` 选条目（不存在 ⇒ exit 1） | `:185-193` | — |
| `--allow-page-align-4k` | 门禁⑦放行，**仅 bring-up**，打 ⚠ | `:162-167` | — |
| （顶层 catch） | 用法/IO/lock 错误 ⇒ stderr + exit 1 | `:271-276` | 1 |

### 4.2 七门禁（exec 型 profile；与 dlopen 库门禁的三处相反见 [`../ARCHITECTURE.md`](../ARCHITECTURE.md) §3.1）

| # | 判据 | 实现行号 | draft 行为 |
|---|---|---|---|
| ① | `e_type == 3`（ET_DYN/PIE） | `:146` | 判死 |
| ② | **PT_INTERP 恰 1 且内容 = `/system/bin/linker64`** | `:148-150` | 判死 |
| ③ | `e_machine == 183`（AArch64） | `:151` | 判死 |
| ④ | DT_NEEDED ⊆ lock `matrix.allowedNeeded` | `:153-155` | 判死 |
| ⑤ | SHA-256 与锁一致 | `:156-157` | 只记录（draft 无 64hex 锁值，`:141`） |
| ⑥ | 大小与锁一致 | `:158-159` | 只记录（draft size=0，`:142`） |
| ⑦ | min LOAD p_align ≥ 0x4000 | `:160` | 判死（`--allow-page-align-4k` 除外） |

ELF 解析（`:58-130`）为极简 ELF64 小端自解析：e_type/e_machine、PT_INTERP 计数+内容、LOAD p_align 集合、
`.dynamic` 的 DT_NEEDED/SONAME——只回答门禁需要的问题，不依赖 llvm/python。

### 4.3 退出码契约（✅ 本机复核 2026-11-02）

| 码 | 语义 | 实测 |
|---|---|---|
| `0` | 全过 | ⬜（M0 无产物，0 路径未出现） |
| `2` | 门禁不合格 / **未投放** / SCAFFOLD 未实现 | ✅ `--check`→2；`fetch --git 2.51.0`→2；`build`（参数齐）→2 |
| `1` | 用法 / IO / lock 错误 | ✅ `--out foo`（缺 --from）→1 |

### 4.4 投放副产物（as-coded；⬜ 未走通——M0 无真实产物）

投放成功后写 `git-cli/src/main/resources/META-INF/git-cli.properties`（`:252-267`）：
`tool.version / abi / name / size / sha256 / provisionedAt`（`paired.runtime` 行本仓恒不出现——残留字段见 §7）。

---

## 5. FR 交叉引用（实现 ↔ [`spec.md`](./spec.md)）

| FR | 实现落点 | 状态 |
|---|---|---|
| FR-000-001（rootName/单模块） | `settings.gradle.kts:20-21` | ✅ |
| FR-000-002（AAR 容器参数） | `git-cli/build.gradle.kts:29-35`；AAR 实测空容器（786 B，classes.jar 空） | ✅ |
| FR-000-003（坐标/CLI_VERSION） | `git-cli/build.gradle.kts:16-26` + `publish.gradle.kts:36-39` + `gradle.properties:7` | ✅ |
| FR-000-004（useLegacyPackaging） | `git-cli/build.gradle.kts:37-43` | ✅（落盘效果 ⬜ M1-T7） |
| FR-000-005（无 .so 可配置） | 全配置无二进制依赖；CI `:34-35` + TC-01 | ✅ |
| FR-000-010~013（lock 纪律族） | `git-cli.lock.json` 全文 + `provision.mjs:141-142,177-197` | ✅（deps 版本表 ⬜ M1-T1） |
| FR-000-030~036（provision 族） | `provision.mjs:146-167,199-268`；退出码 ✅ 复核 | ✅（负例/全链 ⬜） |
| FR-000-040~042（CI 配置期） | `.github/workflows/build-git-cli-android.yml:34-50` | ✅ |

---

## 6. 文件清单（真实行数，✅ 2026-11-02 实测）

| 文件 | 行数 | 角色 |
|---|---|---|
| `settings.gradle.kts` | 21 | rootName + 单模块 + 插件管理 |
| `gradle/libs.versions.toml` | 5 | AGP 版本目录 |
| `gradle.properties` | 19 | CLI_VERSION / RELEASE=false / POM_* |
| `gradle.properties.local.example` | 8 | 用户级凭据模板（不入库） |
| `git-cli/build.gradle.kts` | 45 | AAR 容器 + exec 打包 + 版本强制 |
| `publish.gradle.kts` | 139 | 发布面（坐标/Portal/签名/singleVariant/SCM 补丁/RELEASE 门禁） |
| `git-cli.lock.json` | 53 | 唯一事实源（draft） |
| `tools/provision.mjs` | 276 | exec 门禁 + 幂等投放 |
| `scripts/fetch-git-cli-source.mjs` | 54 | 骨架（exit 2，M1 实现） |
| `scripts/build-git-cli-android.sh` | 60 | 骨架（exit 2，M1 实现） |
| `.github/workflows/build-git-cli-android.yml` | 50 | 配置期 CI |
| `.gitignore` | 31 | 二进制/随包树/凭据/工作区排除 |
| `git-cli/THIRD-PARTY-NOTICES.md` | 19 | 第三方许可 + GPLv2 义务 |
| `specs/000-scaffold/{spec.md, tasks.md, test-cases.md}` | 27 / 13 / 17 | 需求 / 任务 / 用例（既有三件） |
| `specs/000-scaffold/plan.md` | 本文件 | as-built 技术方案（本批新增） |

---

## 7. 待实现清单 / 遗留（不属本模块缺失，属 M1/M2 工作）与未确认项

### 7.0 缺陷登记（2026-11-02 评审发现）：CI 退出码断言语义失效

- 现象：`build-git-cli-android.yml:37-45` 中 `node tools/provision.mjs --check` 以 2 退出时，
  GitHub Actions 默认 `bash -e` 使 step 即刻失败，`code=$?` 与 `-ne 2` 分支不可达——
  无法区分「预期 2=未投放」与「意外 1=工具缺陷」（与 python/node/pnpm 三仓同款，本仓此前漏登记）；
- 影响：纪律仍有强制力（step 失败即红），但断言语义失效；
- 修法（M1-T6 重写流水线时落地）：`code=0; node tools/provision.mjs --check || code=$?; [ "$code" -eq 2 ] || exit 1`。

| 项 | 归属 | 依据 |
|---|---|---|
| fetch 真实实现（五输入钉选 + sha256 + deps 版本表回写） | M1-T1 | 规划 §4.1/§10 |
| 依赖静态构建 + git 试编 + helper 清单探明 | M1-T2/T3 | 规划 §4.2（R1/R7/R8/R9） |
| strip/16KB/命名/assets 收集 | M1-T4 | 规划 §4.2⑤⑥ |
| provision 扩展（helper 同门禁 + jniLibsWhitelist + manifest 一致性 + assets 校验） | M1-T5 | 规划 §5.3 |
| CI 真实流水线 + Release + lock 回写 released | M1-T6 | 规划 §9/§10 |
| `META-INF/git-cli.properties` 首次生成（投放链路走通） | M1 | §4.4 ⬜ |
| 负例用例 TC-000-07~10 | M1 | [`../overall-test-cases.md`](../overall-test-cases.md) §2.2 |

**未确认项（[NEEDS CLARIFICATION]，0/3——原 NC-1 已于 2026-11-02 定稿关闭）**：

- ~~**NC-1**：`git-cli.lock.json` 的 `gates` 七项语义待定~~ → **定稿（T9 落地）**：
  `gates` 语义 = **门禁结论存档**（provision 每次重新解析产物判定，不读存档；存档仅为人读的
  最后一次结论快照）。因此 **draft 期初值必须全 `false`**（C6：未实测不当事实），首个真实构建
  过门禁后回写 `true` 并同步真实 sha256/size。实施：T9 ①（lock `gates` 全改 `false` + `$comment`
  注明语义；provision 行为不变——维持不读取）。

**残留字段（⚠️ 不阻塞，建议 M1 顺手清理；详见 [`../STRUCTURE.md`](../STRUCTURE.md) §5）**：
`gradle.properties:3` `VERSION_NAME=0.1.0`（无读取方）；`provision.mjs:196,263` `pairedRuntime`（pty 线
残留，本仓 lock 无该字段）；`provision.mjs:184` 兜底 allowedNeeded 缺 `liblog.so`（与 lock 漂移点）。
