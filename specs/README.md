# 规格文档索引 —— `aosp-git-cli`

**项目名称：** `aosp-git-cli`（Maven 坐标 `io.github.fellow99:git-cli`）
**需求：** **000-scaffold 工程搭建 + 101-probe-app 设备回程探针载体（本批 as-built）** · 规范文档存放目录：`specs/`
**库状态：** M0 骨架已完成（Gradle 骨架 + exec 门禁 provision + draft lock + 骨架脚本 + 配置期 CI）；git 本体尚未构建（M1 ⬜）
**技术栈：** Gradle 9.4.1 + AGP 9.2.1 + vanniktech 0.37.0（`:git-cli` AAR 容器，零源码，useLegacyPackaging=true）+ 纯 Node exec 门禁（`tools/provision.mjs`）+ M1 四源（git/zlib/curl/openssl）静态交叉编译（规划）
**文档生成时间：** 2026-11-02 · **最后更新：** 2026-11-06

> **权威规划文档是 [`../docs/000-工程规划.md`](../docs/000-工程规划.md)（v2.0）。**
> 本目录是它的**收敛/展开版（as-built）**：只做细化与验收，**不复制粘贴**，所有结论回引规划的 § 号
> 与决策号（D1–D7 / R1–R11），避免两份文档漂移。新增平台结论必须先写进规划文档，再回到这里引用。
> **源码即真相**：每条论断可追溯实际文件（`path:line`）；未确认处标 `[NEEDS CLARIFICATION]`（仅
> [`000-scaffold/plan.md`](./000-scaffold/plan.md) §7 NC-1 一处）；未实测一律 ⬜，绝不当作已定事实。

---

## 一、文档总览

| 层级 | 分类 | 文档数量 | 说明 |
|---|---|---|---|
| 整体 | 项目级顶层文档 | 5 | `constitution.md` · `ARCHITECTURE.md` · `TECH.md` · `STRUCTURE.md` · `SPECS_CHECKLIST.md` |
| 整体 | 整体规格文档 | 3 | `overall-spec.md` · `overall-plan.md` · `overall-test-cases.md` |
| 模块 | 工程搭建（`000-scaffold`） | 4 | spec · plan · tasks（+T9）· test-cases · ✅ 实现（T9 收口 ⬜） |
| 模块 | 构建（`001-building`） | 4 | spec · plan · tasks · test-cases（FR-001-xxx；⬜ M1-T1~T4） |
| 模块 | 构建流水线（`002-building-workflow`） | 4 | spec · plan · tasks · test-cases（FR-002-xxx；⬜ M1-T5/T6） |
| 模块 | CLI 运行期验证（`003-cli`） | 4 | spec · plan · tasks · test-cases（FR-003-xxx；⬜ M1-T7/M2；**主用例全集 TC-003-00~17**） |
| 模块 | 设备回程探针载体（`101-probe-app`） | 4 | spec · plan · tasks · test-cases（FR-101-PROBE-xxx；✅ as-built；AAR 落位 + `assembleDebug` ✅ 2026-11-06） |
| 索引 | 本索引 | 1 | `README.md` |
| **合计** | **5 目录 / 25 文件** | | 模块目录 5 个，模块文档 20 份 |

> **刻意不生成** `API.md` / `overall-api.md`：本仓**不含任何嵌入 API**——只有原生二进制与随包数据的
> 可复现构建、ELF 门禁与发布流水线。对外契约面 = Maven 坐标 + 运行期 env 注入契约（规划 §7.1，
> 见 [`overall-spec.md`](./overall-spec.md) §3.1 与 [`ARCHITECTURE.md`](./ARCHITECTURE.md) ④）。
> **刻意不生成** `overall-data-model.md`：唯一数据实体 `git-cli.lock.json` 的全字段模型已在
> [`000-scaffold/plan.md`](./000-scaffold/plan.md) §3 逐字段给出，独立成文会造成漂移源。

---

## 二、项目级顶层文档

全局性的架构、技术、宪法与结构文档，定义项目基线与开发准则。

| 文档 | 路径 | 说明 |
|---|---|---|
| **项目宪法** | [constitution.md](./constitution.md) | 8 条不可协商原则（C1 fetch 不改源 · C2 lock 唯一事实源 · C3 二进制不入库 · C4 门禁强制 · C5 发布卫生 · C6 未实测 ⬜ · **C7 GPLv2 对应源码义务** · C8 先改文档再改实现）+ 证据纪律（✅/🔶/⬜/⚠️）+ 评审清单 + 变更流程 |
| **整体架构** | [ARCHITECTURE.md](./ARCHITECTURE.md) | 五层架构（①构建发布 ②供给门禁 ✅ as-built；③exec 制品 ④随包数据 ⑤运行期引导 ⬜ 规划标注）+ 制品流 ASCII 图 + exec 型与 dlopen 型门禁三处相反对照 + D1–D7 决策状态表 |
| **技术选型** | [TECH.md](./TECH.md) | 技术/版本/用途/理由 + **已实现 vs 规划状态列**；被否方案（动态依赖、源码补丁、helper 拷贝 filesDir、运行期下载等）；版本矩阵；七门禁与退出码硬数据；命令速查 |
| **项目结构** | [STRUCTURE.md](./STRUCTURE.md) | 真实目录树（逐文件行数）+ 刻意不存在的路径（防误引用）+ 配置锚点 + 产物落点 + 4 项事实性问题（评审必读）+ 不入库清单 |
| **检查清单** | [SPECS_CHECKLIST.md](./SPECS_CHECKLIST.md) | 规格文档完成度追踪（项目级 + 模块级）+ 质量检查 + 未闭合项 |

### 整体规格文档

跨模块的全局规格、方案与测试索引。

| 文档 | 路径 | 说明 |
|---|---|---|
| **整体规格** | [overall-spec.md](./overall-spec.md) | 技术无关需求（RFC 2119）：目的、用户故事、**FR-000-xxx 沿用**（001–005 逐条；010~013 / 030~036 / 040~042 族）、边界（**ssh 远程二期**、**perl/tcl 钩子不可用**）、可证伪验收判据 A1–A7 |
| **整体方案** | [overall-plan.md](./overall-plan.md) | 技术上下文、宪法符合性逐条检查（C1–C8）、里程碑与依赖顺序、横切关注点（退出码/日志/供应链/许可/体积）、测试途径、两段式发布策略 |
| **测试用例索引** | [overall-test-cases.md](./overall-test-cases.md) | 测试分层（L1/L1.5/L3/L5）+ 用例族索引（TC-000-01~10 → 模块用例；TC-M1/M2/M3 规划引用）+ **禁止的判据** + 已知基线数值 |

---

## 三、模块文档

### 000-scaffold — 工程搭建（✅ M0）

> 确立仓库结构、构建系统、版本纪律、exec 门禁工具与配置期 CI，使 M1 交叉编译只需在骨架内填充实现。
> 现状：实现全部落地（T1–T8 ✅）；**T9 残留收口 ⬜**（NC-1 已定稿、白名单对齐、残留清理、负例转正）。

| 文档 | 链接 | 说明 |
|---|---|---|
| 功能规格 | [000-scaffold/spec.md](./000-scaffold/spec.md) | FR-000-xxx（骨架/lock/provision/CI 族） |
| 技术方案 | [000-scaffold/plan.md](./000-scaffold/plan.md) | as-built：lock 全字段模型、七门禁行号、退出码契约、NC-1 已关闭 |
| 任务拆解 | [000-scaffold/tasks.md](./000-scaffold/tasks.md) | T1–T8 ✅ + T9 ⬜ |
| 测试用例 | [000-scaffold/test-cases.md](./000-scaffold/test-cases.md) | TC-01~05 ✅ + 负例族（TC-000-06~10，随 001/002 转正） |

### 001-building — 构建（⬜ M1-T1~T4）

> 五输入钉选 fetch → zlib/openssl/curl 静态交叉构建 → git 试编 + helper 实产探明 → strip/`libgit_*.so` 命名/assets 收集。

| 文档 | 链接 | 说明 |
|---|---|---|
| 功能规格 | [001-building/spec.md](./001-building/spec.md) | FR-001-001~006（fetch）/010~014（依赖）/020~026（git）/030~035（整理） |
| 技术方案 | [001-building/plan.md](./001-building/plan.md) | PINS 钉选表、S1–S9 流程、config.mak 参数、命名映射、lock 扩展 |
| 任务拆解 | [001-building/tasks.md](./001-building/tasks.md) | T1–T13 |
| 测试用例 | [001-building/test-cases.md](./001-building/test-cases.md) | TC-001-01~18（L1/L1.5） |

### 002-building-workflow — 构建流水线（⬜ M1-T5/T6）

> provision 扩展（helper 同门禁 + jniLibsWhitelist + manifest 一致性 + assets 校验）+ CI 真实流水线 + Release + lock 回写。

| 文档 | 链接 | 说明 |
|---|---|---|
| 功能规格 | [002-building-workflow/spec.md](./002-building-workflow/spec.md) | FR-002-001~006（provision 扩展）/010~016（CI）/020~021（不回归） |
| 技术方案 | [002-building-workflow/plan.md](./002-building-workflow/plan.md) | 命令面增量、白名单/一致性规则、workflow 步骤、断言修复 |
| 任务拆解 | [002-building-workflow/tasks.md](./002-building-workflow/tasks.md) | T1–T11 |
| 测试用例 | [002-building-workflow/test-cases.md](./002-building-workflow/test-cases.md) | TC-002-01~20（负例矩阵 + 断言语义） |

### 003-cli — CLI 运行期验证（⬜ M1-T7/M2-T2 shell 域等价）

> adb shell 域 L3 探针：部署 + symlink 农场 + env 契约注入 + **CLI 主用例全集**（版本/本地链含中文/https/CA 反证/限制事实化）。

| 文档 | 链接 | 说明 |
|---|---|---|
| 功能规格 | [003-cli/spec.md](./003-cli/spec.md) | FR-003-001~005（harness）/010~018（主行为）/030~034（env 契约）/040~044（限制事实化） |
| 技术方案 | [003-cli/plan.md](./003-cli/plan.md) | harness 设计、目录布局、P1–P7 映射、设备策略 |
| 任务拆解 | [003-cli/tasks.md](./003-cli/tasks.md) | T1–T10 |
| 测试用例 | [003-cli/test-cases.md](./003-cli/test-cases.md) | **TC-003-00~17 主用例全集**（A 环境自检/B 版本/C 本地链/D https/E 限制） |

### 101-probe-app — 设备回程探针载体（✅ as-built，2026-11-06 构建修齐）

> 独立 Android 探针载体：消费 CI 产物 AAR，物化 assets + helper 农场 + env 注入（规划 §7.1），
> 逐条执行 003 主用例可执行子集（TC-003-01…19 + App 域 18a/18b/05b/08b）并出 JSON 报告。
> 设备实跑 ⬜（编排者排队）；git 修复项零（20261105 修复设计 §1/§7）。

| 文档 | 链接 | 说明 |
|---|---|---|
| 功能规格 | [101-probe-app/spec.md](./101-probe-app/spec.md) | FR-101-PROBE-001~011（装载/注入/执行/判据/报告/无头/SKIP 口径） |
| 技术方案 | [101-probe-app/plan.md](./101-probe-app/plan.md) | as-built：真实行数、AAR 获取与 lock 校验、不一致登记、FR 交叉引用 |
| 任务拆解 | [101-probe-app/tasks.md](./101-probe-app/tasks.md) | T1 建仓 ✅ / T2 正典映射与首跑 ✅ / T3 构建修齐 ✅ / T4 遗留执行项 |
| 测试用例 | [101-probe-app/test-cases.md](./101-probe-app/test-cases.md) | 27 判据点（26 条 + TC-003-17）+ 端点 extras SKIP 口径 + host 侧用例 |
---

## 四、模块编号一览（注册于规划 §10.2，2026-11-02）

| 编号 | 模块名 | 目录 | 状态 | 规划出处 |
|---|---|---|---|---|
| 000 | 工程搭建（scaffold） | [`000-scaffold/`](./000-scaffold/) | ✅ M0 完成（T9 收口 ⬜） | 规划 §10 M0 + §10.2 |
| 001 | 构建（源钉选 + 交叉编译） | [`001-building/`](./001-building/) | ⬜ 立项 | 规划 §10 M1-T1~T4 |
| 002 | 构建流水线（门禁扩展 + CI + 发布） | [`002-building-workflow/`](./002-building-workflow/) | ⬜ 立项 | 规划 §10 M1-T5/T6 |
| 003 | CLI 运行期验证 | [`003-cli/`](./003-cli/) | ⬜ 立项 | 规划 §10 M1-T7 + M2-T2（shell 域等价） |
| 101 | 设备回程探针载体（probe-app） | [`101-probe-app/`](./101-probe-app/) | ✅ as-built（构建 ✅；设备实跑 ⬜ 编排者排队） | 本批 specs/101-probe-app（101 编号段沿用系约定，见下注）+ 规划 §10 M1-T7 / M2-T1 |
> 编号分配须**先写进规划 §10.2 再建目录**（C8）；FR 族 = `FR-<模块号>-xxx`。
> **101 编号段**：沿用 node/python/uv/pnpm 各仓「设备侧探针 / 集成模块」编号段约定（其 000-003
> 外的 101 模块：node 为 101-npm-integration + 101-probe-app，python/uv/pnpm 为 101-probe-app）；
> git-cli 首个 101 模块 = **101-probe-app**（无 101-*-integration）。规划 §10.2 编号登记表本次未
> 改动（C8 后续如需，由 003/101 收口时一并回写规划）。
---

## 五、模块文档结构规范

每个模块目录 `NNN-<模块名>/` 下**必须成对**提供：

| 文件 | 命名 | 说明 |
|---|---|---|
| 功能规格 | `spec.md` | **技术无关**：目的、范围边界、功能需求（`FR-0NN-*`，RFC 2119）、验收场景 |
| 技术方案 | `plan.md` | **实现特定**：技术上下文与版本、宪法合规检查（C1–C8 逐条）、数据模型、CLI/接口契约、文件清单（**真实行数**）、FR 交叉引用、待实现清单与 [NEEDS CLARIFICATION] |

> 复杂模块可再追加 `tasks.md` / `test-cases.md`。

**三条纪律**：

1. `spec.md` 写「做什么、验收判据是什么」；`plan.md` 写「怎么做」。两份都**回引** `docs/000-工程规划.md` 的 § 号。
2. `spec.md` 不出现实现细节；`plan.md` 不出现没有源码依据的断言。
3. as-built 与 planned 必须逐条区分：未实现的写 `⬜ 规划未实现（M1/M2）`，**不得**把规划当既成事实。

---

## 六、快速导航

| 目标读者 | 推荐阅读顺序 |
|---|---|
| **新加入开发者** | [`constitution.md`](./constitution.md) → [`STRUCTURE.md`](./STRUCTURE.md) → [`overall-spec.md`](./overall-spec.md) → 规划 §1/§3 → [`000-scaffold/spec.md`](./000-scaffold/spec.md) |
| **架构师 / Tech Lead** | 规划 §3（D1–D7）→ [`ARCHITECTURE.md`](./ARCHITECTURE.md) → [`TECH.md`](./TECH.md) → [`overall-plan.md`](./overall-plan.md) → 规划 §11（R1–R11 风险） |
| **M1 实现者** | [`000-scaffold/plan.md`](./000-scaffold/plan.md) §7（待实现清单）→ 规划 §4/§5（构建设计/helper 打包）→ [`overall-test-cases.md`](./overall-test-cases.md) §2.3 |
| **消费方（终端 App）** | [`../README_zh.md`](../README_zh.md) → 规划 **§7.1 env 注入表 / §7.2 已知限制** → [`overall-spec.md`](./overall-spec.md) §3 |
| **测试 / QA** | [`overall-test-cases.md`](./overall-test-cases.md) → [`000-scaffold/test-cases.md`](./000-scaffold/test-cases.md) → 规划 §7.3（P1–P7） |
| **合规 / 上架** | [`constitution.md`](./constitution.md) C7 → [`../git-cli/THIRD-PARTY-NOTICES.md`](../git-cli/THIRD-PARTY-NOTICES.md) → 规划 §10.1（GPLv2 对应源码归档，D7） |

### 快照命令（先看证据，再看结论）

```bash
node tools/provision.mjs --check                                   # exec 门禁（未投放=exit 2 ✅）
node tools/provision.mjs --inspect <libgit_cli.so>                 # 对任意文件跑七门禁
gradle :git-cli:tasks --console=plain                              # 配置期门禁（无 .so 必须过）
gradle :git-cli:assembleDebug                                      # AAR 容器产出（786 B 空容器 ✅）
node scripts/fetch-git-cli-source.mjs --git 2.51.0 --out .dist/src # ⬜ M1（现 exit 2=SCAFFOLD）
bash scripts/build-git-cli-android.sh --git 2.51.0 --api 24 \
  --src .dist/src/git --deps .dist/src --ndk "$ANDROID_NDK_HOME" --out build/out  # ⬜ M1
```

---

**文档维护者：** `aosp-git-cli` 开发团队 · **权威来源：** [`../docs/000-工程规划.md`](../docs/000-工程规划.md)（v2.0）·
**方法：** specs-as-built（源码即真相；先项目级后模块级；README 最后扫描生成、链接全验）
