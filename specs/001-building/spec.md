# 001 · 构建（building）功能规格

> 模块：001-building · 状态：⬜ 规划已立项（规划 §10.2）· 所属工程：aosp-git-cli
> 规划基线：[`docs/000-工程规划.md`](../../docs/000-工程规划.md) §4（构建设计）/§5（制品形态）/§8（lock）
> 覆盖任务：M1-T1（fetch 五输入钉选）/ M1-T2（依赖静态构建）/ M1-T3（git 试编 + helper 探明）/ M1-T4（strip/命名/assets 收集）

## 1. 目的

把官方四源（git / zlib / OpenSSL / curl）+ CA bundle 变成**过 exec 门禁的 Android arm64 制品集**：
`libgit_cli.so`（exec 型 PIE，静态依赖，16KB 对齐）+ helper 全集（`libgit_*.so`）+ 随包纯数据
（templates / cacert.pem / gitexec-manifest.json）。全流程**可复现、不改源、出处钉选**。

## 2. 功能需求（FR-001-xxx，RFC 2119；判据可证伪）

### 2.1 源钉选与获取（fetch，M1-T1）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-001-001 | MUST | 五输入（git/zlib/openssl/curl/cacert）各自独立钉版：官方 URL + 版本 + SHA-256 内置于 fetch 脚本的钉选表 | 钉选表五条齐全；改任一字节 ⇒ 校验失败（exit 2） |
| FR-001-002 | MUST | 下载只走官方出处，不改源（C1）：解压后源码树与官方包逐字节一致（无补丁/无 fork） | fetch 后对任一源跑 `sha256` 与官方包一致；仓库与 `.dist/` 无补丁文件 |
| FR-001-003 | MUST | fetch 幂等：已就位且哈希正确的输入跳过下载；损坏/缺文件自动重下 | 二次执行不重新下载（有跳过日志）；构造损坏文件 ⇒ 自动修复 |
| FR-001-004 | MUST | 输出布局固定：`.dist/src/<name>/`（git/zlib/openssl/curl 四源码树 + cacert.pem），可整目录删除重建 | 删除 `.dist/src` 后重跑，产物布局一致 |
| FR-001-005 | MUST | 钉选版本表回写 lock（`builtFrom.deps` 升级为版本表结构，规划 §8） | fetch 成功后打印与 lock 一致的版本表；lock 字段类型校验通过 |
| FR-001-006 | MUST NOT | 不得引入钉选表之外的任何源码/镜像/预编译二进制 | 钉选表外的下载请求 ⇒ 拒绝（exit 2） |

### 2.2 静态依赖构建（M1-T2；顺序 zlib → openssl → curl，规划 §4.1）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-001-010 | MUST | zlib 以 Android 交叉目标静态构建，产物 `libz.a`（无 `.so`） | 构建目录存在 `libz.a` 且无 `libz.so` |
| FR-001-011 | MUST | OpenSSL 以 `android-arm64`（no-shared/no-tests）静态构建，产物 `libssl.a` + `libcrypto.a` | 两个 `.a` 存在；`libssl.so`/`libcrypto.so` 不存在 |
| FR-001-012 | MUST | curl 交叉静态构建：`--disable-shared --enable-static --with-openssl --with-zlib`；缺库一律 `--without-*` 关闭（psl/brotli/zstd/idn2 等），不引入新源（C1） | `libcurl.a` 存在；configure 日志无新增第三方库启用 |
| FR-001-013 | MUST | 三依赖的 include/lib 路径以参数注入 git 构建，不污染系统目录 | git 链接命令行可见注入路径；系统无安装痕迹 |
| FR-001-014 | SHOULD | 依赖构建产物可缓存复跑（重跑只重建变更项） | 未变更输入时二次执行命中缓存（跳过日志） |

### 2.3 git 交叉编译（M1-T3；config.mak/configure 双路线，规划 §4.2）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-001-020 | MUST | git 以 Android NDK 交叉编译（AArch64、API 24），缺项以 `NO_*` 关闭：NO_TCLTK / NO_GETTEXT / NO_ICONV / NO_REGEX / NO_PERL / NO_PYTHON | 构建日志含全部 NO_* 注入；产物不依赖 tcl/perl/gettext |
| FR-001-021 | MUST | zlib/curl/openssl **静态链入**主二进制与 helper（DT_NEEDED 只剩系统库白名单） | `provision --inspect` 门禁④过（NEEDED ⊆ 白名单） |
| FR-001-022 | MUST | 链接参数 `-Wl,-z,max-page-size=16384`（16KB 页设备） | 门禁⑦过（min LOAD align ≥ 0x4000） |
| FR-001-023 | MUST | 主产物为 exec 型 PIE 且 interp=`/system/bin/linker64` | 门禁①②③过 |
| FR-001-024 | MUST | **helper 实产清单探明**：以 make 实际产物为准枚举 helper 集（remote-curl 及别名、dashed 子进程入口等），回写规划 §5.2 与 lock（R1 出口） | 探明报告落盘（BUILD-METADATA）；lock/规划与实产一致 |
| FR-001-025 | MUST | configure 优先 `make configure` 路线，失败自动回退 `config.mak` 直写（Termux 同款）；路线选择记录于构建日志 | 日志含路线选择与回退原因（如有） |
| FR-001-026 | SHOULD | 构建可中断续跑（分阶段产物落盘） | 阶段产物存在时跳过该阶段 |

### 2.4 产物整理与随包数据收集（M1-T4）

| 编号 | 级别 | 需求 | 可证伪的验收判据 |
|---|---|---|---|
| FR-001-030 | MUST | 全部可执行产物 `llvm-strip --strip-unneeded` | strip 前后体积对比记录于 BUILD-METADATA |
| FR-001-031 | MUST | 命名映射：主二进制 → `libgit_cli.so`；helper → `libgit_<名>.so`（Android 只认 `lib*.so`） | 产物目录全部文件名匹配 `libgit_*.so` |
| FR-001-032 | MUST | gitexec-manifest.json 生成：农场命令名 → 物理件文件名（含 dashed 子进程与 helper 别名，规划 §5.2 表为候选，以实产回写） | manifest JSON 可解析；条目与实产一一对应 |
| FR-001-033 | MUST | assets 收集：templates/（源码树模板）+ cacert.pem（钉选版）+ gitexec-manifest.json → 统一 assets 目录；**纯数据纪律**（无 `.so`、无可执行位） | assets 树内无 `.so`；全部文件无可执行位 |
| FR-001-034 | MUST | BUILD-METADATA.txt / FETCH-METADATA.json 落盘（版本、sha256、参数、路线、时间；镜像 pty 归档形态） | 两文件存在且字段齐备（版本/哈希/flags/NDK） |
| FR-001-035 | MUST | 体积实测回填（本体 + 依赖增量 + helper；R6 出口） | BUILD-METADATA 含逐产物 size；与 lock 回写一致 |

## 3. 边界（不在本模块）

- provision 门禁扩展/jniLibs 白名单/manifest 一致性校验 → **002-building-workflow**；
- CI 流水线与 Release → **002-building-workflow**；
- 产物在设备上的行为验证（探针/用例）→ **003-cli**；
- ssh/openssh、perl/tcl 子命令（宪法 C1/overall-spec §1.3 非目标）。

## 4. 验收场景

- 干净环境（空 `.dist/`、空构建目录）一条 fetch + 一条 build 命令产出：`libgit_cli.so` + helper 集
  + assets 三件（templates/cacert/manifest）+ 双 METADATA，主/辅产物全部过 `provision --inspect` 七门禁；
- 任一源包被篡改 1 字节 ⇒ fetch exit 2，绝不进入构建；
- 重复执行 fetch/build 幂等（缓存命中、产物一致）。
