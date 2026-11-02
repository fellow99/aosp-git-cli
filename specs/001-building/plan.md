# 001-building — 模块计划（plan.md，planned → 开发后回写 as-built）

> **模块**：001-building 构建 · **性质**：技术实现计划（本文件先写「怎么做」，实现落地后逐条回写 as-built 与行号）。
> **依据**：[`../constitution.md`](../constitution.md)（C1–C8）· [`../../docs/000-工程规划.md`](../../docs/000-工程规划.md)（唯一规划基线，下称「规划 §」）· 本模块 [`spec.md`](./spec.md)（FR-001-xxx）。
> **标记**：✅实测 / 🔶沿用 / ⬜未实测（规划）/ ⚠️风险。**本文所有构建参数在首轮试编前均为规划值（⬜），试编后回写。**
> **版本**：v1.0 · 2026-11-02 · 状态：⬜ 未实现（脚本骨架接口已固化于 000-scaffold）。

---

## 1. 技术上下文

### 1.1 运行环境（本机 as-built ✅ 2026-11-02）

| 项 | 值 | 说明 |
|---|---|---|
| 宿主 | Windows x86_64 + Git Bash（CI 为 ubuntu-24.04，脚本双环境兼容） | bash + node 驱动 |
| NDK | **r28c（28.2.13676358）**，安装于本机 SDK；`lock.builtFrom.ndk` 回写 | 与 aosp-node-runtime 对齐线（规划 §4.1） |
| 工具链 | `$TOOLCHAIN/bin/clang`（`--target=aarch64-linux-android24`）+ `llvm-ar/ranlib/strip`；`make` 用 NDK 自带 `prebuilt/<host>/bin/make` | Windows 下 wrapper 为 `.cmd`，脚本统一用 clang 直调 + `--target` |
| host 工具 | perl（Git Bash 自带，openssl Configure 需要）、tar/xz、node ≥18（fetch 下载/校验） | autoconf **不假设存在**（config.mak 路线兜底） |
| API / ABI | android-24 / arm64-v8a（lock `androidApi` ✅） | — |
| 版本钉选 | 见 §2.1 PINNED 表（draft：git 2.51.0；zlib/openssl/curl/cacert 以 fetch 实现定稿回写 lock） | 规划 §4.1 四源表 |

### 1.2 关键决策（沿规划 D1–D7，本模块相关）

| 决策 | 本模块落点 |
|---|---|
| D2 静态链入 | 依赖三件全 `.a`；git 链接注入路径（§3.3） |
| D3 缺项 NO_* | git config.mak/configure 的 NO_* 全集（§3.3） |
| D5 helper 命名 | `libgit_<名>.so` 映射 + gitexec-manifest.json（§3.4） |
| D6 assets 纯数据 | templates/cacert/manifest 三件，无 `.so` 无 exec 位（§3.4） |

---

## 2. fetch 脚本设计（`scripts/fetch-git-cli-source.mjs`，M1-T1）

### 2.1 PINNED 钉选表（内置常量；定稿值以脚本为准，lock 同步）

```
PINS = {
  git:     { version: '2.51.0', url: 'https://github.com/git/git/releases/download/v{v}/git-{v}.tar.gz', sha256: '<官方包实测>' },
  zlib:    { version: '1.3.1',  url: 'https://zlib.net/fossils/zlib-{v}.tar.gz', sha256: '…' },
  openssl: { version: '<3.x>',  url: 'https://github.com/openssl/openssl/releases/download/openssl-{v}/openssl-{v}.tar.gz', sha256: '…' },
  curl:    { version: '<8.x>',  url: 'https://curl.se/download/curl-{v}.tar.xz', sha256: '…' },
  cacert:  { version: '<date>', url: 'https://curl.se/ca/cacert-<date>.pem', sha256: '…' },
}
```

- sha256 取值纪律：**官方发布包一手实测**（下载后计算并与人读的官方 checksum 页核对），绝不凭记忆填；
- `--git <ver>` 覆盖 PINS.git.version（其余不开放覆盖，防漂移）；版本不在表内 ⇒ exit 2（FR-001-006）。

### 2.2 流程

```
① 逐项：缓存文件在（.dist/dl/<name>-<ver>.tar*）且 sha256 匹配 → 跳过下载（FR-001-003）
② 下载（node 内置 fetch，官方 URL 直连）→ sha256 校验失败 ⇒ 删缓存 exit 2（FR-001-001）
③ 解压到 .dist/src/<name>/（git/zlib/openssl/curl）+ cacert.pem 落 .dist/src/cacert.pem
   解压前清旧目录（幂等，FR-001-004）
④ 校验解压后树存在性（git: Makefile+GIT-VERSION-GEN；zlib: configure；openssl: Configure；curl: configure）
⑤ 打印/回写版本表 → lock.builtFrom.deps（FR-001-005，见 §5.1）+ FETCH-METADATA.json（FR-001-034 之取侧）
```

退出码：0 成功 · 2 校验失败/版本不在钉选表 · 1 用法/IO（沿用全仓契约）。

---

## 3. build 脚本设计（`scripts/build-git-cli-android.sh`，M1-T2/T3/T4）

### 3.1 总流程与阶段缓存

```
env 解析（--git/--api/--src/--deps/--ndk/--out；TOOLCHAIN 推导）
→ S1 zlib → S2 openssl → S3 curl（各阶段产物 .a 存在即跳过，FR-001-014/026）
→ S4 git configure（autoconf 路线失败自动回退 config.mak，FR-001-025）
→ S5 make -j → S6 helper 清单探明（FR-001-024，R1）
→ S7 strip + libgit_*.so 命名映射 → S8 assets 收集 + gitexec-manifest.json
→ S9 BUILD-METADATA.txt / FETCH-METADATA.json 归位（FR-001-034/035）
```

### 3.2 依赖静态构建参数（⬜ 首轮试编拍板，规划 §4.2②）

| 源 | 命令要点 | 产物 |
|---|---|---|
| zlib | `CC="$CLANG" CFLAGS="--target=… -fPIC" ./configure --static`（CHOST 等价 aarch64；R9） | `libz.a` |
| openssl | `perl Configure android-arm64 no-shared no-tests -fPIC --libdir=lib \`（`CC`/`CFLAGS` 注入；R7） | `libssl.a` `libcrypto.a` |
| curl | `./configure --host=aarch64-linux-android --disable-shared --enable-static --with-openssl=<deps>/openssl --with-zlib=<deps>/zlib --without-libpsl --without-brotli --without-zstd --without-libidn2 --disable-ldap --disable-ldaps`（R8） | `libcurl.a` |

### 3.3 git 构建参数（config.mak 直写为主路线；⬜ 试编后回写）

```make
# config.mak（生成进 git 源码树外：build/out/config.mak，make -f 注入，不改源树 → C1）
CC = <clang --target=aarch64-linux-android24>
AR/RANLIB/STRIP = llvm-*
CFLAGS  = -O2 -fPIC
LDFLAGS = -Wl,-z,max-page-size=16384        # D/FR-001-022
NO_TCLTK=1  NO_GETTEXT=1  NO_ICONV=1  NO_REGEX=1  NO_PERL=1  NO_PYTHON=1   # D3
NO_INSTALL_HARDLINKS=1（产物收集按副本）
CURL_CONFIG/<CURLDIR> 或 CURL_LDFLAGS/CURL_CFLAGS + OPENSSL/ZLIB 路径注入    # FR-001-013
INSTALL_SYMLINKS/NO_CROSS_DIRECTORY_HARDLINKS 视实产调整（helper 别名形态 ⬜）
```

- 产物集（候选，R1 ⬜）：`git`、`git-remote-http(s)`、`git-upload-pack`、`git-receive-pack`、
  `git-upload-archive`、`git-http-fetch/push`（裁剪待定）、`git-shell`/`git-imap-send`（默认裁）；
- 探明动作（S6）：枚举 make 产物中「ELF 可执行」全集 + 别名（hardlink/symlink 形态记录），写
  `helper-inventory.json`（实产清单），供 §3.4 manifest 生成与 002 白名单回写。

### 3.4 产物命名映射与 assets（FR-001-031/032/033）

| make 产物 | 物理件（jniLibs 名） | 农场名（gitexec-manifest 条目） |
|---|---|---|
| `git` | `libgit_cli.so` | `git` + `git-upload-pack`/`git-receive-pack`/`git-upload-archive`（argv[0] 分发，同物理件） |
| `git-remote-http`（含 https/ftp/ftps 别名 ⬜） | `libgit_remote_curl.so` | `git-remote-http` `git-remote-https`（`-ftp*` 按实产） |
| `git-http-fetch` / `git-http-push`（若随包 ⬜） | `libgit_http_fetch.so` / `libgit_http_push.so` | 同名 |

- manifest schema（gitexec-manifest.json，§5.2）：`{ "$schema"…, "farm": { "<农场名>": "<libgit_*.so>" }, "notes": … }`；
- assets 收集：`<out>/assets/git-bridge-tools/{templates/**, cacert.pem, gitexec-manifest.json}`，
  `chmod -x` 全体（纯数据纪律）；templates 取 git 源码树 `templates/`（M1-T4 定稿 ⬜）。

### 3.5 METADATA（FR-001-034/035）

- `BUILD-METADATA.txt`：逐产物 {文件, size(strip 前/后), sha256, 命名映射来源} + 参数快照（NDK 版本、API、flags、configure 路线、时间）；
- `FETCH-METADATA.json`：五输入 {name, version, url, sha256} + fetch 时间（fetch 脚本产出，build 归档收编）。

---

## 4. 宪法符合性检查（逐条）

| 原则 | 判定 | 依据 |
|---|---|---|
| C1 fetch 不改源 | ✅ 设计符合 | 解压即用；缺项 NO_*/--without-*；config.mak 写在源树外（make -f / Makefile include ⬜ 试编定）；仓库无补丁 |
| C2 lock 唯一事实源 | ✅ | 五输入版本+sha256 进 `builtFrom.deps` 版本表（§5.1）；产物 sha/size 回写 releases 条目 |
| C3 二进制不入库 | ✅ | 全部产物落 `.dist/`、`build/out/`（.gitignore 已列）；入库只有脚本与规格 |
| C4 门禁强制 | ✅ | build 只产不判；投放判定归 provision（002）；脚本出口提示 `--inspect` 自检 |
| C5 发布卫生 | ➖ | 本模块不触碰发布 |
| C6 未实测标 ⬜ | ✅ | 本文全部构建参数标 ⬜ 待首轮试编回写；探明前 §5.2 表为候选 |
| C7 GPLv2 对应源码 | ✅ | FETCH-METADATA 记录四源出处；Release 归档义务在 002（M1-T6） |
| C8 先改文档再改实现 | ✅ | 本文件先于实现；实产清单/别名形态/体积回写规划 §5.2 与本文件 |

---

## 5. 数据模型变更（lock 扩展，规划 §8）

### 5.1 `releases[].builtFrom.deps`（文本 → 版本表）

```json
"deps": {
  "zlib":    { "version": "1.3.1", "sha256": "<官方包>" },
  "openssl": { "version": "3.x.y", "sha256": "…" },
  "curl":    { "version": "8.x.y", "sha256": "…" }
}
```

（git 本体在 `builtFrom.source` 升级为 `{version,url,sha256}`；cacert 进 assets manifest，规划 §5.3。）

### 5.2 `matrix.jniLibsWhitelist` + `builtFrom.helpers`（002 消费，本模块产出清单）

- `helper-inventory.json`（构建产物）→ 人工/CI 回写 lock `matrix.jniLibsWhitelist`（`libgit_cli.so` + helper 集）；
- `releases[].builtFrom.helpers`：逐 helper {farm 名, 物理件, sha256}。

---

## 6. FR 交叉引用（spec ↔ 实现）

| FR | 实现落点 | 状态 |
|---|---|---|
| FR-001-001~006 | `scripts/fetch-git-cli-source.mjs`（PINS 表 + 幂等 + 校验 + deps 回写） | ⬜（现为骨架 exit 2） |
| FR-001-010~014 | `build-git-cli-android.sh` S1–S3 | ⬜ |
| FR-001-020~026 | 同上 S4–S6（config.mak 生成器 + NO_* + LDFLAGS + 探明） | ⬜ |
| FR-001-030~035 | 同上 S7–S9（strip/命名/assets/manifest/METADATA） | ⬜ |

---

## 7. 风险与回退（沿规划 §11）

| # | 风险 | 回退 |
|---|---|---|
| R7 openssl×NDK | Configure 失败 ⇒ 降级试 `android-arm64` + `no-asm`；再失败 ⇒ https 首版不编，如实上报 |
| R8 curl 裁剪 | 缺库逐项 `--without-*`；仍失败 ⇒ `--disable-all --enable-https --enable-static` 最小集 |
| R9 zlib CHOST | configure 失败 ⇒ 手写 Makefile 片段（不进源树） |
| R1 helper 清单 | 以 S6 实产为准；别名形态（hardlink/symlink）决定 manifest 生成方式 |
| Windows 兼容 | clang `.cmd` wrapper / 路径空格 / `make` 来源（NDK 自带）；CI（Linux）为主口径，本机为辅 |

---

## 8. 待实现清单

- [ ] fetch：PINS 定稿（五输入官方 sha256 实测）+ 下载/校验/解压/幂等（FR-001-001~006）
- [ ] build S1–S3 依赖静态构建（FR-001-010~014）
- [ ] build S4–S5 config.mak 生成 + make（FR-001-020~023/025/026）
- [ ] build S6 helper 探明 + S7–S9 整理/收集/METADATA（FR-001-024/030~035）
- [ ] lock 回写：deps 版本表 + helper 清单 + ndk + 体积（C2/C8）
- [ ] 首轮试编结论回写本文件（⬜ → ✅/🔶）与规划 §4.2/§5.2
