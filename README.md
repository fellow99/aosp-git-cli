# aosp-git-cli

[English](README.md) · [**中文**](README_zh.md)

**The Android `git` command-line executable, packaged as an AAR** — an NDK cross-compiled
`libgit_cli.so` (arm64-v8a, exec-form PIE) with zlib / libcurl / OpenSSL **statically
linked** (https transport works out of the box), plus bundled assets carrying git templates
and a CA bundle. Launched from the terminal by node-pty via `forkpty` + `execve`, providing
a real `git` command (Termux is the mature precedent).

This repository contains no embedding API — only the reproducible build, ELF gates and
release pipeline for the native binary and its bundled data. Planning baseline:
[`docs/000-工程规划.md`](docs/000-工程规划.md); workspace-level rationale: the
node-bridge-workspace doc `docs/aosp+node+python+git运行方案.md`.

## Version: follows upstream git (independent semver)

The artifact version = the git upstream version. No pairing with other repos.
**AArch64 (arm64-v8a) only**.

### Releases — Maven Central (`io.github.fellow99:git-cli`)

| Version | Status | Link |
|---|---|---|
| 2.51.0 | ⬜ draft (after the first M1 build; the CI-pinned git version prevails) | — |

## Build profile (key points)

- `NO_TCLTK` / `NO_GETTEXT` / `NO_ICONV` (bionic has no iconv) / `NO_REGEX` (bundled compat/regex);
- zlib / libcurl / OpenSSL **statically linked** → DT_NEEDED reduces to system libs;
- `-Wl,-z,max-page-size=16384` (hard requirement on 16KB-page devices);
- ssh remotes (`git@…`) need a separate ssh binary — out of scope here (phase 2).

## Usage (consumers)

```kotlin
dependencies {
    runtimeOnly("io.github.fellow99:git-cli:2.51.0") // independent version, not paired with the node family
}
```

Terminal side: `PATH` points at `nativeLibraryDir`; `GIT_CONFIG_GLOBAL=$HOME/.gitconfig`,
`GIT_TEMPLATE_DIR` and `SSL_CERT_FILE` are injected by the environment bootstrap layer.

## Exec-form packaging points

- **`useLegacyPackaging=true`** (must be physically extracted to `nativeLibraryDir`,
  otherwise `execve` ENOENT);
- PT_INTERP must be `/system/bin/linker64` (hard gate);
- DT_NEEDED whitelist (system libs only); 16KB page alignment.

## How to build (000-scaffold skeleton; real pipeline lands in M1)

```bash
node scripts/fetch-git-cli-source.mjs --git 2.51.0 --out .dist/src   # M1
bash scripts/build-git-cli-android.sh --git 2.51.0 --api 24 \
  --src .dist/src/git --deps .dist/src --ndk "$ANDROID_NDK_HOME" --out build/out  # M1
node tools/provision.mjs --out git-cli/src/main/jniLibs --from build/out/libgit_cli.so
node tools/provision.mjs --check
```

## Lock & verification

[`git-cli.lock.json`](git-cli.lock.json) (single source of truth, currently draft).
Exit codes: `0` pass · `2` gate failure / not provisioned · `1` usage/IO error.

## License

[MIT](LICENSE). **git itself is GPLv2** — distributing the AAR requires offering the
corresponding source (the Release archive ships the source tarball and build scripts);
zlib/curl/OpenSSL carry their own licenses — see
[`git-cli/THIRD-PARTY-NOTICES.md`](git-cli/THIRD-PARTY-NOTICES.md).
