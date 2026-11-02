# ARCHITECTURE.md —— `aosp-git-cli` 整体架构（as-built + 规划引用）

> **性质**：项目级架构规格。回答「分几层、制品怎么流、门禁卡在哪、运行期怎么被消费方用起来」。
> **依据**：[`constitution.md`](./constitution.md)（C1–C8）· [`../docs/000-工程规划.md`](../docs/000-工程规划.md)（唯一规划基线，下称「规划 §」）· 源码 ✅实测（2026-11-02）。
> **标记**：✅实测 / 🔶沿用 / ⬜未实测 / ⚠️冲突或风险。凡标「**⬜ 规划**」的层/组件，代码里**确实没有**（M1/M2 落地），只是规划引用（D5/§5.1/§7），不得当既成事实。
> **版本**：v1.0 · 2026-11-02 · 状态：M0 骨架已完成（层①② as-built）；层③④⑤ 全部 ⬜ 规划。

---

## ① 分层架构

```
┌─ 终端消费方（App 进程，node-pty 宿主）─────────────────────────────────────────┐
│ ⑤ 运行期环境引导层（消费方 bridge 载荷或 Kotlin；契约见规划 §7.1）⬜ 规划(M2)      │
│   - assets/git-bridge-tools/ 幂等物化 → filesDir                                │
│     （templates/ + cacert.pem + gitexec-manifest.json）                          │
│   - 依 gitexec-manifest.json 建 helper symlink 农场：                            │
│     filesDir/gitexec/git-remote-https → <nativeLibraryDir>/libgit_remote_curl.so │
│   - 注入 GIT_EXEC_PATH / GIT_TEMPLATE_DIR / GIT_CONFIG_GLOBAL /                  │
│     GIT_SSL_CAINFO / SSL_CERT_FILE / PATH / HOME / TMPDIR                        │
│        │ pty.spawn(<nativeLibraryDir>/libgit_cli.so, …)（forkpty → execve）      │
│        ▼                                                                         │
│ ③ git 子进程（exec 型，独立生命周期）⬜ 规划(M1 产物)：                            │
│   libgit_cli.so（PIE，静态 zlib/curl/openssl，16KB 对齐，interp=linker64）        │
│   https：git 按 GIT_EXEC_PATH exec 农场里的 git-remote-https（symlink→物理件）    │
│   本地：dashed 子进程 git-upload-pack / git-receive-pack 经农场（argv[0] 分发）   │
└──────────────────────────────────────────────────────────────────────────────────┘
        ▲ 随包供给（构建期已定，运行期零下载）                        门禁/事实源
┌───────┴────────────────────────────────────────────────────────┬────────────────┐
│ ④ 随包数据层：AAR assets/git-bridge-tools/ ⬜ 规划(M1 收集)      │ ② 供给门禁层    │
│   templates/（hooks 仅为样例，运行期不可 exec）                  │ ✅ as-built：   │
│   cacert.pem（钉版 + sha256）                                    │  git-cli.lock.  │
│   gitexec-manifest.json（命令名 → lib 文件名；农场建链依据）      │  json（唯一事实 │
│   manifest.json（逐文件 sha256 + 总 sha256）                     │  源）+          │
│ ③ exec 制品层：AAR jni/arm64-v8a/ ⬜ 规划(M1)：                  │  tools/provision│
│   libgit_cli.so + libgit_remote_curl.so（+⬜ http-fetch/push）   │  .mjs（7 门禁 + │
│   → 打包要求 useLegacyPackaging=true（D1）物理落盘               │  幂等投放 +     │
│ ① 构建与发布层 ✅ as-built：Gradle 9.4.1 / AGP 9.2.1 /           │  libnode.so 禁  │
│   vanniktech 0.37.0 / :git-cli AAR 容器 / publish.gradle.kts     │  入 / 退出码    │
│   两段式发布（GitHub Release → Maven Central，RELEASE=false 门） │  0/2/1）        │
└─────────────────────────────────────────────────────────────────┴────────────────┘
```

| 层 | 归属 | 进哪个发布物 | 现状 |
|---|---|---|---|
| ① 构建与发布层（Gradle 骨架、发布管线、发布卫生门禁） | 本仓 | 仓库（不入 AAR） | ✅ as-built |
| ② 供给门禁层（lock + provision exec 门禁 + jniLibs 白名单） | 本仓 | 仓库（不入 AAR） | ✅ as-built（helper 白名单扩展 ⬜ M1-T5） |
| ③ exec 制品层（libgit_cli.so + helper 集） | 本仓（M1 产出） | AAR `jni/arm64-v8a/` | ⬜ 规划（M1-T3/T4） |
| ④ 随包数据层（assets 纯数据 + manifest） | 本仓（M1 收集） | AAR `assets/` | ⬜ 规划（M1-T4） |
| ⑤ 运行期引导层（物化 + 农场 + env 注入） | **消费方**（本仓只定义契约，规划 §7.1） | 消费方 App | ⬜ 规划（M2-T1）；SELinux 农场放行 🔶 工作区断言 / ⬜ P5 |

**一条关键边界（C2/规划 §1.3）**：本仓**不运行期下载任何可执行物**；assets 物化的只是纯数据，农场只建名字映射 symlink，不产生新代码。

---

## ② 制品流（as-built 的真实链路 + 规划虚线）

```
官方源码包 ×4 + cacert.pem                                  git-cli.lock.json（唯一事实源）
  │  scripts/fetch-git-cli-source.mjs ⬜ M1（现 exit 2）        │ 版本/ABI/白名单/门禁存档
  │  钉版 + sha256，不改源（C1）                                 ▼
  ▼                                                    ┌─────────────────┐
scripts/build-git-cli-android.sh ⬜ M1（现 exit 2）      │ tools/provision │
  zlib → openssl → curl（全 .a）→ git（NO_* 配置）        │     .mjs ✅     │
  make → helper 清单探明 → llvm-strip → 16KB LDFLAGS     │ ①ELF 解析       │
  │                                                      │ ②7 门禁判定     │
  │  build/out/libgit_cli.so（+ helper 集 ⬜）            │ ③幂等投放       │
  └─────────── --from ─────────────────────────────────▶│ ④META-INF 写入  │
                                                          └────────┬────────┘
                                            门禁全过才落盘          ▼
                                  git-cli/src/main/jniLibs/arm64-v8a/*.so（不入库，C3）
                                                                   ▼
                                              gradle assemble/Release → AAR
                         （jni/ + assets/ + META-INF/git-cli.properties ⬜）
                                                                   ▼
                              GitHub Release 归档（含四源 tarball + 构建脚本，C7/D7）⬜ M1-T6
                                                                   ▼
                              Maven Central（RELEASE=true + 用户级凭据；lock 回写）⬜ M3
```

as-built 已发生的链路只有两条：**配置期**（`gradle :git-cli:tasks` / `assembleDebug` → 786 B 空 AAR ✅）
与**门禁自检**（`provision --check` → exit 2 未投放 ✅）。`--out` 投放链路 as-coded、未走通全链（⬜ 无真实产物）。

---

## ③ 门禁层（唯一 as-built 的「架构性」组件）

### 3.1 exec 型门禁 profile 与 dlopen 库门禁的三处相反/差异（`provision.mjs:9-16`）

| 维度 | 本仓（exec 型） | aosp-node-pty（dlopen 库） |
|---|---|---|
| PT_INTERP | **恰 1 个且 = `/system/bin/linker64`**（经系统动态链接器启动） | 必须为 0（PIE 产物 `dlopen` 必崩） |
| DT_NEEDED | **白名单制**：⊆ lock `matrix.allowedNeeded`（静态链入后只剩系统库） | 「必须含 libnode.so」 |
| NAPI | 无门禁（独立进程，不加载引擎） | 「napi_* 未定义引用」门禁 |
| 打包 | `useLegacyPackaging=true`（物理落盘） | `false`（mmap 不落盘） |

### 3.2 门禁与白名单的落点

| 门禁/纪律 | 判据 | 落点（✅实测） |
|---|---|---|
| ①–⑦ 七门禁 | 见 [`TECH.md`](./TECH.md) §6.1 | `provision.mjs:146-167` |
| draft 诚实 | 无锁值（sha/size）只记录不比对，打印 ⚠ | `:141-142,156-159,197` |
| jniLibs 单文件白名单 | 目录内 `.so` 只允许 `active.name`（当前= `libgit_cli.so`）；白名单外全部拒绝 | `:222-228` |
| `libnode.so` 禁入 | `BANNED_IN_AAR`，投放后存在即 throw（→ exit 1） | `:38,246-250` |
| 版本元数据 | 投放成功写 `git-cli/src/main/resources/META-INF/git-cli.properties` | `:252-267` |
| 退出码契约 | 0 全过 / 2 门禁不合格·未投放 / 1 用法·IO | `:205,216,228,237,275` |

**M1 扩展（规划引用，⬜）**：helper 全集过同一 exec profile（§6）；jniLibs 白名单扩展为 lock
`matrix.jniLibsWhitelist`（§5.3）；gitexec-manifest 一致性校验（引用 ⊆ 白名单、无孤儿）；assets 纯数据
校验（无 `.so`/可执行位，逐文件 sha256）。

---

## ④ 运行期契约（规划引用，⬜ M2；本仓只定义、不实现）

| 面 | 契约（规划 §7.1/§7.2） | 本仓供给 | 消费方职责 |
|---|---|---|---|
| 启动 | `pty.spawn(<nativeLibraryDir>/libgit_cli.so, …)` | exec 型物理件（D1 落盘） | 终端/PTY 装配 |
| helper 查找 | `GIT_EXEC_PATH=<filesDir>/gitexec`（symlink 农场，依 gitexec-manifest.json 建/重建，幂等） | manifest 清单 + 物理件 | 建农场、注入 env |
| TLS | `GIT_SSL_CAINFO` / `SSL_CERT_FILE` → 物化后的 cacert.pem | CA 随包（钉版） | 物化 + 注入 |
| 模板/配置 | `GIT_TEMPLATE_DIR` / `GIT_CONFIG_GLOBAL` / `HOME` / `TMPDIR` | templates 随包 | 物化 + 注入 |
| 已知限制 | ssh 远程不可用（二期）；perl/tcl/python 子命令不可用；仓库钩子视为无钩子；无 iconv/gettext；dumb-http/DAV push 随裁剪 ⬜ | 如实登记（NOTICES/README） | 文档写明 |

**已定义但未验证的运行期断言（全部 ⬜，规划 §7.3 探针 P1–P7）**：版本串回程、本地 clone 经农场、
https ls-remote/clone、农场 symlink 的 SELinux 放行（🔶 工作区 §4.3 同款）、CA 生效反证、16KB 页设备全链。

---

## ⑤ 关键架构决策（D1–D7，全部引自规划 §3.1；实现状态标注）

| # | 决策 | 理由 | 反面（禁止） | 状态 |
|---|---|---|---|---|
| D1 | exec 打包 `useLegacyPackaging=true` | 物理落盘 nativeLibraryDir，否则 `execve` ENOENT | `false`（pty dlopen 口径） | ✅ 已实现（`git-cli/build.gradle.kts:42`） |
| D2 | zlib/libcurl/OpenSSL 全静态链入 | DT_NEEDED 只剩系统库；产物单文件化 | 动态 `.so` + `LD_LIBRARY_PATH` | ⬜ M1 |
| D3 | 缺项以 NO_* 配置关闭，不打源码补丁 | fetch 不改源（C1）；bionic 缺项用自带 compat | fork / 补丁 | ⬜ M1（纪律已固化进脚本骨架 ✅） |
| D4 | 版本 = git 上游版本，独立 semver | 与 node 系无 ABI 约束 | 与 runtime/pty 配对 | ✅ 已实现（CLI_VERSION 管线） |
| D5 | helper `lib*.so` 随包 + filesDir/gitexec symlink 农场 + GIT_EXEC_PATH 指向农场 | 物理件只能落 nativeLibraryDir（C1）；git 按原名查找；SELinux 按目标标签放行（🔶⬜ P5） | 运行期下载 / 拷贝 filesDir / 直指 nativeLibraryDir | ⬜ 规划（M1-T3/T4 + M2-T1） |
| D6 | assets 只带纯数据，CA 经 env 注入 | filesDir 布局构建期不可知 | curl `--with-ca-bundle` 写死路径 | ⬜ M1 |
| D7 | GPLv2 对应源码随 Release 归档分发（四源 tarball + 构建脚本） | git GPLv2 对应源码义务（C7） | 仅给上游链接 | ⬜ M1-T6（NOTICES 已登记 ✅） |

---

## ⑥ 架构层面的已知缺口（里程碑归属）

| 缺口 | 归属 | 影响 |
|---|---|---|
| fetch/build 真实实现（四源钉选 + 交叉编译 + strip） | M1-T1/T2/T3 | 无任何 git 产物 |
| helper 产物清单探明 + `libgit_*.so` 命名 + assets 收集 | M1-T3/T4 | https/本地传输不可用 |
| provision 扩展：helper 同门禁 + jniLibs 白名单 + manifest 一致性 + assets 校验 | M1-T5 | 多文件门禁缺口 |
| CI 真实流水线 + Release（含 C7 归档）+ lock 回写 released | M1-T6 | 发布不闭环 |
| useLegacyPackaging true/false 对照 + exec 回程探针 | M1-T7 | 工作区探针 1/2 结论 ⬜ |
| 物化 + 农场 + env 注入（消费方）+ 真机 P1–P7 | M2 | 运行期契约未验证 |
| Maven Central 发布 | M3 | 公共坐标不可用 |
