# constitution.md —— `aosp-git-cli` 项目宪法（治理原则）

> 本文件是 `aosp-git-cli` 的**最高约束**。任何 `spec.md` / `plan.md` / 实现 / CI / 评审都必须先过这一关。
> 原则不是发明的，而是从**已落地的代码**（`tools/provision.mjs`、`git-cli.lock.json`、Gradle 骨架）与
> **唯一规划基线**（`docs/000-工程规划.md` v2.0）中抽取的（依据列在每条末尾）。
>
> - 权威规划文档：[`../docs/000-工程规划.md`](../docs/000-工程规划.md)（v2.0，**结论以它为准**，下称「规划 §」）
> - 工作区级纪律来源：[`../../../docs/aosp+node+python+git运行方案.md`](../../../docs/aosp+node+python+git运行方案.md)（fetch 不改源 / exec 门禁 / symlink 农场 / 制品线）
> - 版本：v1.0 · 2026-11-02 · 状态：**生效**（M0 骨架已完成，git 本体尚未构建）
> - 适用：Gradle 骨架 · `tools/` · `scripts/` · `git-cli.lock.json` · CI · `specs/`

---

## 一、八条不可协商的原则

### C1. fetch 不改源（No Source Patching）

**构建输入（git / zlib / curl / openssl 源码包）必须原样使用，禁止任何源码补丁。**

- Android/bionic 缺项一律以**配置关闭**回答：git 侧 `NO_TCLTK` / `NO_GETTEXT` / `NO_ICONV` / `NO_REGEX`
  （自带 compat/regex）/ `NO_PERL` / `NO_PYTHON`；curl 侧缺库一律 `--without-*`
  （`--without-libpsl` / `--without-brotli` / `--without-zstd`），不引入新源；
- 禁止第三方 fork、禁止下载后改文件再校验——SHA-256 钉的是**官方原包**；
- 裁剪导致的能力缺失必须**如实登记**（如 dumb-http / DAV push 是否随包 ⬜），不得静默。

依据：规划 §D3 · §4.1/§4.2 · §13「fetch 不改源」；`scripts/fetch-git-cli-source.mjs:9`（文件头纪律注释）。

---

### C2. lock 唯一事实源（Single Source of Truth）

**`git-cli.lock.json` 是版本、大小、SHA-256、门禁、出处、发布状态的唯一事实源。**

- 制品版本 = git 上游版本，**独立 semver**，与 node 系无配对、无 `NODE_MODULE_VERSION` 约束（D4）；
- **draft 不伪造哈希**：`size=0` / `sha256=""` 就是「尚未构建」的诚实表达；首个真实 CI 构建后才回写
  `status=released` 与真实哈希（规划 §8）；
- 四源（git/zlib/curl/openssl）+ cacert 各自独立钉版，版本表进 `builtFrom.deps`（M1 扩展 ⬜）；
- 改制品必先改 lock，lock 与产物不一致 = 门禁硬失败。

依据：规划 §2/§8/§13 · `tools/provision.mjs:5`（文件头）· `git-cli.lock.json:2`（$comment）。

---

### C3. 二进制不入库（Binaries Stay Out of the Repo）

**`.so` 与随包 assets 树绝不进版本库；由 CI 产出、`tools/provision.mjs` 投放。**

- `.gitignore:23-24`：`git-cli/src/main/jniLibs/**/*.so` 与 `git-cli/src/main/assets/**`；
- 投放落点 `git-cli/src/main/jniLibs/<abi>/` 由 provision 幂等创建；当前**不存在**（尚未投放）；
- 工作区产物 `.dist/`、`build/out/` 同不入库（`.gitignore:27-28`）。

依据：规划 §8/§13 · `specs/000-scaffold/spec.md` FR-000-010~013 族。

---

### C4. 门禁强制（Gates Are Mandatory）

**exec 型 ELF 门禁是投放的前置硬条件；任一不过 = 拒绝投放（exit 2），绝不「凑合放行」。**

- 门禁 profile（exec 型，与 dlopen 库门禁相反处）：
  ① `ET_DYN`（PIE）；② **PT_INTERP 恰 1 个且 = `/system/bin/linker64`**；③ `e_machine = AArch64`；
  ④ **DT_NEEDED ⊆ lock `matrix.allowedNeeded` 白名单**（静态链入后只允许系统库）；
  ⑤ SHA-256 与锁一致；⑥ 大小与锁一致；⑦ **16KB 页对齐**（min LOAD align ≥ 0x4000）；
- draft 期 ⑤⑥ **只记录不拦截**（无锁值不谎报；首个真实构建后锁值为 CI 钉选参考值，失配打 ⚠ 但放行——产物不必比特级可复现）；**released 后 ⑤⑥ 硬比对**（实现：`provision.mjs` enforceHash= status==='released'）；
- jniLibs 兄弟文件纪律：白名单 = lock `matrix.jniLibsWhitelist`（首个真实构建起为 `libgit_cli.so` + helper 集，
  规划 §10.3）；`libnode.so` **禁入**（由 node-runtime 统一供给）；
- `--allow-page-align-4k` 是唯一放行开关，**仅限 bring-up**，输出必须打 ⚠ 警示，上架/16KB 设备不合格。

依据：规划 §6/§12 · `tools/provision.mjs:9-24`（文件头差异说明）· `:146-167`（门禁实现）· `:222-228`（兄弟文件检查）。

---

### C5. 发布卫生（Release Hygiene）

**发布动作必须显式、可门禁、凭据零入库。**

- `RELEASE=false`（默认）：Central 上传与签名任务**被禁用**，防误发
  （`publish.gradle.kts:133-139` 任务 disable 门禁）；
- Portal Token / GPG 只从**用户级** `~/.gradle/gradle.properties` 读取；仓库只提供
  `gradle.properties.local.example` 模板（8 行，占位符）；
- 发布走**两段式**：GitHub Release 先行（M1-T6 ⬜，归档含源码 tarball，见 C7）→ Maven Central 随后
  （M3 ⬜，runbook：[`../../../docs/发布到maven-central.md`](../../../docs/发布到maven-central.md)）；
  lock 回写 `status=released` / `mavenCentral.published=true` 才算闭环。

依据：规划 §10.1/§12 · `publish.gradle.kts:12-14`（纪律注释）· `gradle.properties:18-19`。

---

### C6. 未实测标 ⬜（Unverified Is Not Fact）

**凡未在本仓实测过的断言，一律带 ⬜，绝不当作已定事实引用。**

- M1 的交叉编译参数（zlib `CHOST` configure、openssl `android-arm64`、curl 交叉 configure、
  git `make configure`/`config.mak` 回退）、helper 实际产物清单、体积、symlink 农场的 SELinux 放行
  —— 全部 ⬜（规划 §4/§5.2/§11 R1–R11）；
- 规格文档的「现状」列必须区分 ✅实测 / 🔶沿用 / ⬜未实测 / ⚠️冲突（见 §三）；
- 🔶沿用（工作区 §4.3 命令农场、Termux 先例）**不得**作为本仓对外承诺的依据，须以本域探针（P1–P7）实证。

依据：规划文件头「纪律」· §7.3（探针表）· §11（风险表）。

---

### C7. GPLv2 对应源码义务（GPL Corresponding Source Obligation）

**git 本体（含 helper）为 GPLv2；二进制分发必须同时提供对应源码。**

- Release 归档**必须**随附构建所用源码 tarball ×4（git/zlib/curl/openssl）与构建脚本——
  这是 GPLv2「corresponding source」（preferred form for modifications）的履行方式（D7）；
- 仅给上游链接**不视为**义务履行（D7 反面列明，措辞 M1-T6 前定稿 ⬜，R5）；
- `git-cli/THIRD-PARTY-NOTICES.md` 已登记五项第三方组件（git GPLv2 / zlib / curl / OpenSSL Apache-2.0 /
  CA bundle）与该义务；helper 归属 git 源码树的措辞 M1 补。

依据：规划 §D7/§10.1/§12 · [`../git-cli/THIRD-PARTY-NOTICES.md`](../git-cli/THIRD-PARTY-NOTICES.md)。

---

### C8. 先改文档再改实现（Plan Before Code）

**`docs/000-工程规划.md` 是唯一规划基线；变更走「先改本文件，再改实现」，偏差随里程碑回写。**

- M0 → M1 的每一步（fetch 实现、四源试编、helper 清单探明、provision 扩展、CI 真实流水线）都先在
  规划 §10 任务表立项，实现后回写结论（helper 清单回写 §5.2、体积回填 lock）；
- `specs/` 是规划的收敛/展开版：只做细化与验收，**不复制粘贴**，结论回引规划 § 号；
- 里程碑出口（G1–G4）是验收线：G1 交叉编译过门禁并 Release · G2 assets 过 manifest 校验 ·
  G3 真机回程 · G4 lock=released。

依据：规划文件头（版本纪律）· §10/§10.1 · `specs/README.md` 文档规则。

---

## 二、证据纪律（Evidence Discipline）

全文使用四种标记，**不要把推断当实测**：

| 标记 | 含义 |
|---|---|
| ✅ **实测** | 本工程内可复核的一手证据（源码 `path:line`、本机命令退出码、AAR 产物内容） |
| 🔶 **沿用** | 沿用同型仓/工作区方案的一手记录（本域**未复现**：如 symlink 农场 SELinux 放行、Termux 先例） |
| ⬜ **未实测** | 本工程必须自行实测后才能定稿（M1/M2 项） |
| ⚠️ **冲突/风险** | 两份材料互斥，或存在已知风险（规划 §11 R1–R11） |

两条纪律：

1. `🔶 沿用` 的结论不得直接写进对外承诺；进入 M2 真机探针（P1–P7）后转 ✅。
2. M0 的全部「已建成」结论仅覆盖**骨架与门禁工具**；任何「git 能在 Android 上跑」的表述在 M2 前都是 ⬜。

---

## 三、评审清单（Reviewer Checklist）

评审任何 `spec.md` / `plan.md` / PR 时逐条问：

- [ ] 是否给源码打了补丁或引入了 fork？（C1）
- [ ] 版本/哈希/出处是否以 lock 为准？draft 是否诚实？（C2）
- [ ] `.so` / assets 是否试图入库？（C3）
- [ ] 门禁是否可绕过？draft 是否被当成 released 用？（C4）
- [ ] 发布是否可能误触发？凭据是否入库？（C5）
- [ ] 新断言是否带了正确的证据标记？（§二）
- [ ] GPLv2 对应源码义务是否被满足（Release 归档面）？（C7）
- [ ] 是否先改了规划文档再动实现？（C8）

---

## 四、变更流程

1. 改发布口径（坐标/版本策略/插件版本）⇒ 先改规划 §2/§10.1，再改 `publish.gradle.kts` /
   `gradle.properties`，并同步 `specs/TECH.md`。
2. 改 `git-cli.lock.json`（换版本/回写哈希）⇒ 必须重跑 `node tools/provision.mjs --check`；
   `status` 只允许 `draft → released` 单向推进。
3. 新增平台结论（探针 P1–P7 结果、helper 实产清单）⇒ **先写进 `docs/000-工程规划.md`**（唯一权威），
   规格文档只引用其 § 号，不复制粘贴。
4. 改 provision 门禁判据 ⇒ 同步规划 §6/§12 与 `specs/000-scaffold/plan.md` §4，且退出码契约（0/2/1）不变。
