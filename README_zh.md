# aosp-git-cli

[English](README.md) · [**中文**](README_zh.md)

**以 AAR 形式发布的、Android 版 `git` 命令行可执行**——NDK 交叉编译的 `libgit_cli.so`
（arm64-v8a，exec 型 PIE），zlib / libcurl / OpenSSL **静态链入**（https 传输开箱可用），
随包 assets 携带 git 模板与 CA bundle。终端里由 node-pty 经 `forkpty` + `execve` 启动，
提供真正的 `git` 命令（Termux 有成熟先例）。

本仓库不含任何嵌入 API——只有原生二进制与随包数据的可复现构建、ELF 门禁与发布流水线。
规划基线见 [`docs/000-工程规划.md`](docs/000-工程规划.md)；工作区级方案背景见
node-bridge-workspace 的 `docs/aosp+node+python+git运行方案.md`。

## 版本：跟随 git 上游（独立 semver）

制品版本 = git 上游版本。与其它仓无配对关系。**只发布 AArch64（arm64-v8a）**。

### 发布版本 —— Maven Central（`io.github.fellow99:git-cli`）

| 版本 | 状态 | 链接 |
|---|---|---|
| 2.56.0 | ⬜ draft（M1 首产后发布；以 CI 实际钉住的 git 版本为准） | — |

## 构建口径（要点）

- `NO_TCLTK` / `NO_GETTEXT` / `NO_ICONV`（bionic 无 iconv）/ `NO_REGEX`（用自带 compat/regex）；
- zlib / libcurl / OpenSSL **静态链入** → 产物 DT_NEEDED 只剩系统库；
- `-Wl,-z,max-page-size=16384`（16KB 页设备硬要求）；
- ssh 远程（`git@…`）需要单独的 ssh 二进制——不在本仓范围（二期考虑）。

## 用法（消费方）

```kotlin
dependencies {
    runtimeOnly("io.github.fellow99:git-cli:2.56.0") // 独立版本，不与 node 系配对
}
```

终端侧：`PATH` 指向 `nativeLibraryDir`；`GIT_CONFIG_GLOBAL=$HOME/.gitconfig`、
`GIT_TEMPLATE_DIR`、`SSL_CERT_FILE` 由环境引导层注入。

## exec 型打包要点

- **`useLegacyPackaging=true`**（必须物理落盘 `nativeLibraryDir`，否则 `execve` ENOENT）；
- PT_INTERP 必须为 `/system/bin/linker64`（门禁强制）；
- DT_NEEDED 白名单（仅系统库）；16KB 页对齐。

## 如何构建（000-scaffold 骨架；M1 接入真实交叉编译）

```bash
node scripts/fetch-git-cli-source.mjs --git 2.56.0 --out .dist/src   # M1
bash scripts/build-git-cli-android.sh --git 2.56.0 --api 24 \
  --src .dist/src/git --deps .dist/src --ndk "$ANDROID_NDK_HOME" --out build/out  # M1
node tools/provision.mjs --out git-cli/src/main/jniLibs --from build/out/libgit_cli.so
node tools/provision.mjs --check
```

## 锁定与校验

[`git-cli.lock.json`](git-cli.lock.json)（唯一事实源，当前 draft）。退出码：`0` 全过 ·
`2` 门禁不合格/未投放 · `1` 用法/IO 错误。

## 许可

[MIT](LICENSE)。**git 本体为 GPLv2**——随 AAR 分发必须同时提供对应源码
（Release 归档随附源码 tarball 与构建脚本）；zlib/curl/OpenSSL 各随其许可——见
[`git-cli/THIRD-PARTY-NOTICES.md`](git-cli/THIRD-PARTY-NOTICES.md)。
