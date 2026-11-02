# overall-plan.md —— `aosp-git-cli` 整体技术方案

> **性质**：项目级**实现计划**（怎么做、按什么顺序做、宪法如何逐条对齐、横切关注点、测试与发布策略）。
> **上位约束**：[`constitution.md`](./constitution.md)（C1–C8）· [`../docs/000-工程规划.md`](../docs/000-工程规划.md)（唯一规划基线，下称「规划 §」）。本文引用其 § 号，不复制正文。
> **标记**：✅实测 / 🔶沿用 / ⬜未实测 / ⚠️冲突或风险。**行号以 2026-11-02 实读为准**。
> **版本**：v1.0 · 2026-11-02 · 状态：M0 已完成（骨架 + 门禁 + draft lock + 配置期 CI）；M1 未开工。

---

## 1. Technical Context

### 1.1 运行环境

| 项 | 值 | 证据 |
|---|---|---|
| 构建侧 | Gradle 9.4.1（CI `setup-gradle@v4` 钉版，workflow:29-32）· AGP 9.2.1（`gradle/libs.versions.toml:2`）· JDK 21 temurin（workflow:23-27）· vanniktech 0.37.0（`settings.gradle.kts:3`） | ✅ |
| 门禁侧 | 纯 Node（`node:fs/path/crypto/url`）；本机 Node v24.7.0；零第三方依赖 | ✅ |
| 交叉编译侧 | NDK（r28c+，与 aosp-node-runtime 对齐 ⬜）· Android API 24（默认）· arm64-v8a | ⬜ M1（lock `androidApi:24` ✅ 已锁） |
| CI runner | `ubuntu-24.04`（M0）；M1 追加 autoconf/make/gcc/curl/file/tar/xz/ccache（规划 §9） | ✅ / ⬜ |
| 消费侧 | 终端 App（node-pty 宿主）；targetSdk≥29 ⇒ SELinux C1（nativeLibraryDir 是唯一合规执行位） | 🔶 工作区 §2 硬约束 |
| 坐标 | `io.github.fellow99:git-cli:<CLI_VERSION>`；当前 2.51.0（draft） | `gradle.properties:7` + lock ✅ |

### 1.2 关键依赖与锁定

| 依赖 | 版本/标识 | 锁定位置 | 状态 |
|---|---|---|---|
| git 源码包 | `github.com/git/git` releases `git-<ver>.tar.gz`；draft 2.51.0，M1 钉选回写 | `lock.builtFrom.source` | ⬜（现为文本描述） |
| zlib / libcurl / OpenSSL | 官方源码包，各 M1 钉版 + sha256 | `lock.builtFrom.deps`（M1 升级为版本表） | ⬜ |
| CA bundle | cURL 来源 `cacert.pem`，钉版 + sha256 | assets manifest（M1） | ⬜ |
| NDK | r28c 或更高 | `lock.builtFrom.ndk`（现 `TBD`） | ⬜ |
| Gradle/AGP/发布插件/JDK | 9.4.1 / 9.2.1 / 0.37.0 / 21 | 各配置文件 | ✅ |

### 1.3 已闭环的平台事实（方案的基石）

| # | 事实 | 等级 |
|---|---|---|
| 1 | targetSdk≥29 的 SELinux 禁止从可写数据目录 exec ⇒ exec 型二进制必须物理落盘 `nativeLibraryDir`（`useLegacyPackaging=true`） | 🔶 工作区 C1（配置已落地 ✅，落盘效果 ⬜ M1-T7） |
| 2 | exec 型与 dlopen 库的门禁三处相反（PT_INTERP / NEEDED 白名单 / 无 NAPI） | ✅ `provision.mjs:9-16` |
| 3 | git 把 https/本地传输委托给独立进程 helper（按 `<GIT_EXEC_PATH>/git-remote-<scheme>` 名字查找）；本地 clone/fetch/push 也经 dashed 子进程 | 🔶 规划 §5.2（⬜ 本域 GIT_TRACE 实证 P2/P3） |
| 4 | Termux 为「Android 上交叉编译 git」的社区成熟先例；上游无官方 Android 支持 | 🔶 规划 §1.2/§4.2 |
| 5 | 干净工程无 `.so` 时 `gradle :git-cli:tasks` / `assembleDebug` 成功；`provision --check` 未投放=exit 2 | ✅（TC-01~03，2026-11-02 执行记录） |

---

## 2. 宪法符合性检查（逐条）

| 原则 | 判定 | 证据 |
|---|---|---|
| **C1 fetch 不改源** | ✅ 符合（纪律层） | 脚本骨架文件头明文纪律（`fetch-git-cli-source.mjs:9`、`build-git-cli-android.sh:5-11`）；缺项以 `NO_*`/`--without-*` 关闭；仓库无任何补丁痕迹。真实执行 ⬜ M1 |
| **C2 lock 唯一事实源** | ✅ 符合 | lock 含 active/releases/matrix；draft `size=0`/`sha256:""` 诚实（`git-cli.lock.json:13-14,35`）；provision 只认 lock（`:177-197`）。⚠️ `gates` 字段 draft 即全 true 且无工具读取（语义 [NEEDS CLARIFICATION]，见 000-scaffold/plan.md §7） |
| **C3 二进制不入库** | ✅ 符合 | `.gitignore:23-24`（jniLibs/**.so、assets/**）+ `:27-28`（.dist/、build/out/）；仓库当前无任何 `.so` ✅ |
| **C4 门禁强制** | ✅ 符合 | 七门禁硬判定（`:146-167`）；draft 只记录不比对（`:156-159`）；jniLibs 单文件白名单（`:222-228`）；`libnode.so` 禁入（`:38,246-250`）；`--allow-page-align-4k` 仅 bring-up 且打 ⚠（`:162-167`）。⚠️ 兜底 allowedNeeded 缺 `liblog.so`（`:184`，漂移点，STRUCTURE §5-3） |
| **C5 发布卫生** | ✅ 符合 | `RELEASE=false` 默认（`gradle.properties:19`）；sign/publish 任务 disable 门禁（`publish.gradle.kts:133-139`）；凭据仅用户级（`:12-14` + local.example 模板）；POM SCM 补丁指向本仓（`:115-131`） |
| **C6 未实测标 ⬜** | ✅ 符合 | 规划全文遵循；本 specs 套件全部结论带标记；M1 试编项（configure 参数/体积/helper 清单）一律 ⬜ |
| **C7 GPLv2 对应源码义务** | ✅ 登记完成 / ⬜ 交付未发生 | `git-cli/THIRD-PARTY-NOTICES.md:16-17` 明文义务；Release 归档随附四源 tarball + 构建脚本（规划 §10.1）；措辞定稿 ⬜（R5） |
| **C8 先改文档再改实现** | ✅ 符合 | 规划 v2.0 先行（含 M1/M2 设计）；本批 as-built 规格只回引其 § 号；偏差随里程碑回写规划 |

**结论**：0 条违背；2 处 ⚠️ 漂移点（allowedNeeded 兜底、`gates` 语义）+ 2 处残留字段（`VERSION_NAME`、`pairedRuntime`）已登记 STRUCTURE §5，均不影响 M0 出口。

---

## 3. 实现策略总览

### 3.1 里程碑 ↔ 现状 ↔ 模块（规划 §10/§10.2）

| 里程碑 | 内容 | 模块归属 | 现状 |
|---|---|---|---|
| **M0 骨架** | Gradle 骨架、exec 门禁 provision、draft lock、骨架脚本、配置期 CI | 000-scaffold | ✅ 完成（T9 残留收口 ⬜） |
| M1-T1 | fetch 完整实现（五输入钉选 + sha256；deps 版本表回写） | 001-building T1/T2 | ⬜ |
| M1-T2 | 依赖静态构建（zlib→openssl→curl，全 `.a`） | 001 T3~T5 | ⬜ |
| M1-T3 | git configure/make 首轮试编 + **helper 实产清单探明**（回写规划 §5.2/lock） | 001 T6~T8 | ⬜（R1 高风险首项） |
| M1-T4 | strip + 16KB + helper `libgit_*.so` 命名 + assets 收集 | 001 T9~T11 | ⬜ |
| M1-T5 | provision 扩展（helper 同门禁 + jniLibs 白名单 + manifest 一致性 + assets 校验） | 002-building-workflow T1~T6 | ⬜ |
| M1-T6 | CI 真实流水线 + Release `v<gitver>`（含 C7 归档）+ lock 回写 | 002 T7~T9 | ⬜ |
| M1-T7 | 最小消费探针（useLegacyPackaging 对照 + exec 回程 `git --version`） | 003-cli（本仓 adb 等价部分）+ 消费方（App 域） | ⬜（工作区探针 1/2） |
| M2 | 消费方物化 + 农场 + env 注入 + 真机 P1–P7 | 003-cli（shell 域等价）+ 消费方（App 域） | ⬜ |
| M3 | Maven Central 发布 | —（publish.gradle.kts 已内置） | ⬜ |
| M4 | 跟随机制（git 新版 runbook）；可选 openssh 伴生线立项 | — | ⬜ |

### 3.2 依赖顺序（不可并行者）

```
① fetch（五输入钉选）──▶ ② 依赖静态构建 ──▶ ③ git 试编 + helper 清单探明（R1/R7/R8/R9 出口）
                                                      │
                                                      ▼
                              ④ strip/16KB/命名/assets（M1-T4）──▶ ⑤ provision 扩展（M1-T5）
                                                                            │
                                    ⑥ CI 真实流水线 + Release + lock 回写（M1-T6）◀┘
                                                      │
                              ⑦ 消费探针（M1-T7）→ ⑧ 物化/农场/真机 P1–P7（M2）→ ⑨ Maven Central（M3）
```

纪律：③ 的「helper 清单」是 ④⑤⑥ 的输入，**必须先探明再写白名单**（规划 §10 M1-T3 出口）；
⑤ 未完成前 ⑥ 不得 Release（门禁缺口）；⑧ 的 P5（SELinux 农场）是五线共享前提，**最早验证点**。

### 3.3 M0 出口判据 → 实测映射

| 判据（规划/tasks.md T8） | 命令 | 结果 |
|---|---|---|
| 干净工程可配置 | `gradle :git-cli:tasks` | ✅ TC-01 |
| AAR 容器可产出 | `gradle :git-cli:assembleDebug` | ✅ TC-02（786 B 空容器） |
| provision 未投放语义 | `node tools/provision.mjs --check` | ✅ TC-03（exit=2，文案含「未投放」） |
| 语法门 | `node --check` ×2 + `bash -n` | ✅ TC-04 |
| 二进制不入库 | 版本库状态核对 | ✅ TC-05 |

---

## 4. 跨切面关注点

### 4.1 错误处理与退出码

| 层 | 策略 | 依据 |
|---|---|---|
| provision | 硬失败 `exit 2`（门禁/未投放）；用法/IO `exit 1`（顶层 catch，`:271-276`）；错误消息给**明确出路**（「先跑 --out …」/ lock 现有条目列表） | C4/C2 · FR-000-030 |
| fetch/build（骨架） | 未实现 = `exit 2` + stderr 说明「M1 实现」，不假装成功 | C6 |
| Gradle | `CLI_VERSION` 缺失即 error（不静默默认）；发布任务默认 disabled | FR-000-003 / C5 |
| 失败可见性口径 | 门禁输出逐项 `✔/✘` + 细节（`printGates`，`:171-173`），可粘贴为证据 | C6 |

### 4.2 日志口径

- progress 走 stdout（统一 `[provision]` / `[fetch]` / `[build]` 前缀）；失败走 stderr；无文件日志——
  门禁工具的一次输出即证据（可复制进 PR/CI 日志）。
- ⚠ 级别：draft 告警（`:197`）与 `--allow-page-align-4k` 放行告警（`:166`）必须保留，不得静默。

### 4.3 供应链与安全

| 项 | 策略 |
|---|---|
| 源钉选 | 四源 + cacert 各自 sha256（M1-T1）；官方 URL，不引第三方镜像 |
| 禁入 | `libnode.so` 禁入本 AAR（`BANNED_IN_AAR`）；白名单外 `.so` 拒绝 |
| 凭据 | 用户级 gradle.properties；仓库只有占位模板 |
| 运行期 | 零下载、零网络组件；assets 纯数据；农场只建 symlink |
| 16KB | LDFLAG `-Wl,-z,max-page-size=16384`（M1）+ 门禁⑦（✅）双保险 |

### 4.4 许可（GPLv2 义务，C7/D7）

- 本仓自身 MIT；git 本体（含 helper）GPLv2 ⇒ Release 归档随附四源 tarball + 构建脚本；
  NOTICES 已登记五项第三方 + 义务声明；Maven 阶段 sources jar 与「对应源码」表述 M1-T6 前定稿 ⬜（R5）。

### 4.5 体积

预算（🔶 工作区 §3.3 估，⬜ 首产回填）：本体 2–5MB + curl/openssl 静态增量 ≈5–8MB；
超标先裁 git-http-fetch/push/imap（R6 处置）。

---

## 5. 测试途径

| 层 | 内容 | 真机 | 现状 | 索引 |
|---|---|---|---|---|
| L1 host 门禁 | 七门禁 + draft 语义 + 白名单 + 退出码契约 + 语法门 | ❌ | ✅（TC-01~05；负例 ⬜） | [`overall-test-cases.md`](./overall-test-cases.md) |
| L1.5 构建可复现 | 干净 runner 重出同口径制品、哈希一致 | ❌ | ⬜ M1-T6 | 同上 |
| L3 消费探针 | useLegacyPackaging 对照 + exec 回程 | ✅ | ⬜ M1-T7 | 规划 §10 M1-T7 |
| L3 真机回程 | P1–P7（版本/本地链/https/农场/CA/16KB） | ✅ | ⬜ M2 | 规划 §7.3 |

**禁止的判据**：① 「脚本骨架打印了计划」≠「能构建」（骨架 exit 2 是诚实信号）；② 「draft 全 true 的
gates 存档」≠「产物过门禁」（门禁以 provision 逐次解析为准）；③ 「配置期 CI 绿」≠「真机能跑 git」
（L3 之前一切能力表述都是 ⬜）。

---

## 6. 发布策略（两段式，规划 §10.1）

1. **先行 GitHub Release（M1-T6，tag `v<gitver>` 触发）**：归档 `git-cli-v<ver>-android-arm64-v8a.tar.gz`
   （lib*.so 集 + assets + BUILD/FETCH-METADATA + LICENSES + **四源 tarball 与构建脚本**）+ `.sha256`；
   lock 回写 `status=released`（含真实 size/sha256，C2）。**GPLv2 对应源码义务以此归档履行（C7/D7）。**
2. **随后 Maven Central（M3）**：按工作区 runbook
   [`../../../docs/发布到maven-central.md`](../../../docs/发布到maven-central.md)（§2 凭据 → §4 发布前检查 →
   §5 上传 → §6 核验回填 `mavenCentral.published=true`）；`publish.gradle.kts` 已内置该管线；
   manifest 校验纳入发布前检查（runbook §10 已登记复用，⬜ 首次实走后回填）。
3. **卫生门禁**：`RELEASE=false` 默认（发布任务禁用）；凭据仅用户级；`AUTOMATIC_RELEASE=true` 才
   validation=PUBLISHED（默认人工在 Portal 点 Publish）。
