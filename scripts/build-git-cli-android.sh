#!/usr/bin/env bash
# scripts/build-git-cli-android.sh —— NDK 交叉编译 git 为 Android arm64 的 exec 型
# git 命令行（libgit_cli.so，PIE 可执行，zlib/curl/openssl 静态链入）。
#
# 纪律（docs/000-工程规划.md §4.2 / specs/001-building/plan.md；C1/D2/D3/D5/D6）：
#   1) configure 以 NO_* 关闭 Android 缺项：NO_TCLTK / NO_GETTEXT / NO_ICONV / NO_REGEX / NO_PERL / NO_PYTHON；
#   2) zlib / libcurl / OpenSSL 静态链入（https 传输）；产物 DT_NEEDED 只剩系统库；
#   3) -Wl,-z,max-page-size=16384（16KB 页设备硬要求）；
#   4) 产物 exec 型 ELF：PIE + PT_INTERP=/system/bin/linker64（门禁②由 provision 判定）；
#   5) 输出命名 libgit_cli.so / libgit_<名>.so（Android 打包只认 lib*.so）；
#   6) assets 纯数据：templates/ + cacert.pem + gitexec-manifest.json（无 .so、无 exec 位）。
#   7) 不改源：config.mak 是 git Makefile 官方 include 点（新增文件，不改既有文件；C1）。
#
# 阶段（可缓存续跑；--force 重建；产物存在即跳过）：
#   S1 zlib → S2 openssl → S3 curl → S4 config.mak → S5 make → S6 helper 探明
#   → S7 strip+命名 → S8 assets+manifest → S9 METADATA
#
# 用法：
#   bash scripts/build-git-cli-android.sh --git 2.56.0 --api 24 \
#     --src .dist/src --deps .dist/src --ndk "$NDK" --out build/out [-j N] [--stage S6] [--force]
#
# 退出码：0 成功 · 2 阶段失败（工具链/编译/校验） · 1 用法/IO 错误
set -euo pipefail

usage() {
  cat <<'EOF'
用法: build-git-cli-android.sh --git <ver> --api <api> --src <git 源码树> --deps <依赖源码根> --ndk <ndk> --out <dir>
  --git    git 上游版本（= CLI_VERSION，须与源码树一致）
  --api    Android API level（默认 24）
  --src    四源源码根（fetch 脚本产出；git 树 = <src>/git）
  --deps   同 --src（zlib/openssl/curl 树在 <deps>/ 下）
  --ndk    Android NDK 路径（Windows 盘符路径可）
  --out    产物目录（默认 build/out）
  -j N     并行度（默认 nproc）
  --stage  只跑到指定阶段（S1..S9）
  --force  忽略阶段缓存重建
EOF
}

GITVER="" API="24" ARCH="arm64-v8a" SRC="" DEPS="" NDK="" OUT="build/out" JOBS="" STAGE="S9" FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --git) GITVER="$2"; shift 2;;
    --api) API="$2"; shift 2;;
    --arch) ARCH="$2"; shift 2;;
    --src) SRC="$2"; shift 2;;
    --deps) DEPS="$2"; shift 2;;
    --ndk) NDK="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    -j|--jobs) JOBS="$2"; shift 2;;
    --stage) STAGE="$2"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "未知参数: $1" >&2; usage; exit 1;;
  esac
done
[[ -z "$GITVER" || -z "$SRC" || -z "$NDK" ]] && { usage; exit 1; }
DEPS="${DEPS:-$SRC}"

say() { echo "[build] $*"; }
die() { echo "[build] 失败: $*" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── 路径归一（Windows 盘符 → MSYS POSIX；MSYS 工具链需要）───────────────────
to_posix() {
  local p="$1"
  if [[ "$p" =~ ^[A-Za-z]:[\\/].* ]]; then
    local drive="${p:0:1}"; local rest="${p:3}"; rest="${rest//\\//}"
    echo "/$(echo "$drive" | tr 'A-Z' 'a-z')/$rest"
  else
    echo "$p"
  fi
}
NDK="$(to_posix "$NDK")"; SRC="$(to_posix "$SRC")"; DEPS="$(to_posix "$DEPS")"; OUT="$(to_posix "$OUT")"
# 归一为绝对路径（openssl Configure 的 --prefix 等要求绝对路径）
abs() { case "$1" in /*) echo "$1";; *) echo "$PWD/$1";; esac; }
SRC="$(abs "$SRC")"; DEPS="$(abs "$DEPS")"; OUT="$(abs "$OUT")"
[[ -d "$NDK" ]] || die "NDK 不存在: $NDK"
[[ -f "$SRC/git/Makefile" ]] || die "缺 git 源码树: $SRC/git（先跑 fetch）"

# ── 工具链定位（host tag 探测；Windows 用 NDK 自带 make.exe + sh wrapper）──
case "$(uname -s)" in
  Linux) HOST_TAG="linux-x86_64";;
  Darwin) HOST_TAG="darwin-x86_64";;
  MINGW*|MSYS*|CYGWIN*) HOST_TAG="windows-x86_64";;
  *) die "不支持的宿主: $(uname -s)";;
esac
PREBUILD="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
[[ -d "$PREBUILD/bin" ]] || die "缺工具链: $PREBUILD/bin"
if [[ "$HOST_TAG" == "windows-x86_64" ]]; then
  [[ -f "$NDK/prebuilt/windows-x86_64/bin/make.exe" ]] || die "缺 NDK make.exe"
  export PATH="$NDK/prebuilt/windows-x86_64/bin:$PATH"
  export MAKEFLAGS_SHELL="SHELL=/usr/bin/sh"
fi
export PATH="$PREBUILD/bin:$PATH"
MAKE="make"
command -v "$MAKE" >/dev/null 2>&1 || die "缺 make"

# ── 目标三元组（arm64-v8a=aarch64 产品线；x86_64 仅限本地测试构建，不入 lock/AAR）──
case "$ARCH" in
  arm64-v8a) TRIPLE="aarch64-linux-android";;
  x86_64) TRIPLE="x86_64-linux-android"
    [[ "$OUT" == *"x64"* || "$OUT" == *"test"* ]] || die "--arch x86_64 测试构建的 --out 必须含 x64/test 标识（防与产品 arm64 产物混淆，C2/C3）";;
  *) die "不支持的 --arch: $ARCH（arm64-v8a 产品 / x86_64 本地测试）";;
esac

CC="$PREBUILD/bin/${TRIPLE}${API}-clang"
CXX="$PREBUILD/bin/${TRIPLE}${API}-clang++"
[[ -f "$CC" || -f "$CC.cmd" ]] || die "缺交叉 clang: $CC"
AR="llvm-ar"; RANLIB="llvm-ranlib"; STRIP="llvm-strip"
command -v clang >/dev/null 2>&1 || die "clang 不在 PATH（$PREBUILD/bin）"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"

CFLAGS_COMMON="--target=${TRIPLE}${API} -fPIC -O2"
LDFLAGS_16K="-Wl,-z,max-page-size=16384"

mkdir -p "$OUT"
DEPS_OUT="$OUT/deps"
mkdir -p "$DEPS_OUT"

stage_done() { [[ -f "$1" && "$FORCE" -eq 0 ]]; }
le_stage() { echo "── $1 ───────────────────────────────────────────"; }

# ══ S1 zlib（产物 libz.a）════════════════════════════════════════════════════
if [[ ! "$STAGE" < "S1" ]]; then
  le_stage "S1 zlib"
  ZLIB_A="$DEPS_OUT/zlib/libz.a"
  if stage_done "$ZLIB_A"; then
    say "✔ S1 缓存命中（$ZLIB_A）"
  else
    say "configure zlib（CC 直注，静态）"
    ( cd "$DEPS/zlib" \
      && CC="$CC" CFLAGS="$CFLAGS_COMMON" AR="$AR" RANLIB="$RANLIB" \
         ./configure --static ) || die "zlib configure 失败（R9：CHOST 路线；可手写 Makefile 片段）"
    ( cd "$DEPS/zlib" && "$MAKE" ${MAKEFLAGS_SHELL:-} -j"$JOBS" libz.a ) || die "zlib make 失败"
    mkdir -p "$DEPS_OUT/zlib"
    cp "$DEPS/zlib/libz.a" "$DEPS_OUT/zlib/libz.a"
    [[ -f "$DEPS_OUT/zlib/libz.a" ]] || die "libz.a 未产出"
    say "✔ libz.a（$(du -h "$DEPS_OUT/zlib/libz.a" | cut -f1)）"
  fi
fi

# ══ S2 openssl（产物 libssl.a + libcrypto.a）════════════════════════════════
if [[ ! "$STAGE" < "S2" ]]; then
  le_stage "S2 openssl"
  SSL_A="$DEPS_OUT/openssl/lib/libssl.a"
  if stage_done "$SSL_A"; then
    say "✔ S2 缓存命中（$SSL_A）"
  else
    # git-bash 自带 perl 为裁剪版（缺 Locale::Maketext::Simple / ExtUtils::MakeMaker / Pod::* 等，
    # openssl Configure 依赖链 IPC::Cmd→Params::Check / configdata→Pod::Usage 需要）。
    # 从 CPAN（metacpan API）补齐到 .dist/perl-deps（PERL5LIB 注入；不触碰源码树，C1）；
    # 每次实际下载的 url+sha256 记入 PERL-DEPS.lock.json（host 侧构建工具依赖，审计用；产品输入仍以 lock 为准）。
    # CI（ubuntu）系统 perl 完整，此步自动跳过。
    PERL_DEPS="$ROOT/.dist/perl-deps"
    # PERL5LIB 供 bash→perl 直调；PERL5OPT=-I… 供 make.exe（native）转发的 perl 子进程
    # （PERL5LIB 经 native make 传递时盘符冒号会被 cygwin perl 按 ':' 拆坏，PERL5OPT 由 perl 自解析不受影响）
    export PERL5LIB="$PERL_DEPS/lib"
    export PERL5OPT="-I$PERL_DEPS/lib"
    PERL_MODS=(Locale::Maketext::Simple ExtUtils::MakeMaker Pod::Escapes Pod::Simple Pod::Text Pod::Usage Pod::Perldoc)
    need_perl=0
    for m in "${PERL_MODS[@]}"; do
      perl -M"$m" -e 1 >/dev/null 2>&1 || need_perl=1
    done
    if [[ $need_perl -eq 1 ]]; then
      mkdir -p "$PERL_DEPS/lib" "$PERL_DEPS/locks"
      for m in "${PERL_MODS[@]}"; do
        perl -M"$m" -e 1 >/dev/null 2>&1 && continue
        say "↓ CPAN $m（metacpan latest-stable，sha256 记锁）"
        url="$(curl -s --max-time 30 "https://api.metacpan.org/v1/download_url/$m" | grep -o '"download_url" : "[^"]*"' | cut -d'"' -f4)"
        sha="$(curl -s --max-time 30 "https://api.metacpan.org/v1/download_url/$m" | grep -o '"checksum_sha256" : "[^"]*"' | cut -d'"' -f4)"
        [[ -n "$url" && -n "$sha" ]] || die "metacpan 查询失败：$m"
        tgz="$PERL_DEPS/$(basename "$url")"
        curl -sL --retry 3 --max-time 240 -o "$tgz" "$url" || die "$m 下载失败"
        echo "$sha  $tgz" | sha256sum -c - >/dev/null || die "$m sha256 不匹配（$sha）"
        printf '{"module":"%s","url":"%s","sha256":"%s"}\n' "$m" "$url" "$sha" > "$PERL_DEPS/locks/$m.lock.json"
        tar --force-local -xzf "$tgz" -C "$PERL_DEPS" || die "$m 解压失败"
        cp -r "$PERL_DEPS/$(basename "${tgz%.tar.gz}")"/lib/* "$PERL_DEPS/lib/" 2>/dev/null || true
        perl -M"$m" -e 1 >/dev/null 2>&1 || die "$m 装配失败"
        say "✔ $m"
      done
    fi
    say "Configure openssl android-arm64（no-shared no-tests；ANDROID_API=$API 对齐 minSdk，防产物引用 API>minSdk 符号）"
    ( cd "$DEPS/openssl" \
      && ANDROID_NDK_ROOT="$NDK" ANDROID_API="$API" perl Configure android-arm64 no-shared no-tests \
         -fPIC -O2 --libdir=lib --prefix="$DEPS_OUT/openssl" \
         CC="$CC" ) || die "openssl Configure 失败（R7：可试 no-asm 降级）"
    ( cd "$DEPS/openssl" && "$MAKE" ${MAKEFLAGS_SHELL:-} -j"$JOBS" build_sw ) || die "openssl make 失败"
    ( cd "$DEPS/openssl" && "$MAKE" install_sw install_ssldirs >/dev/null ) || die "openssl install 失败"
    [[ -f "$DEPS_OUT/openssl/lib/libssl.a" && -f "$DEPS_OUT/openssl/lib/libcrypto.a" ]] || die "openssl .a 未产出"
    say "✔ libssl.a + libcrypto.a（$(du -h "$DEPS_OUT/openssl/lib/libcrypto.a" | cut -f1)）"
  fi
fi

# ══ S3 curl（产物 libcurl.a；CMake + NDK toolchain 路线）═════════════════════
# 注：autotools/libtool 路线在 MSYS（Windows make.exe 转发）下断裂（"C:/Program: No such file"），
#     改用 CMake + NDK 官方 toolchain file（Windows/Linux 同口径；plan §3.2 回写）。
if [[ ! "$STAGE" < "S3" ]]; then
  le_stage "S3 curl"
  CURL_A="$DEPS_OUT/curl/lib/libcurl.a"
  if stage_done "$CURL_A"; then
    say "✔ S3 缓存命中（$CURL_A）"
  else
    # cmake 定位：pip 装的 cmake（Windows）或系统 cmake（CI）
    CMAKE_BIN="$(command -v cmake || true)"
    if [[ -z "$CMAKE_BIN" ]]; then
      CMAKE_BIN="$(python -c "import cmake,os;print(os.path.join(os.path.dirname(cmake.__file__),'data','bin','cmake.exe'))" 2>/dev/null || true)"
    fi
    [[ -n "$CMAKE_BIN" && -x "$CMAKE_BIN" ]] || die "缺 cmake（pip install cmake 或系统安装）"
    say "cmake: $CMAKE_BIN"
    case "$ARCH" in
      arm64-v8a) CMAKE_ABI="arm64-v8a";;
      x86_64) CMAKE_ABI="x86_64";;
    esac
    CURL_BUILD="$DEPS_OUT/curl-build"
    "$CMAKE_BIN" -S "$DEPS/curl" -B "$CURL_BUILD" -G "Unix Makefiles" \
      -DCMAKE_MAKE_PROGRAM="$MAKE" \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$CMAKE_ABI" -DANDROID_PLATFORM="android-$API" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
      -DCMAKE_INSTALL_PREFIX="$DEPS_OUT/curl" \
      -DCURL_USE_OPENSSL=ON -DOPENSSL_ROOT_DIR="$DEPS_OUT/openssl" \
      -DOPENSSL_CRYPTO_LIBRARY="$DEPS_OUT/openssl/lib/libcrypto.a" \
      -DOPENSSL_SSL_LIBRARY="$DEPS_OUT/openssl/lib/libssl.a" \
      -DOPENSSL_INCLUDE_DIR="$DEPS_OUT/openssl/include" \
      -DZLIB_LIBRARY="$DEPS_OUT/zlib/libz.a" -DZLIB_INCLUDE_DIR="$DEPS/zlib" \
      -DCURL_USE_MBEDTLS=OFF -DCURL_USE_WOLFSSL=OFF -DCURL_USE_GNUTLS=OFF \
      -DCURL_USE_LIBPSL=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DUSE_LIBIDN2=OFF \
      -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON \
      -DCURL_DISABLE_FTP=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_TELNET=ON \
      -DCURL_DISABLE_TFTP=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_DICT=ON \
      -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_SMTP=ON \
      -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_SMB=ON \
      -DCURL_DISABLE_TESTS=ON -DENABLE_UNIX_SOCKETS=ON \
      > "$OUT/curl-cmake-configure.log" 2>&1 || { tail -20 "$OUT/curl-cmake-configure.log"; die "curl cmake configure 失败（R8）"; }
    "$CMAKE_BIN" --build "$CURL_BUILD" -j "$JOBS" > "$OUT/curl-cmake-build.log" 2>&1 \
      || { tail -20 "$OUT/curl-cmake-build.log"; die "curl cmake build 失败"; }
    "$CMAKE_BIN" --install "$CURL_BUILD" > /dev/null || die "curl install 失败"
    [[ -f "$CURL_A" ]] || die "libcurl.a 未产出"
    say "✔ libcurl.a（$(du -h "$CURL_A" | cut -f1)，CMake 路线）"
  fi
fi

# ══ S4 config.mak 生成（git 官方 include 点；新增文件不改源，C1）═════════════
if [[ ! "$STAGE" < "S4" ]]; then
  le_stage "S4 git config.mak"
  GITDIR="$SRC/git"
  cat > "$GITDIR/config.mak" <<EOF
# auto-generated by scripts/build-git-cli-android.sh (git Makefile official include point; untracked)
CC = $CC
AR = $AR
RANLIB = $RANLIB
STRIP = $STRIP
CFLAGS = $CFLAGS_COMMON
LDFLAGS = $LDFLAGS_16K
# 依赖注入（git Makefile 真实变量：BASIC_CFLAGS/CURL_CFLAGS/CURL_LDFLAGS/OPENSSLDIR/BASIC_LDFLAGS）
BASIC_CFLAGS += -I$DEPS_OUT/openssl/include -I$DEPS/zlib -I$DEPS_OUT/curl/include
BASIC_LDFLAGS += -L$DEPS_OUT/openssl/lib -L$DEPS_OUT/zlib -L$DEPS_OUT/curl/lib
CURL_CFLAGS = -I$DEPS_OUT/curl/include
# 静态链接闭包：libcurl.a 的 SSL_*/EVP_*/zlib 符号必须由后续 -lssl -lcrypto -lz 供出
CURL_LDFLAGS = -L$DEPS_OUT/curl/lib -lcurl -L$DEPS_OUT/openssl/lib -lssl -lcrypto -L$DEPS_OUT/zlib -lz
OPENSSLDIR = $DEPS_OUT/openssl
NO_TCLTK = YesPlease
NO_GETTEXT = YesPlease
NO_ICONV = YesPlease
NO_REGEX = YesPlease
NO_PERL = YesPlease
NO_PYTHON = YesPlease
NO_EXPAT = YesPlease
# git 2.56 引入 Rust 子系统（libgitcore）；NDK 交叉 cargo 工具链不在本线范围，D3 缺项关闭
NO_RUST = YesPlease
# bionic pthread 全在 libc（无独立 libpthread；NDK 无 -lpthread 可链）
PTHREAD_LIBS =
# bionic<28 无 getrandom()（API 24）；随机源走 /dev/urandom 默认路径
CSPRNG_METHOD = DEFAULT
# uname_S=Linux 块带入的 glibc 特性在 bionic 缺席（config.mak 后包含，覆盖为空即关闭）
HAVE_SYNC_FILE_RANGE =
# 宿主 HOME 为 Windows 路径会经 prefix 污染 C 字符串宏（\U 非法转义）；运行期由 GIT_EXEC_PATH 农场提供
prefix = /usr
# bionic 无线程取消 API（pthread_setcancelstate/PTHREAD_CANCEL_DISABLE 未声明；git 仅作防护性调用，
# 恒为空操作语义）——编译期 compat 宏，不改源码（C1：与 NO_* 同类的配置关闭）
BASIC_CFLAGS += -DPTHREAD_CANCEL_DISABLE=0 '-Dpthread_setcancelstate(state,oldstate)=0'
NO_INSTALL_HARDLINKS = YesPlease
NO_CROSS_DIRECTORY_HARDLINKS = YesPlease
INSTALL_SYMLINKS = YesPlease
V = 1
EOF
  say "✔ config.mak 写入 $GITDIR/config.mak（autoconf 路线省略：缺 autoconf 时 config.mak 直写为 Termux 同款主路线）"
fi

# ══ S5 make（git 主二进制 + helper 集）═══════════════════════════════════════
if [[ ! "$STAGE" < "S5" ]]; then
  le_stage "S5 git make"
  GITDIR="$SRC/git"
  if stage_done "$GITDIR/git" && [[ "$FORCE" -eq 0 ]]; then
    say "✔ S5 缓存命中（git 二进制已存在）"
  else
    ( cd "$GITDIR" && "$MAKE" ${MAKEFLAGS_SHELL:-} -j"$JOBS" uname_S=Linux uname_O=Unix \
        NO_LINT=1 ) || die "git make 失败（检查 config.mak 与依赖 .a）"
    [[ -x "$GITDIR/git" ]] || die "git 主二进制未产出"
    say "✔ git（$(du -h "$GITDIR/git" | cut -f1)，未 strip）"
  fi
fi

# ══ S6 helper 实产清单探明（R1；回写依据）═══════════════════════════════════
if [[ ! "$STAGE" < "S6" ]]; then
  le_stage "S6 helper 探明"
  GITDIR="$SRC/git"
  node - "$GITDIR" "$OUT" <<'NODE'
// 枚举 git 源树顶层 ELF 可执行 + 链接形态（symlink/hardlink/独立文件）
const fs = require('fs'), path = require('path');
const dir = process.argv[2], out = process.argv[3];
const entries = [];
for (const f of fs.readdirSync(dir)) {
  const p = path.join(dir, f);
  const st = fs.lstatSync(p);
  if (!st.isFile() && !st.isSymbolicLink()) continue;
  let kind = null;
  if (st.isSymbolicLink()) kind = 'symlink:' + fs.readlinkSync(p);
  else {
    const fd = fs.openSync(p, 'r');
    const b = Buffer.alloc(4); fs.readSync(fd, b, 0, 4, 0); fs.closeSync(fd);
    if (b.readUInt32BE(0) !== 0x7f454c46) continue; // 只登记 ELF
    kind = st.nlink > 1 ? `hardlink(x${st.nlink})` : 'file';
  }
  entries.push({ name: f, form: kind });
}
entries.sort((a, b) => a.name.localeCompare(b.name));
fs.writeFileSync(path.join(out, 'helper-inventory.json'), JSON.stringify({ discoveredAt: new Date().toISOString(), entries }, null, 2) + '\n');
console.log('[build] helper-inventory.json：' + entries.length + ' 个 ELF/链接条目');
for (const e of entries) console.log(`  ${e.name.padEnd(28)} ${e.form}`);
NODE
  say "✔ 实产清单落盘 $OUT/helper-inventory.json（回写规划 §5.2/lock 依据）"
fi

# ══ S7 strip + libgit_*.so 命名映射（FR-001-030/031）══════════════════════════
if [[ ! "$STAGE" < "S7" ]]; then
  le_stage "S7 strip + 命名映射"
  GITDIR="$SRC/git"
  mkdir -p "$OUT/jni"
  map_bin() { # <源名> <目标 lib 名>
    local src="$GITDIR/$1" dst="$OUT/jni/$2"
    [[ -f "$src" ]] || { say "⚠ 跳过 $1（未产出）"; return 0; }
    cp "$src" "$dst"
    "$STRIP" --strip-unneeded "$dst"
    say "✔ $1 → $2（strip 后 $(du -h "$dst" | cut -f1)）"
  }
  map_bin git          libgit_cli.so
  map_bin git-remote-http libgit_remote_curl.so
  # 候选（是否随包由白名单决定；此处先产出供门禁与决策）
  map_bin git-http-fetch   libgit_http_fetch.so
  map_bin git-http-push    libgit_http_push.so
  [[ -f "$OUT/jni/libgit_cli.so" && -f "$OUT/jni/libgit_remote_curl.so" ]] \
    || die "主二进制/remote helper 缺失（libgit_cli.so + libgit_remote_curl.so 必须在）"
fi

# ══ S8 assets 收集 + gitexec-manifest.json（FR-001-032/033）══════════════════
if [[ ! "$STAGE" < "S8" ]]; then
  le_stage "S8 assets + manifest"
  GITDIR="$SRC/git"
  ASSETS="$OUT/assets/git-bridge-tools"
  rm -rf "$OUT/assets"; mkdir -p "$ASSETS"
  # templates（源码树自带；hooks 仅为样例文件——运行期不可 exec）
  cp -r "$GITDIR/templates" "$ASSETS/templates"
  cp "$SRC/cacert.pem" "$ASSETS/cacert.pem"
  # 农场清单：以 S6 实产为准（别名按 make 实产形态生成；此处按主映射 + dashed 分发）
  node - "$OUT" <<'NODE'
const fs = require('fs'), path = require('path');
const out = process.argv[2];
const inv = JSON.parse(fs.readFileSync(path.join(out, 'helper-inventory.json'), 'utf8')).entries.map((e) => e.name);
const has = (n) => inv.includes(n);
const farm = {
  git: 'libgit_cli.so',
  'git-upload-pack': 'libgit_cli.so',        // argv[0] 分发（builtin）
  'git-receive-pack': 'libgit_cli.so',
  'git-upload-archive': 'libgit_cli.so',
  'git-remote-http': 'libgit_remote_curl.so',
  'git-remote-https': 'libgit_remote_curl.so', // 别名（同体）
};
if (has('git-remote-ftp')) farm['git-remote-ftp'] = 'libgit_remote_curl.so';
if (has('git-remote-ftps')) farm['git-remote-ftps'] = 'libgit_remote_curl.so';
const manifest = {
  $schema: 'gitexec-farm/1',
  note: 'farm names → physical libgit_*.so; consumer creates symlinks in filesDir/gitexec; GIT_EXEC_PATH points there (D5)',
  farm,
};
const dst = path.join(out, 'assets', 'git-bridge-tools', 'gitexec-manifest.json');
fs.writeFileSync(dst, JSON.stringify(manifest, null, 2) + '\n');
console.log('[build] gitexec-manifest.json：' + Object.keys(farm).length + ' 条 farm 条目');
NODE
  # 纯数据纪律：去可执行位、拒绝 .so
  find "$ASSETS" -type f ! -name "*.pem" ! -name "*.json" ! -name "*.sample" ! -name "*.hook" | while read -r f; do
    case "$f" in *hooks*|*Info/exclude*|*info/exclude*) ;; esac
  done
  chmod -R a-x "$ASSETS" 2>/dev/null || true
  if find "$ASSETS" -type f -name "*.so" | grep -q .; then die "assets 内出现 .so（纯数据纪律）"; fi
  say "✔ assets 就绪（templates + cacert.pem + gitexec-manifest.json；无可执行位）"
fi

# ══ S9 BUILD-METADATA（FR-001-034/035）══════════════════════════════════════
if [[ ! "$STAGE" < "S9" ]]; then
  le_stage "S9 BUILD-METADATA"
  {
    echo "# git-cli android arm64 build metadata"
    echo "builtAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "git: $GITVER (kernel.org official tarball, unmodified)"
    echo "ndk: $(basename "$NDK") (host: $HOST_TAG)"
    echo "api: $API  abi: arm64-v8a"
    echo "flags: $CFLAGS_COMMON ; LDFLAGS: $LDFLAGS_16K ; strip: llvm-strip --strip-unneeded"
    echo "configureRoute: config.mak direct (autoconf not assumed; Termux-style)"
    echo "deps: zlib(static) openssl(static) curl(static) — see .dist/FETCH-METADATA.json for versions/sha256"
    echo
    echo "# artifacts (post-strip)"
    for f in "$OUT"/jni/*.so; do
      echo "$(basename "$f")  size=$(stat -c%s "$f")  sha256=$(sha256sum "$f" | cut -d' ' -f1)"
    done
    echo
    echo "# helper inventory (S6, pre-rename) — see helper-inventory.json"
  } > "$OUT/BUILD-METADATA.txt"
  say "✔ BUILD-METADATA.txt 落盘"
  say "完成：$OUT/jni/*.so + assets/ + METADATA（下一步：node tools/provision.mjs --inspect <so> 逐个过门禁）"
fi
