# TECH.md —— `aosp-git-cli` 技术选型（as-built + 决策）

> **性质**：项目级技术选型规格。回答「用了什么、什么版本、为什么、否掉了什么、**已实现还是规划**」。
> **依据**：[`constitution.md`](./constitution.md)（C1–C8）· [`../docs/000-工程规划.md`](../docs/000-工程规划.md)（唯一规划基线，下称「规划 §」）· 本仓库文件 ✅实测（2026-11-02）。
> **标记**：✅实测 / 🔶沿用 / ⬜未实测 / ⚠️冲突或风险。**状态列**区分 **已实现（as-built）** 与 **规划（⬜ M1/M2/M3）**——规划项不得当作既成事实引用。
> **版本**：v1.0 · 2026-11-02。

---

## 1. 选型总表（含状态列）

| 类别 | 技术/版本 | 用途 | 选型理由 | 状态 |
|---|---|---|---|---|
| **构建系统** | Gradle **9.4.1**（仓库无 wrapper；CI `setup-gradle@v4` 钉版；本地 `.gradle/9.4.1` 佐证） | 工程构建 / AAR 产出 | 与工作区五条 CLI 线统一；CI 固定版本保证可复现 | ✅ 已实现（配置期可用，TC-01/02 过） |
| **Android 插件** | AGP **9.2.1**（`gradle/libs.versions.toml:2`） | `com.android.library` | AAR 容器所需最小插件面 | ✅ 已实现 |
| **发布插件** | `com.vanniktech.maven.publish.base` **0.37.0**（`settings.gradle.kts:3`） | Maven Central 发布（Central Portal 直连） | 工作区五线同款；`pomFromGradleProperties` + singleVariant + 签名 | ✅ 已实现（发布动作被 C5 门禁禁用） |
| **JDK** | Temurin **21**（CI workflow:23-27） | Gradle 运行时 | AGP 9 要求 | ✅ 已实现 |
| **发布坐标/版本源** | `io.github.fellow99:git-cli:<CLI_VERSION>`；`CLI_VERSION` = git 上游版本，**独立 semver**（`gradle.properties:7`，当前 `2.51.0` draft） | Maven 坐标 | 与 node 系无 ABI 约束、无配对顺序（D4）；缺失即构建报错（`git-cli/build.gradle.kts:16-17`） | ✅ 已实现（值为 draft，M1 以 CI 实际钉选版回写 ⬜） |
| **exec 打包** | `packaging.jniLibs.useLegacyPackaging = true`（`git-cli/build.gradle.kts:42`） | 物理落盘 `nativeLibraryDir` | exec 型硬要求：不落盘则 `execve` ENOENT；targetSdk≥29 SELinux 禁止从可写数据目录 exec（D1/C1） | ✅ 已实现（落盘效果待 M1-T7 探针 ⬜） |
| **模块形态** | `:git-cli` Android library，**零 Kotlin/Java 源**（无 `src/` 树） | AAR 容器 | 本仓不含任何嵌入 API（README/规划 §1.1）；✅ 实测 debug AAR 786 B、`classes.jar` 为空 | ✅ 已实现 |
| **目标 ABI** | 仅 **arm64-v8a**（`abiFilters`，`git-cli/build.gradle.kts:34`；lock `matrix.abi`） | 产物面 | 只发布 AArch64（README/规划 §2） | ✅ 已实现 |
| **SDK 维度** | `minSdk 24` / `compileSdk 36`；lock `androidApi:24`（交叉编译 API level） | 兼容面 | Android 7.0 起步；compileSdk 取当前 AGP 9 支持线 | ✅ 已实现 |
| **exec 门禁工具** | **纯 Node**（`node:fs/path/crypto/url`，零第三方、零 llvm/python 依赖）；`tools/provision.mjs`（276 行） | 极简 ELF64 自解析 + 7 门禁 + 幂等投放 | 「一个 `node` 就能跑」⇒ CI 与消费方机器零依赖（与 pty 线同款骨架、不同 profile） | ✅ 已实现（退出码 0/2/1 本机复核） |
| **门禁 profile** | exec 型：①ET_DYN ②PT_INTERP 恰 1 且=`/system/bin/linker64` ③AArch64 ④DT_NEEDED 白名单 ⑤SHA-256 ⑥size ⑦16KB 对齐 | 投放前置 | 与 dlopen 库门禁**三处相反/差异**（PT_INTERP、NEEDED 白名单、无 NAPI 门禁）——`provision.mjs:9-16` | ✅ 已实现；helper 全集过同一 profile ⬜ M1-T5 |
| **四源静态交叉编译** | git + zlib + libcurl + OpenSSL（官方源码包，各钉版 + sha256）→ 全静态链入 `libgit_cli.so` | https 传输开箱可用、DT_NEEDED 只剩系统库 | D2：产物单文件化、白名单门禁天然满足；构建顺序 zlib → openssl → curl → git | ⬜ **规划（M1-T1/T2/T3）**：脚本骨架已固化接口与纪律（exit 2） |
| **NDK** | r28c 或更高，与 aosp-node-runtime 对齐 | 交叉工具链 | 一台 runner 一条 NDK 线（规划 §4.1） | ⬜ 规划（M1 钉选并回写 lock.builtFrom.ndk，现为 `TBD`） |
| **git configure 路线** | 优先 `make configure && ./configure --host=aarch64-linux-android`（需 autoconf），失败回退 `config.mak` 直写（Termux 同款 🔶） | Android 缺项以 `NO_TCLTK/NO_GETTEXT/NO_ICONV/NO_REGEX/NO_PERL/NO_PYTHON` 关闭 | D3 fetch 不改源；不引入补丁 | ⬜ 规划（M1-T3 首轮试编拍板） |
| **CA bundle** | cURL 来源 `cacert.pem`，钉版 + sha256 → assets；运行期 env 注入（`GIT_SSL_CAINFO` / `SSL_CERT_FILE`） | TLS 根证书 | D6：filesDir 布局构建期不可知，**不写死构建期路径** | ⬜ 规划（M1-T4） |
| **helper 分发** | helper 物理件以 `lib*.so` 随 jniLibs + `filesDir/gitexec` **symlink 符号链接农场** + `GIT_EXEC_PATH` 指向农场 | https remote helper 与本地 dashed 子进程（`git-upload-pack` 等）按原名可查 | D5：SELinux exec 检查解引用到目标文件标签放行（🔶 工作区 §4.3 同款，本域 ⬜ P5 未验证）；物理件只能落 nativeLibraryDir（C1） | ⬜ **规划（M1-T3/T4 + M2-T1）**；本仓 M0 无任何 helper 实现 |
| **assets 物化** | `assets/git-bridge-tools/`（templates + cacert.pem + gitexec-manifest.json + manifest.json 逐文件 sha256）→ 消费方幂等物化 | 随包纯数据 | D6 + 规划 §5.1/§5.3；物化复用 bridge payload 纪律 | ⬜ 规划（M1 收集 / M2 物化） |
| **发布模式** | **两段式**：GitHub Release 先行（M1-T6，tag `v<gitver>`；归档含四源 tarball + 构建脚本，D7/C7）→ Maven Central 随后（M3，runbook [`../../docs/发布到maven-central.md`](../../docs/发布到maven-central.md)） | 分发 | 与 aosp-node-pty 同款；`publish.gradle.kts` 管线已内置 | ✅ 管线已实现 / ⬜ 两段发布动作未发生（`RELEASE=false`） |
| **CI** | 配置期门禁（Gradle 配置 + provision 退出码纪律 + 语法门）→ M1 替换为真实流水线（fetch 四源 → 静态构建 → make → strip → provision → 归档 → Release） | 质量门禁 | M0 先保证「无 .so 也必须可配置」（FR-000-005） | ✅ 配置期 CI 已实现 / ⬜ 真实流水线 M1-T6 |
| **许可** | 本仓 MIT（`LICENSE`）；git 本体 **GPLv2**（含 helper）→ **Release 归档随附对应源码**（四源 tarball + 构建脚本）；zlib/curl/OpenSSL 各随其许可 | 合规交付物 | C7/D7：仅给上游链接不视为义务履行 | ✅ NOTICES 已登记 / ⬜ 归档与措辞定稿 M1-T6（R5） |
| **host 侧工具链语言** | Node ≥18（内置 fetch 备 M1 下载用）；bash（build 脚本）；Node 本机实测 v24.7.0 | 脚本 | 零第三方 npm 依赖 | ✅ |

---

## 2. 被**否掉**的选型及替代方案（规划 §D1–D7 反面 / §5.2 候选）

| 被否对象 | 否掉理由 | 替代方案（现状） |
|---|---|---|
| **动态 zlib/curl/openssl `.so` 随包 + `LD_LIBRARY_PATH`** | 多文件多门禁、版本漂移；exec 子进程走默认 linker namespace，本就看不到 App 库目录（D2 反面） | 四源**全静态链入** ⬜ M1 |
| **源码补丁 / 第三方 fork** | fetch 不改源纪律（C1/D3）；bionic 缺项用 git 自带 compat 补 | `NO_*` 配置关闭 + curl `--without-*` ⬜ M1 |
| **版本与 node 系配对** | 无 `NODE_MODULE_VERSION` 约束（D4 反面）；git 版本节奏独立 | CLI_VERSION = git 上游独立 semver ✅ |
| **`useLegacyPackaging=false`** | 库从 APK mmap 不落盘 → `execve` ENOENT（D1 反面；与 pty dlopen 库口径**相反**） | `useLegacyPackaging=true` ✅ |
| **helper 拷贝物化进 filesDir** | C1 封死：app_data_file 不可 exec（§5.2 候选 b） | symlink 农场 ⬜ M2（SELinux 放行 ⬜ P5） |
| **运行期下载 helper** | C2 红线 + Play 政策（§5.2 候选 c） | 全部随 APK 预置 |
| **`GIT_EXEC_PATH` 直指 nativeLibraryDir** | git 按名字 `git-remote-https` 查找，目录内是 `lib*.so` 名，不匹配；且该目录应用不可写（§5.2 候选 d） | 农场提供原名 symlink ⬜ M2 |
| **isomorphic-git 等进程内替代** | 工作区 §3.3 已否决：协议覆盖不全、无命令形态（§5.2 候选 e） | 真 `git` exec 进程 |
| **ssh 远程随包** | 需另带 openssh/dropbear，二期再议（规划 §1.3/§7.2） | ssh 远程如实登记不可用 |

---

## 3. 版本矩阵与兼容口径

| 维度 | 值 | 来源 |
|---|---|---|
| Maven 坐标 | `io.github.fellow99:git-cli:2.51.0`（**draft**） | `git-cli.lock.json:31-33` + `gradle.properties:7` ✅ |
| 版本语义 | = git 上游版本，独立 semver，无配对 | 规划 §2 / D4 ✅（口径） |
| draft 钉选 | 2.51.0 为**计划值**；M1 开工时以 CI 实际可构建的最新稳定版钉选并回写（README 同口径） | 规划 §2 ⬜ |
| minSdk / compileSdk | 24 / 36 | `git-cli/build.gradle.kts:30,32` ✅ |
| 交叉编译 API | 24（lock `androidApi`；build 脚本 `--api` 默认 24） | `git-cli.lock.json:11` + `scripts/build-git-cli-android.sh:30` ✅ |
| ABI | arm64-v8a（唯一） | `git-cli/build.gradle.kts:34` ✅ |
| Gradle / AGP / 发布插件 / JDK | 9.4.1 / 9.2.1 / 0.37.0 / 21 | 各配置文件 ✅ |
| NDK | TBD（M1 钉选；与 aosp-node-runtime 对齐线） | `git-cli.lock.json:19` ⬜ |
| DT_NEEDED 白名单 | libc.so / libm.so / libdl.so / libz.so / liblog.so（`libz.so` 为防御性允许，M1 复核 ⬜） | `git-cli.lock.json:43-49` ✅ |

---

## 4. 依赖清单

| 依赖 | 谁提供 | 何时需要 | 缺失后果 | 状态 |
|---|---|---|---|---|
| Node ≥18（本机 24.7.0） | 开发机 | provision / fetch / CI 语法门 | 门禁与 CI 跑不了 | ✅ |
| JDK 21 + Gradle 9.4.1 + AGP 9.2.1 | 开发机 / CI | 任何 Gradle 求值 | 配置期即失败（CLI_VERSION 缺失同样 error） | ✅ |
| Android NDK | runner | M1 交叉编译 | 无 libgit_cli.so | ⬜ M1 |
| zlib / libcurl / OpenSSL / git 官方源码包 + cacert.pem | 上游（fetch 钉版 + sha256） | M1 构建 | 无产物 | ⬜ M1 |
| autoconf / make / gcc / curl / file / tar / xz / ccache | runner（ubuntu-24.04） | M1 真实流水线 | configure/make 失败 | ⬜ M1 |
| Central Portal Token / GPG | **用户级** `~/.gradle/gradle.properties` | 仅发布（`RELEASE=true`） | sign/publish 任务保持禁用（防误发） | ✅ 门禁 |

> **零第三方 npm 依赖** ✅：`tools/` 与 `scripts/` 只用 Node 内置模块；Gradle 侧无 application 依赖（模块零源码）。

---

## 5. 选型层面的未决 / 风险（⚠️ / ⬜，规划 §11 全表为本）

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| 1 | helper 实际产物清单/别名形态 ⬜（R1，高） | §5.2 为候选表 | M1-T3 以 make 实产为准回写；最小集 `git-remote-http`(+别名) 必随包 |
| 2 | symlink 农场 SELinux 放行 ⬜（R2，高） | 🔶 工作区 §4.3 断言，本域未实证 | M2-T1 P5 真机先行；若被拒升级评审（影响五线农场） |
| 3 | git 上游无官方 Android/NDK 支持（🔶 Termux 社区先例） | NO_*/config 注入回答，M1-T3 试编 | 失败退路 R7/R8 |
| 4 | OpenSSL `android-arm64` × NDK 兼容 ⬜（R7）/ curl 依赖裁剪 ⬜（R8）/ zlib CHOST ⬜（R9） | 全部 M1 首轮试编 | 缺库一律 `--without-*`；https 失败则首版功能受限**如实上报** |
| 5 | 体积超标 ⬜（R6：静态 curl/openssl 后 >10MB） | 估 2–5MB + 5–8MB 增量（🔶 工作区估） | 首产实测回填 lock；超标先裁 http-fetch/push/imap |
| 6 | GPLv2 措辞定稿 ⬜（R5） | NOTICES 已登记义务 | M1-T6 Release 前定稿（AAR/NOTICES/Maven sources jar） |
| 7 | compat/regex 性能 ⬜（R3）/ 无 iconv 中文路径 ⬜（R4）/ 16KB 全链 ⬜（R10）/ 钩子跳过行为 ⬜（R11） | 记录性风险 | P2/P7 真机事实化 |
| 8 | lock `gates` 在 draft 即全 `true` 且无工具读取 | ⚠️ 语义未定（STRUCTURE §5-4） | [NEEDS CLARIFICATION] 登记于 `000-scaffold/plan.md` §7；M1 回写哈希时一并明确 |

---

## 6. 关键技术口径（实现必须对齐的硬数据）

### 6.1 七项 exec 门禁（`tools/provision.mjs:146-167`，任一不过 = 拒绝投放，exit 2）

| # | 判据 | 行号 | draft 行为 |
|---|---|---|---|
| ① | `e_type == ET_DYN`(3) | `provision.mjs:146` | 判死 |
| ② | PT_INTERP 恰 1 个且内容 = `/system/bin/linker64` | `:148-150` | 判死（与 dlopen 门禁相反） |
| ③ | `e_machine == 183`(AArch64) | `:151` | 判死 |
| ④ | DT_NEEDED ⊆ lock `matrix.allowedNeeded` | `:153-155` | 判死 |
| ⑤ | SHA-256 与锁一致 | `:156-157` | **只记录不比对**（draft 无锁值） |
| ⑥ | 大小与锁一致 | `:158-159` | **只记录不比对** |
| ⑦ | min LOAD align ≥ 0x4000（16KB） | `:160` | 判死；`--allow-page-align-4k` 仅 bring-up 放行并 ⚠（`:162-167`） |

### 6.2 退出码契约（C4/FR-000-030 族；✅ 本机复核 2026-11-02）

| 退出码 | 语义 | 实测 |
|---|---|---|
| `0` | 门禁全过（--check 含 jniLibs 兄弟文件白名单过） | —（M0 无产物，未出现 0 路径 ⬜） |
| `2` | 门禁不合格 / **未投放** / SCAFFOLD 未实现（fetch/build 骨架） | ✅ `--check`→2；`fetch --git 2.51.0`→2；`build`（参数齐）→2 |
| `1` | 用法/IO 错误（如 `--out` 缺 `--from`、lock 缺 release、非 ELF） | ✅ `--out foo`（缺 --from）→1 |

### 6.3 命令速查（与 README「如何构建」同口径）

```bash
node tools/provision.mjs --check                                                  # 校验已投放产物（未投放=exit 2）
node tools/provision.mjs --inspect <libgit_cli.so>                                # 对任意文件跑 7 门禁
node tools/provision.mjs --out git-cli/src/main/jniLibs --from build/out/libgit_cli.so   # 门禁过后幂等投放（M1）
node scripts/fetch-git-cli-source.mjs --git 2.51.0 --out .dist/src                # M1：四源钉选下载
bash scripts/build-git-cli-android.sh --git 2.51.0 --api 24 --src .dist/src/git \
  --deps .dist/src --ndk "$ANDROID_NDK_HOME" --out build/out                      # M1：交叉编译
gradle :git-cli:tasks                                                             # 配置期门禁（无 .so 必须过）
gradle :git-cli:assembleDebug -PCLI_VERSION=2.51.0                                # AAR 容器产出
```
