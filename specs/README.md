# 规格文档索引 —— `aosp-git-cli`

**项目名称：** `aosp-git-cli`（Maven 坐标 `io.github.fellow99:git-cli`）
**需求：** **000-scaffold 工程搭建** · 规范文档存放目录：`specs/`
**库状态：** M0 骨架已完成（Gradle 骨架 + exec 门禁 provision + draft lock + 骨架脚本 + 配置期 CI）；git 本体尚未构建（M1 ⬜）
**技术栈：** Gradle 9.4.1 + AGP 9.2.1 + vanniktech 0.37.0（`:git-cli` AAR 容器，零源码，useLegacyPackaging=true）+ 纯 Node exec 门禁（`tools/provision.mjs`）+ M1 四源（git/zlib/curl/openssl）静态交叉编译（规划）
**文档生成时间：** 2026-11-02 · **最后更新：** 2026-11-02

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
| 模块 | 工程搭建（`000-scaffold`） | 4 | spec（既有）· plan（本批新增）· tasks（既有）· test-cases（既有） |
| 索引 | 本索引 | 1 | `README.md` |
| **合计** | **1 目录 / 13 文件** | | 其中模块目录 1 个，模块文档 4 份 |

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

## 三、模块：000-scaffold — 工程搭建

> 确立仓库结构、构建系统、版本纪律、exec 门禁工具与配置期 CI，使 M1 交叉编译只需在骨架内填充实现。
> 现状：实现全部落地（tasks T1–T8 ✅）；git 本体、helper、assets 属 M1/M2（⬜ 规划引用）。

| 文档 | 链接 | 说明 |
|---|---|---|
| 功能规格 | [000-scaffold/spec.md](./000-scaffold/spec.md) | 模块功能规格（目的、FR-000-001~042 摘要、验收场景）· 既有 |
| 技术方案 | [000-scaffold/plan.md](./000-scaffold/plan.md) | **as-built 实现方案**：技术上下文、宪法合规逐条检查、`git-cli.lock.json` 全字段数据模型、provision CLI 与退出码契约（七门禁逐条行号）、文件清单（真实行数）、FR 交叉引用、NC-1 未确认项 · **本批新增** |
| 任务拆解 | [000-scaffold/tasks.md](./000-scaffold/tasks.md) | T1–T8 全勾 · 既有 |
| 测试用例 | [000-scaffold/test-cases.md](./000-scaffold/test-cases.md) | TC-01~05 + 2026-11-02 执行记录 ✅ · 既有 |

---

## 四、模块编号一览

| 编号 | 模块名 | 目录 | 状态 | 规划出处 |
|---|---|---|---|---|
| 000 | 工程搭建（scaffold） | [`000-scaffold/`](./000-scaffold/) | ✅ M0 完成（含本批 plan.md） | 规划 §10 M0 |
| 001+ | M1 立项时分配（候选：cross-compile-build / provision-extensions / assets-manifest / release-pipeline） | `specs/001-…` 起 | ⬜ 未建 | 规划 §10 M1-T1~T6 |

> 编号分配须**先写进规划 §10 再建目录**（C8）；`specs/` 当前只有 `000-scaffold/` 一个模块目录。

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
