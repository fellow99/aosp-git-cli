# overall-test-cases.md —— `aosp-git-cli` 全模块测试用例索引

> **性质**：**索引文档**（不是逐条用例全集）。逐条用例与执行记录在 [`000-scaffold/test-cases.md`](./000-scaffold/test-cases.md)（TC-01~05，含 2026-11-02 执行记录）；本文负责①分层口径 ②用例族索引 ③规划探针引用 ④禁止的判据。
> **依据**：[`constitution.md`](./constitution.md)（C1–C8）· [`../docs/000-工程规划.md`](../docs/000-工程规划.md)（下称「规划 §」）。
> **标记**：✅已实现可跑 / ⬜规划未实现（归属里程碑）/ ⚠️风险项。
> **判据纪律**：每条判据必须可证伪（有通过/不通过二元出口）；无二元出口的条目不得进表。
> **版本**：v1.0 · 2026-11-02。

---

## 1. 测试分层

| 层 | 代号 | 真机 | 跑在哪 | 目的 | 现状 |
|---|---|---|---|---|---|
| **host 侧门禁** | **L1** | ❌ | 开发机 / CI（node + gradle） | 工程可配置、AAR 容器可产出、退出码契约、语法门、二进制不入库；M1 后扩展为七门禁全判 | ✅ TC-01~05 已跑（000-scaffold/test-cases.md） |
| **构建可复现** | **L1.5** | ❌ | 干净 CI runner | fetch 钉选 → 交叉编译 → 门禁 → 归档，哈希可重现 | ⬜ M1-T6 |
| **消费探针** | **L3** | ✅ | 探针 App / 手动塞 jniLibs | useLegacyPackaging true/false 对照 + `execve` 回程 `git --version`（工作区探针 1/2） | ⬜ M1-T7 |
| **真机回程** | **L3** | ✅ | 真机（规划 §7.3 P1–P7） | 版本串、本地链、https、symlink 农场 SELinux 放行、CA 反证、16KB 全链 | ⬜ M2-T2 |
| **回归基线** | **L5** | ❌/✅ | 构建产物 | 归档 `.sha256`、lock released 值、体积 | ⬜ M1-T6 首产起 |

**顺序纪律**：L3 的任何能力结论必须在 L1 门禁全过之后；L1 绿**不能替代** L3——「配置期 CI 绿」≠「真机能跑 git」（C6）。

---

## 2. 用例族索引

### 2.1 M0（scaffold）——已实现可跑，逐条见 [`000-scaffold/test-cases.md`](./000-scaffold/test-cases.md)

| 用例族 ID | 名称 | 层 | 覆盖 FR | 判据（可证伪） | 命令 | 状态 |
|---|---|---|---|---|---|---|
| TC-000-01 | 干净工程可配置 | L1 | FR-000-005 / 001 | 任务求值 BUILD SUCCESSFUL | `gradle :git-cli:tasks --console=plain` | ✅ |
| TC-000-02 | AAR 容器可产出 | L1 | FR-000-002 | AAR 产物存在；`classes.jar` 为空（无源码） | `gradle :git-cli:assembleDebug` + 解包核对 | ✅ |
| TC-000-03 | 未投放语义 | L1 | FR-000-030/032 | 退出码 = 2，文案含「未投放」 | `node tools/provision.mjs --check; echo $?` | ✅（2026-11-02 复核） |
| TC-000-04 | 语法门 | L1 | FR-000-042 | `node --check` ×2 + `bash -n` 全过 | 同左 | ✅ |
| TC-000-05 | 二进制不入库 | L1 | FR-000-010~013 / C3 | 版本库状态无 jniLibs/assets 条目 | 版本库清单核对 | ✅ |

### 2.2 M0 补充负例（实现已具备，负例未跑 ⬜；M1 全链时一并执行）

| 用例族 ID | 名称 | 层 | 覆盖 FR | 判据（可证伪） | 命令 | 状态 |
|---|---|---|---|---|---|---|
| TC-000-06 | 用法错误退出码 | L1 | FR-000-030 | `--out` 缺 `--from` ⇒ exit 1（stderr 给出缺失项） | `node tools/provision.mjs --out foo` | ✅（2026-11-02 复核） |
| TC-000-07 | 兄弟文件白名单负例 | L1 | FR-000-033 | jniLibs 出现第二个 `.so` ⇒ `--check` exit 2 并列出非法文件 | 投放后放一个假 `.so` 再 `--check` | ⬜（需先有真实投放） |
| TC-000-08 | 禁入库负例 | L1 | FR-000-034 | 投放目录存在 `libnode.so` ⇒ 报错终止 | 构造该场景 | ⬜（同上） |
| TC-000-09 | 门禁七项负例 | L1 | FR-000-031 | 非 ELF / PIE 无 interp / x86 产物 / 超 4KB 对齐 ⇒ 各自 ✘ 且 exit 2 | `provision --inspect <构造文件>` | ⬜（M1 用真实产物） |
| TC-000-10 | draft 只记录不比对 | L1 | FR-000-032 | draft 下改产物字节 ⇒ ⑤⑥ 显示「仅记录」，其它门禁仍判死 | 构造字节差异 | ⬜（M1） |

### 2.3 M1/M2/M3（规划引用，未实现 ⬜）

| 用例族 ID | 名称 | 层 | 规划出处 | 判据（可证伪） | 状态 |
|---|---|---|---|---|---|
| TC-M1-01 | fetch 五输入钉选 | L1.5 | §4.1/§10 M1-T1 | 四源 + cacert 哈希与钉选一致；`.dist/src` 可复现 | ⬜ |
| TC-M1-02 | 依赖静态构建 | L1.5 | §4.2 M1-T2 | `libcurl.a` 等产物存在且可链接 | ⬜ |
| TC-M1-03 | git 试编 + helper 清单 | L1.5 | §4.2④/§10 M1-T3 | `libgit_cli.so` + helper 集产出；实产清单回写 §5.2/lock | ⬜ |
| TC-M1-04 | 七门禁全过（含 16KB） | L1 | §6 | 每个产物（主+helper）七项 ✓ | ⬜ |
| TC-M1-05 | provision 扩展 | L1 | §5.3 M1-T5 | 白名单校验、manifest 一致性、assets 纯数据校验通过；负例拒绝 | ⬜ |
| TC-M1-06 | CI 流水线 + Release | L1.5 | §9/§10 M1-T6 | 干净 runner 重出同哈希；归档含四源 tarball + 构建脚本（C7）；lock=released | ⬜ |
| TC-M1-07 | 落盘探针 | L3 | §10 M1-T7 | `useLegacyPackaging=true` 时物理件在 nativeLibraryDir；`git --version` 回程 | ⬜ |
| TC-M2-01~07 | 真机回程 P1–P7 | L3 | §7.3 | P1 版本回程 · P2 本地链 · P3/P4 https · P5 农场 SELinux · P6 CA 反证 · P7 16KB/中文路径 | ⬜ |
| TC-M3-01 | Maven Central 可解析 | L1 | §10.1 | 坐标可拉取；POM/许可/sources 核对 | ⬜ |

---

## 3. 禁止的判据（写进每条用例的验收纪律）

| 禁止的判据 | 为什么是假信号 | 必须改用的判据 |
|---|---|---|
| 「脚本骨架打印了构建计划」⇒ 能构建 | 骨架 `exit 2` 是**诚实信号**（C6）；打印 ≠ 实现 | L1.5 的真实产物 + 哈希 |
| 「lock `gates` 存档全 true」⇒ 产物过门禁 | 无工具读取存档；门禁以 provision **逐次解析产物**为准（C4） | `provision --check` / `--inspect` 的 ✓ 输出 |
| 「配置期 CI 绿」⇒ 真机能跑 git | M0 CI 只覆盖配置/语法/退出码 | L3 真机探针（P1–P7） |
| 「`assembleDebug` 出了 AAR」⇒ AAR 内有 git | M0 的 AAR 是 786 B 空容器 | AAR 条目清单核对（jni/ 非空） |
| 「体积估算」⇒ 体积达标 | 估算属 🔶（工作区口径） | 首产实测回填 lock（R6） |
| 「Exit 0 from provision」⇒ 投放正确 | 需同时核对该目录**只有一个**白名单内 `.so` + 元数据文件 | `--check` 全过 + 目录清单 |

---

## 4. 已知基线数值（用于回归比对）

| 指标 | 值 | 出处 | 等级 |
|---|---|---|---|
| debug AAR | 786 B；条目 = R.txt(0) / AndroidManifest.xml(206 B) / classes.jar(22 B 空) / aar-metadata.properties(157 B) | 本地解包 2026-11-02 | ✅ |
| `provision --check`（未投放） | exit=2，文案含「未投放：…」 | 本机 2026-11-02 | ✅ |
| `provision --out foo`（缺 --from） | exit=1，stderr「--out 需要配 --from」 | 同上 | ✅ |
| `fetch --git 2.51.0` / `build`（参数齐） | exit=2（SCAFFOLD） | 同上 | ✅ |
| min LOAD align 门限 | 0x4000（16KB） | `provision.mjs:160` | ✅ |
| libgit_cli.so 体积 / sha256 | **无**（draft size=0 / sha256=""） | `git-cli.lock.json:13-14` | ✅（诚实空值） |
| 体积预估 | 本体 2–5MB + 静态增量 ≈5–8MB | 规划 §4.2（🔶 工作区估） | ⬜ 首产回填 |

**基线使用方式**：M1 首产后把真实 size/sha256/体积与 lock 逐项 diff；任何变化必须给出版本/配置层解释，否则视为回归。
