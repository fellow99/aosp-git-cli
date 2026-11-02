# 001-building 测试用例

> 对应：[spec.md](./spec.md)（FR-001-xxx）。层：L1（host 门禁）/ L1.5（构建可复现）。
> 执行环境：Windows x86_64 Git Bash（本机）+ NDK r28c；CI 侧同套用例在 ubuntu-24.04 复跑（002 模块接管）。
> 判据纪律：每条可证伪；⬜ 项在实现完成后执行并回填记录。

| # | 用例 | 层 | 覆盖 FR | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|---|---|
| TC-001-01 | fetch 钉选下载 | L1.5 | 001-001/002/004 | 空 `.dist/` | `node scripts/fetch-git-cli-source.mjs --git 2.51.0 --out .dist/src` | exit 0；`.dist/src/{git,zlib,openssl,curl}/` + `cacert.pem` 齐全；FETCH-METADATA.json 五条 sha256 与 PINS 一致 | ⬜ |
| TC-001-02 | fetch 幂等 | L1.5 | 001-003 | TC-001-01 后 | 再跑一次同命令 | exit 0；日志含跳过下载；目录内容一致 | ⬜ |
| TC-001-03 | fetch 篡改负例 | L1.5 | 001-001/006 | 缓存存在 | 篡改 `.dist/dl/` 内任一包 1 字节后重跑 | exit 2（校验失败）；损坏缓存被删除；不进入解压 | ⬜ |
| TC-001-04 | 非钉选版本负例 | L1.5 | 001-006 | — | `--git 9.9.9` | exit 2（版本不在钉选表） | ⬜ |
| TC-001-05 | deps 版本表回写 | L1 | 001-005 | TC-001-01 | 核对 lock `builtFrom.deps`/`source` | zlib/openssl/curl/git 四条 {version,sha256} 与 PINS 逐字一致；JSON 可解析 | ⬜ |
| TC-001-06 | zlib 静态产物 | L1.5 | 001-010 | S1 后 | 检查构建目录 | `libz.a` 存在；`libz.so*` 不存在 | ⬜ |
| TC-001-07 | openssl 静态产物 | L1.5 | 001-011 | S2 后 | 同上 | `libssl.a`+`libcrypto.a` 存在；无对应 `.so` | ⬜ |
| TC-001-08 | curl 静态产物 | L1.5 | 001-012/013 | S3 后 | 同上 + configure 日志 | `libcurl.a` 存在；无 `.so`；日志无 psl/brotli/zstd/idn2 启用 | ⬜ |
| TC-001-09 | 主产物七门禁 | L1 | 001-020~023 | S5/S7 后 | `node tools/provision.mjs --inspect <out>/libgit_cli.so` | 七门禁全 ✔（①PIE ②interp=linker64 ③AArch64 ④NEEDED ⊆ 白名单 ⑤⑥记录 ⑦16KB） | ⬜ |
| TC-001-10 | helper 全集同门禁 | L1 | 001-021/023 | S7 后 | 对每个 `libgit_*.so` 跑 `--inspect` | 全部七门禁 ✔ | ⬜ |
| TC-001-11 | helper 清单探明 | L1.5 | 001-024 | S6 后 | 读 `helper-inventory.json` + 与规划 §5.2 对照 | 实产清单落盘；别名形态（hardlink/symlink）记录；含 `git-remote-http(s)` 最小集 | ⬜ |
| TC-001-12 | strip 与体积 | L1.5 | 001-030/035 | S7/S9 后 | 读 BUILD-METADATA | 每产物 strip 前/后 size 记录；总量 <10MB 预算（R6）或如实登记超标 | ⬜ |
| TC-001-13 | 命名映射 | L1 | 001-031 | S7 后 | `ls <out>/*.so` | 全部匹配 `libgit_*.so`；主件 `libgit_cli.so` 存在 | ⬜ |
| TC-001-14 | gitexec-manifest | L1 | 001-032 | S8 后 | 解析 manifest + 与 inventory 对照 | farm 条目 ⊆ 物理件集合；别名（git-remote-https 等）指向 `libgit_remote_curl.so` | ⬜ |
| TC-001-15 | assets 纯数据 | L1 | 001-033 | S8 后 | 扫描 assets 树 | 无 `.so`；所有文件无可执行位；templates/ 与 cacert.pem（sha256=钉选值）齐全 | ⬜ |
| TC-001-16 | METADATA 齐备 | L1.5 | 001-034 | S9 后 | 读双 METADATA | 版本/哈希/参数/NDK/路线/时间字段齐备 | ⬜ |
| TC-001-17 | 全链可复现 | L1.5 | 001-002 | 全链后 | 删 `build/out` 重跑 build（不删 `.dist`） | 产物 sha256 与首轮一致（含 helper） | ⬜ |
| TC-001-18 | 不改源纪律 | L1.5 | C1/001-002 | 全链后 | 重跑 fetch 校验 + `git status`（源树外无补丁产物） | 四源包 sha256 仍与 PINS 一致；仓库无源码补丁文件 | ⬜ |

## 执行记录

- ⬜ 首轮执行后回填（日期、环境、逐条结果、偏差说明）。
