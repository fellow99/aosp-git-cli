#!/usr/bin/env bash
# scripts/build-git-cli-android.sh —— NDK 交叉编译 git 为 Android arm64 的 exec 型
# git 命令行（libgit_cli.so，PIE 可执行，zlib/curl/openssl 静态链入）。
#
# 关键纪律（docs/000-工程规划.md §技术方案；000-scaffold 阶段固化接口，M1 实现）：
#   1) configure 以 NO_* 关闭 Android 缺项：NO_TCLTK / NO_GETTEXT / NO_ICONV / NO_REGEX；
#   2) zlib / libcurl / OpenSSL 静态链入（https 传输）；产物 DT_NEEDED 只剩系统库；
#   3) -Wl,-z,max-page-size=16384（16KB 页设备硬要求）；
#   4) 产物 exec 型 ELF：PIE + PT_INTERP=/system/bin/linker64；
#   5) 输出命名 libgit_cli.so（Android 打包只认 lib*.so）；
#   6) git 模板目录与 CA bundle 作为 assets 随包（运行期经 GIT_TEMPLATE_DIR / SSL_CERT_FILE 注入）。
#
# 产物：<out>/libgit_cli.so（strip）+ <out>/BUILD-METADATA.txt
#
# 用法（规划接口，M1 实现）：
#   scripts/build-git-cli-android.sh \
#     --git 2.51.0 --api 24 \
#     --src .dist/src/git \
#     --deps .dist/src \
#     --ndk "$ANDROID_NDK_HOME" \
#     --out build/out
#
# 状态：000-scaffold 只固化接口与差异纪律；configure/make/strip 门禁链在 M1 落地。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/build-git-cli-android.sh --git <ver> --api <api> --src <git 源码树> --deps <依赖根目录> --ndk <ndk 路径> --out <dir>
  --git   git 上游版本（= CLI_VERSION）
  --api   Android API level（默认 24）
  --src   git-<ver> 解压后的源码树（fetch 脚本产出）
  --deps  静态依赖源码根目录（zlib/curl/openssl）
  --ndk   Android NDK 路径
  --out   产物目录
EOF
}

GITVER=""; API="24"; SRC=""; DEPS=""; NDK=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --git)  GITVER="$2"; shift 2;;
    --api)  API="$2";    shift 2;;
    --src)  SRC="$2";    shift 2;;
    --deps) DEPS="$2";   shift 2;;
    --ndk)  NDK="$2";    shift 2;;
    --out)  OUT="$2";    shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "未知参数: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "$GITVER" || -z "$SRC" || -z "$NDK" || -z "$OUT" ]]; then
  usage
  exit 1
fi

echo "[build] SCAFFOLD: configure/make/strip 门禁链在 M1 实现（000-scaffold 只固化接口与差异纪律）。"
echo "[build] 计划: git=$GITVER api=$API src=$SRC deps=$DEPS ndk=$NDK out=$OUT"
echo "[build] 产物计划: $OUT/libgit_cli.so（exec 型 PIE, zlib/curl/openssl 静态, 16KB 对齐）"
exit 2
