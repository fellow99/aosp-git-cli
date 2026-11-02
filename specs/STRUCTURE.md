# STRUCTURE.md —— `aosp-git-cli` 目录与文件结构（as-built）

> **性质**：项目级结构规格（现状快照 + 规划落点）。只描述「文件在哪、干什么、进不进 git/包」。
> **依据**：[`constitution.md`](./constitution.md)（C1–C8）· [`../docs/000-工程规划.md`](../docs/000-工程规划.md)（唯一规划基线，下称「规划 §」）· 本仓库实际文件清单 ✅实测（2026-11-02）。
> **标记**：✅实测（本仓库可复核）/ 🔶沿用（外部一手记录）/ ⬜未实测 / ⚠️冲突或风险。
> **版本**：v1.0 · 2026-11-02 · 状态：M0 骨架已完成（git 本体尚未构建，M1 接入真实交叉编译）。
>
> **一句话边界**：本仓**唯一产品**是 AAR 内的 exec 型原生件（`libgit_cli.so` + helper 集合 ⬜M1）与随包数据
> （assets ⬜M1）；Gradle 骨架、门禁工具、lock、CI 全是**配套物**。本仓不含任何嵌入 API。

---

## 1. 顶层目录树（逐文件一行用途，行数 ✅实测）

```
aosp-git-cli/                            # node-bridge-workspace 的子目录；Maven 坐标 io.github.fellow99:git-cli
├── .github/workflows/
│   └── build-git-cli-android.yml        # ✅ 50 行；配置期 CI（M0）：Gradle 配置门禁 + provision 退出码自检 + 语法门；M1 替换为真实流水线
├── .gitignore                           # ✅ 31 行；jniLibs/**/*.so 与 assets/** 不入库（C3）；.dist/、build/out/ 工作区
├── LICENSE                              # ✅ 21 行；MIT（本仓自身代码；git 本体 GPLv2 另计，C7）
├── README.md                            # ✅ 72 行；英文总览（定位/版本口径/exec 打包要点/如何构建/锁定与校验/许可）
├── README_zh.md                         # ✅ 67 行；中文总览（与 README.md 同构）
├── docs/
│   └── 000-工程规划.md                   # ★ 379 行；唯一规划基线（v2.0；D1–D7 决策、M1/M2 实现设计、探针 P1–P7、风险 R1–R11）
├── git-cli.lock.json                    # ★ 53 行；唯一事实源（C2）：active 2.51.0/arm64-v8a · releases[0] draft · matrix（allowedNeeded/execPackaging）
├── settings.gradle.kts                  # ✅ 21 行；rootProject.name=aosp-git-cli；仅 include(":git-cli")；vanniktech 0.37.0 pluginManagement
├── gradle.properties                    # ✅ 19 行；CLI_VERSION=2.51.0（draft）；RELEASE=false；GROUP/POM_* 公共元数据
├── gradle.properties.local.example      # ✅ 8 行；用户级凭据模板（Central Portal Token / GPG），真值文件不入库（C5）
├── gradle/libs.versions.toml            # ✅ 5 行；AGP 9.2.1（唯一 version 条目）
├── publish.gradle.kts                   # ✅ 139 行；发布面共享配置（coordinates/Central Portal/签名/singleVariant/SCM 补丁/RELEASE 门禁）
├── tools/
│   └── provision.mjs                    # ✅ 276 行；exec 型 ELF 门禁 + 幂等投放（纯 Node，零第三方依赖；退出码 0/2/1）
├── scripts/
│   ├── fetch-git-cli-source.mjs         # ✅ 54 行；骨架：只固化接口与纪律，下载/校验逻辑 M1 落地（现 exit 2=SCAFFOLD）
│   └── build-git-cli-android.sh         # ✅ 60 行；骨架：固化 NO_*/静态链入/16KB 纪律与 CLI 接口（现 exit 2=SCAFFOLD）
├── git-cli/                             # ★ AAR 容器模块（无任何 Kotlin/Java 源、无 src/ 树）
│   ├── build.gradle.kts                 # ✅ 45 行；namespace org.fellow99.gitcli · minSdk 24 · compileSdk 36 · abiFilters arm64-v8a · useLegacyPackaging=true
│   ├── THIRD-PARTY-NOTICES.md           # ✅ 19 行；git GPLv2 / zlib / curl / OpenSSL / CA bundle + GPLv2 对应源码义务（C7）
│   └── build/                           # ⚠️ 本地构建产物（不入库）：outputs/aar/git-cli-debug.aar（786 B 空容器，2026-11-02）
└── specs/                               # 本目录（规格体系，对齐规划 § 号）
    ├── constitution.md                  # 治理原则 C1–C8 + 证据纪律 + 评审清单 + 变更流程
    ├── STRUCTURE.md · TECH.md · ARCHITECTURE.md
    ├── overall-spec.md · overall-plan.md · overall-test-cases.md
    ├── 000-scaffold/                    # 模块级：spec.md（既有）· tasks.md（既有）· test-cases.md（既有）· plan.md（本批新增）
    ├── SPECS_CHECKLIST.md               # 逐文档状态表
    └── README.md                        # 索引（最后生成，链接全验）
```

### 1.1 刻意不存在的东西（防误引用）

| 路径/形态 | 现状 | 说明 |
|---|---|---|
| `git-cli/src/`（整棵树） | ✅ 不存在 | 模块是纯 AAR 容器：无 Kotlin/Java 源、无 `AndroidManifest.xml` 源文件（AAR 内 manifest 由 AGP 从 namespace 合成，✅ 实测 debug AAR 内 `package="org.fellow99.gitcli"` + `minSdkVersion 24`）、无 res |
| `git-cli/src/main/jniLibs/arm64-v8a/libgit_cli.so` | ⬜ 不存在 | provision `--out` 的投放落点；`.gitignore:23` 不入库；M1 首产后出现 |
| `git-cli/src/main/assets/**` | ⬜ 不存在 | M1 起收 templates/cacert.pem/gitexec-manifest.json（规划 §5.1）；`.gitignore:24` 不入库 |
| `git-cli/src/main/resources/META-INF/git-cli.properties` | ⬜ 未产生 | provision 投放成功后生成（`provision.mjs:252-267`，as-coded）；M0 无真实产物可投放，该路径未走通 ⬜ |
| helper 物理件（`libgit_remote_curl.so` 等） | ⬜ 规划未建 | M1-T3 以 make 实产为准探明（规划 §5.2，R1）；命名 `libgit_<名>.so` 映射 |
| `gradlew` / `gradle/wrapper/` | 不存在 | 仓库不含 Gradle Wrapper；CI 用 `gradle/actions/setup-gradle@v4` 固定 **9.4.1**（workflow:29-32）；本地开发须自备同版本 |
| `.dist/src/`、`build/out/` | ⬜ 不存在 | fetch/build 的工作区落点（M1）；`.gitignore:27-28` |

---

## 2. 关键配置文件位置与内容锚点

| 文件 | 层级 | 关键内容（现状 ✅实测） | 规划锚点 |
|---|---|---|---|
| `settings.gradle.kts` | 工程 | `rootProject.name = "aosp-git-cli"`（:20）；`include(":git-cli")`（:21）；pluginManagement 加载 `com.vanniktech.maven.publish.base` **0.37.0**（:3）；`FAIL_ON_PROJECT_REPOS`（:13） | §2 |
| `gradle/libs.versions.toml` | 工程 | `agp = "9.2.1"`（:2）；唯一插件别名 `android-library`（:5） | — |
| `gradle.properties` | 工程 | `CLI_VERSION=2.51.0`（:7，draft 计划版本）；`RELEASE=false`（:19）；`GROUP/POM_NAME/POM_DESCRIPTION/POM_URL/POM_LICENCE/POM_SCM/POM_DEVELOPER`（:2-16）；⚠️ `VERSION_NAME=0.1.0`（:3）为本仓**无读取方**的模板残留（见 §5） | §2/§10.1 |
| `git-cli/build.gradle.kts` | 模块 | `version` 强制取 `CLI_VERSION` 属性，缺失即 error（:16-17）；afterEvaluate 反射覆写 publication version（:19-26）；`namespace`（:29）/`compileSdk = 36`（:30）/`minSdk = 24`（:32）/`abiFilters += "arm64-v8a"`（:34）；`packaging.jniLibs.useLegacyPackaging = true`（:42） | §D1/§D4 |
| `publish.gradle.kts` | 发布 | coordinates `io.github.fellow99` + `project.name` + `CLI_VERSION`（:36-39）；`publishToMavenCentral(false, NONE)`（:42-56，`AUTOMATIC_RELEASE=true` 才 PUBLISHED）；`signAllPublications`（:57）；singleVariant `release + SourcesJar`（:58-69）；GPG 凭据仅用户级（:75-113）；POM `<scm><url>` 补丁（:115-131）；`RELEASE=true && Token 齐` 才启用 sign/publish 任务（:133-139） | §10.1/§12 |
| `git-cli.lock.json` | 事实源 | `active{2.51.0, arm64-v8a}`；`releases[0]`：`androidApi:24`、`name:libgit_cli.so`、`size:0`、`sha256:""`、`status:"draft"`、`mavenCentral.published:false`；`builtFrom.deps` 为**文本描述**（版本表 M1-T1 升级 ⬜）；`matrix.allowedNeeded` 5 项（libc/libm/libdl/libz/liblog）+ `execPackaging` 说明 | §8 |
| `.gitignore` | 仓库 | 构建产物（:1-15）+ 密钥材料（:17-20）+ **`git-cli/src/main/jniLibs/**/*.so`、`git-cli/src/main/assets/**`**（:22-24）+ `.dist/`、`build/out/`（:26-28） | C3 |
| `.github/workflows/build-git-cli-android.yml` | CI | 触发 push(main)/PR/dispatch（:7-11）；`permissions: contents: read`（:13-14）；JDK 21 temurin（:23-27）；Gradle **9.4.1**（:29-32）；`gradle :git-cli:tasks`（:35，无 .so 必须可配置）；`node tools/provision.mjs --check` 退出码必须 **= 2**（:37-45，⚠️ `bash -e` 下断言分支不可达，见 plan.md §7 缺陷登记）；`node --check` ×2 + `bash -n`（:47-50） | FR-000-040~042 |

---

## 3. 构建产物落点（as-built）

| 产物 | 落点 | 现状 | 说明 |
|---|---|---|---|
| debug AAR（空容器） | `git-cli/build/outputs/aar/git-cli-debug.aar` | ✅ **786 B**（2026-11-02 本地 `assembleDebug`） | ✅实测内容 4 条目：`R.txt`(0 B) · `AndroidManifest.xml`(206 B，合成) · `classes.jar`(22 B，**空**) · `aar-metadata.properties`(157 B，`minCompileSdk=36`)——证明「AAR 容器、零源码」 |
| `libgit_cli.so`（exec 型 PIE） | `git-cli/src/main/jniLibs/arm64-v8a/` | ⬜ M1 | 由 M1 交叉编译产出 → provision `--out` 投放（先过 7 门禁）；release AAR 的 `jni/` 目录即物理件 |
| helper 物理件 `libgit_*.so` | 同上 | ⬜ M1-T3 探明清单 | 规划 §5.2 候选表；白名单与 manifest 校验 M1-T5 落地 |
| assets 树（templates/cacert.pem/gitexec-manifest.json/manifest.json） | `git-cli/src/main/assets/git-bridge-tools/` | ⬜ M1 | 纯数据纪律：assets 内不得出现 `.so`/可执行位文件（规划 §5.3） |
| 发布归档 | GitHub Release `git-cli-v<ver>-android-arm64-v8a.tar.gz` + `.sha256` | ⬜ M1-T6 | 含 lib*.so 集 + assets + 元数据 + LICENSES + **四源 tarball 与构建脚本（C7/D7）** |
| Maven Central 制品 | `io.github.fellow99:git-cli:<CLI_VERSION>` | ⬜ M3 | `RELEASE=true` + 用户级凭据才可发布（C5） |
| `META-INF/git-cli.properties` | AAR resources | ⬜ 未产生 | provision 投放成功后写入 `tool.version/abi/name/size/sha256/provisionedAt`（`provision.mjs:255-266`） |

---

## 4. 目录 ↔ 能力 ↔ FR 映射（`specs/000-scaffold/spec.md`）

| 目录 / 文件 | 能力 | FR 族 | 现状 |
|---|---|---|---|
| `settings.gradle.kts` | 工程骨架（rootName、单模块） | FR-000-001 | ✅ |
| `git-cli/build.gradle.kts` | AAR 容器 + exec 打包 | FR-000-002 / FR-000-004 | ✅ |
| `gradle.properties` + `publish.gradle.kts` + `gradle.properties.local.example` | 版本纪律（CLI_VERSION 独立 semver）+ 发布面 | FR-000-003 | ✅ |
| `git-cli.lock.json` | 唯一事实源（draft 诚实） | FR-000-010~013 | ✅（draft 纪律）；deps 版本表 ⬜ M1-T1 |
| `tools/provision.mjs` | exec 门禁 + 幂等投放 + libnode.so 禁入 | FR-000-030~036 | ✅（单文件白名单口径）；helper 白名单/manifest 校验 ⬜ M1-T5 |
| `scripts/fetch-git-cli-source.mjs` · `scripts/build-git-cli-android.sh` | 构建输入接口（纪律已固化，逻辑 M1） | —（规划 §4.2） | ✅ 接口 / ⬜ 实现 |
| `.github/workflows/build-git-cli-android.yml` | 配置期门禁 | FR-000-040~042 | ✅（M0）；真实流水线 ⬜ M1-T6 |

---

## 5. ⚠️ 结构层面发现的事实性问题（评审必读）

| # | 发现 | 证据 | 影响/处置 |
|---|---|---|---|
| 1 | `gradle.properties:3` 的 `VERSION_NAME=0.1.0` **无任何读取方**：发布坐标 version 唯一取 `CLI_VERSION`（`git-cli/build.gradle.kts:16-17`、`publish.gradle.kts:37-39`） | 全仓 grep `VERSION_NAME` 仅 1 处命中（定义处） | 模板残留，易误读为「库版本 0.1.0」；建议 M1 清理或改为注释 |
| 2 | `provision.mjs:196,263` 的 `pairedRuntime?.coordinates` 是 **pty 线继承的残留字段**：本仓 lock 无 `pairedRuntime`，永远输出「无配对信息」/不写 `paired.runtime` 行 | `git-cli.lock.json` 无该字段 | 无害但不属于本仓口径（C2：与 node 系无配对）；建议 M1 清理 |
| 3 | `provision.mjs:184` 的 allowedNeeded **兜底默认缺 `liblog.so`**（兜底 4 项：libc/libm/libdl/libz；lock `matrix.allowedNeeded` 是 5 项） | `provision.mjs:184` vs `git-cli.lock.json:43-49` | 仅当 lock 缺 matrix 时触发，当前不生效；兜底与 lock 漂移点，建议对齐 |
| 4 | `git-cli.lock.json:22-30` 的 `gates` 七项在 **draft（size=0/sha256 空）即全 `true`**，且**无任何工具读取** gates（provision 每次重新解析产物，不读存档） | `provision.mjs` 全文无 `gates` 读取 | 语义未定：是「门禁 profile 定义」还是「结论存档」？已登记为 `000-scaffold/plan.md` §7 的 [NEEDS CLARIFICATION]；M1 回写哈希时应一并明确 |

---

## 6. 「不入库」清单（C3 + 发布卫生）

| 对象 | 位置 | 机制 | 依据 |
|---|---|---|---|
| `libgit_cli.so` + helper 集 | `git-cli/src/main/jniLibs/**/*.so` | `.gitignore:23`；只进 AAR | C3 · 规划 §8 |
| assets 随包树 | `git-cli/src/main/assets/**` | `.gitignore:24`；只进 AAR | C3 |
| 工作区 `.dist/`、`build/out/` | 仓库根 | `.gitignore:27-28` | C1/C3 |
| Gradle/IDE 本地产物 | `.gradle/`、`build/`、`.kotlin/`、`.idea/` 等 | `.gitignore:1-15` | — |
| 密钥材料 | `*.jks`、`*.keystore`、`google-services.json` + 用户级 gradle.properties | `.gitignore:17-20` + `gradle.properties.local.example` 模板 | C5 |
| debug/release AAR 本体 | `git-cli/build/outputs/aar/` | `.gitignore:3`（`build/`） | — |
