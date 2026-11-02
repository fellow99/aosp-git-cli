# SPECS_CHECKLIST.md —— 规格文档完成度追踪

> 工程：`aosp-git-cli` · 需求：**000-scaffold 工程搭建**
> 规范文档存放目录：`specs/` · 生成日期：**2026-11-02**（specs-as-built 套件）
> 权威规划文档：[`../docs/000-工程规划.md`](../docs/000-工程规划.md)（v2.0，**结论以它为准**）
>
> 状态口径：✅ 已完成 · ⚠️ 已完成但含未闭合项（见备注）· ⬜ 待生成

---

## 一、项目级文档

| # | 文档 | 路径 | 状态 | 说明 |
|---|---|---|---|---|
| P-01 | 项目宪法 | [constitution.md](./constitution.md) | ✅ | 8 条不可协商原则（C1 fetch 不改源 · C2 lock 唯一事实源 · C3 二进制不入库 · C4 门禁强制 · C5 发布卫生 · C6 未实测 ⬜ · C7 GPLv2 对应源码义务 · C8 先改文档再改实现）+ 证据纪律 + 评审清单 + 变更流程 |
| P-02 | 整体架构 | [ARCHITECTURE.md](./ARCHITECTURE.md) | ✅ | 五层架构（构建发布/供给门禁 as-built；制品/随包数据/运行期引导 ⬜ 规划标注）+ 制品流 ASCII 图 + exec 门禁 profile 对照 + D1–D7 状态 |
| P-03 | 技术选型 | [TECH.md](./TECH.md) | ✅ | 技术/版本/理由/**已实现 vs 规划状态列**；被否方案；版本矩阵；七门禁与退出码口径；命令速查 |
| P-04 | 目录结构 | [STRUCTURE.md](./STRUCTURE.md) | ✅ | 目录树（真实行数）+ 刻意不存在的路径 + 配置锚点 + 产物落点 + FR 映射 + 4 项事实性问题 + 不入库清单 |
| P-05 | 整体规格 | [overall-spec.md](./overall-spec.md) | ✅ | 技术无关需求（RFC 2119）：目的/用户故事/FR-000-xxx 沿用（001–005 逐条 + 010~013、030~036、040~042 族）/边界（ssh 二期、perl/tcl 钩子不可用）/验收判据 A1–A7 |
| P-06 | 整体技术方案 | [overall-plan.md](./overall-plan.md) | ✅ | 技术上下文 + 宪法符合性逐条检查 + 里程碑/依赖顺序 + 横切关注点 + 测试途径 + 两段式发布策略 |
| P-07 | 测试用例索引 | [overall-test-cases.md](./overall-test-cases.md) | ✅ | 分层（L1/L1.5/L3/L5）+ 用例族索引（TC-000-01~10 已跑/待跑，TC-M1/M2/M3 规划引用）+ 禁止判据 + 基线数值 |
| P-08 | 规格检查清单 | SPECS_CHECKLIST.md | ✅ | 本文件 |
| P-09 | 规格索引 | [README.md](./README.md) | ✅ | 最后生成：按实际产出的全量索引（链接已全验） |
| — | `API.md` / `overall-api.md` / `overall-api` | — | ⛔ 刻意不生成 | 本仓**不含任何嵌入 API**（README/规划 §1.1）；对外契约面 = Maven 坐标 + 运行期 env 注入契约（规划 §7.1，在 `overall-spec.md` §3.1/`ARCHITECTURE.md` ④ 呈现） |
| — | `overall-data-model.md` | — | ⛔ 刻意不生成 | 本仓唯一数据实体是 `git-cli.lock.json`，其**全字段数据模型**已在 [`000-scaffold/plan.md`](./000-scaffold/plan.md) §3 逐字段给出（53 行 JSON，单一模块粒度），独立成文会形成两份漂移源 |

---

## 二、模块级文档（当前唯一在册模块：000-scaffold）

| # | 模块 | 目录 | spec.md | plan.md | tasks.md | test-cases.md | 状态 | 备注 |
|---|---|---|---|---|---|---|---|---|
| M-01 | 工程搭建（scaffold） | [`000-scaffold/`](./000-scaffold/) | ✅（既有） | ✅（本批新增） | ✅（既有） | ✅（既有，含 2026-11-02 执行记录） | ⚠️ | 实现全部落地（T1–T8）；⬜ 未闭合项均属 M1/M2：fetch/build 实现、provision 扩展、lock released、负例用例、NC-1（`gates` 语义） |

**模块纪律**：每个模块目录 `NNN-<name>/` 下 `spec.md`（需求与验收，成对必须）+ `plan.md`（实现方案，
FR 交叉引用 + 真实行数）必备；复杂模块可追加 `tasks.md` / `test-cases.md`。

**预留编号**：`001`+ 待 M1 立项时启用（候选：001-cross-compile-build 四源交叉编译、002-provision-extensions
门禁扩展、003-assets-manifest 随包数据、004-release-pipeline CI 与发布）；编号分配须先写进规划 §10 再建目录。

---

## 三、生成顺序与依据

1. **先整体、后模块**：项目级文档（P-01…P-07）先建立术语、证据口径与 FR 族，模块文档再细化——避免前后引用不存在的文件。
2. **最后生成索引**：`README.md` 与本文件按**实际目录内容**生成/校对，不预测结构。
3. **不复制粘贴**：所有结论回引 `docs/000-工程规划.md` 的 § 号与决策号（D1–D7/R1–R11），避免漂移；新增平台结论先落规划文档（C8）。
4. **证据标记**：每条非显然结论带 ✅实测 / 🔶沿用 / ⬜未实测 / ⚠️冲突 之一（口径见 [`constitution.md`](./constitution.md) §二）。

---

## 四、质量检查

| 检查项 | 结果 |
|---|---|
| 每条结论可回溯到源码 `path:line` 或规划 § 号 | ✅ |
| 无占位内容（`TODO` / `TBD` / 「待补充」；lock 内的 `TBD` 为**制品字段原值**，已如实引用并标 ⬜） | ✅ |
| `overall-spec.md` 不含实现细节（文件路径/工具名） | ✅（技术无关表述） |
| `plan.md`（000-scaffold）引用真实文件路径与真实行数 | ✅ |
| `plan.md` 交叉引用本模块 `spec.md` 的 `FR-000-*` | ✅（§5 映射表） |
| as-built 与 planned 逐条区分（⬜ + 「规划引用」标注） | ✅ |
| README 链接全部指向存在的文件 | ✅（生成时逐链接校验） |
| 模块数与 `NNN-*/` 实际目录数一致 | ✅（1/1） |
| [NEEDS CLARIFICATION] ≤ 3 处/份 | ✅（仅 000-scaffold/plan.md 1 处 NC-1） |

---

## 五、未闭合项（不属文档缺失，属**实现**阶段工作）

| 项 | 归属 | 依据 |
|---|---|---|
| fetch / build 脚本真实实现（四源钉选、交叉编译、strip） | M1-T1/T2/T3 | 规划 §4/§10 |
| helper 实产清单探明 + `libgit_*.so` 命名 + assets 收集 | M1-T3/T4 | 规划 §5.2（R1） |
| provision 扩展（helper 同门禁 + jniLibsWhitelist + manifest 一致性 + assets 校验） | M1-T5 | 规划 §5.3 |
| CI 真实流水线 + GitHub Release（含 GPLv2 四源归档）+ lock 回写 released | M1-T6 | 规划 §9/§10.1（C7/D7） |
| useLegacyPackaging 落盘对照 + exec 回程探针 | M1-T7 | 规划 §10（工作区探针 1/2） |
| 物化 + symlink 农场 + env 注入 + 真机 P1–P7 | M2 | 规划 §7.3（R2 SELinux 农场为五线共享前提） |
| Maven Central 发布 | M3 | 规划 §10.1 + 工作区 runbook |
| 残留字段清理（`VERSION_NAME` / `pairedRuntime`）+ 兜底 allowedNeeded 对齐 + `gates` 语义定稿（NC-1） | M1 顺手 | STRUCTURE §5 / plan.md §7 |
