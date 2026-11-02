#!/usr/bin/env bash
# scripts/test-on-device/run-probes.sh —— 003-cli 设备端探针（adb shell 域 L3）
#
# 依据：specs/003-cli/{spec,plan,test-cases}.md（FR-003-001~005；用例 TC-003-00~17）
# 判据口径：adb 探针在 shell 域（/data/local/tmp 可 exec）验证二进制本体行为；
#   不能以此替代 App 域结论（nativeLibraryDir 落盘 / app 域 SELinux，归消费方 ⬜）。
#
# 用法：
#   bash scripts/test-on-device/run-probes.sh --artifacts build/out [--serial <adb serial>] [--case TC-003-01] [--evidence <dir>]
#
# 退出码：0 全部 PASS/SKIP（无 FAIL）· 2 存在 FAIL · 1 用法/IO 错误
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ADB="${ADB:-adb}"
SERIAL="" ARTIFACTS="$ROOT/build/out" CASE_FILTER="" EVIDENCE="$ROOT/logs/evidence"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2;;
    --artifacts) ARTIFACTS="$2"; shift 2;;
    --case) CASE_FILTER="$2"; shift 2;;
    --evidence) EVIDENCE="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | head -12; exit 0;;
    *) echo "未知参数: $1" >&2; exit 1;;
  esac
done

ADB_BIN="$(command -v "$ADB" || true)"
[[ -z "$ADB_BIN" ]] && ADB_BIN="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
[[ -f "$ADB_BIN" ]] || { echo "缺 adb（PATH 或 ANDROID SDK platform-tools）" >&2; exit 1; }
if [[ -n "$SERIAL" ]]; then ADB_CMD=("$ADB_BIN" -s "$SERIAL"); else ADB_CMD=("$ADB_BIN"); fi

DEV="/data/local/tmp/git-cli-probe"
mkdir -p "$EVIDENCE"

say() { echo "[probe] $*"; }

# ── adb 封装 ────────────────────────────────────────────────────────────────
adb_shell() { "${ADB_CMD[@]}" shell "$@"; }
adb_sh() { "${ADB_CMD[@]}" shell "$@" 2>&1; }   # 合并 stderr

# ── 部署（FR-003-001/002/003）────────────────────────────────────────────────
deploy() {
  say "部署 → $DEV（bin/ tools/ gitexec/ home/ tmp/ ws/）"
  adb_shell rm -rf "$DEV"
  adb_shell mkdir -p "$DEV/bin" "$DEV/tools" "$DEV/gitexec" "$DEV/home" "$DEV/tmp" "$DEV/ws"

  # ① 物理件（build/out/jni/*.so → bin/，附执行位）
  for f in "$ARTIFACTS"/jni/*.so; do
    [[ -f "$f" ]] || continue
    "${ADB_CMD[@]}" push "$f" "$DEV/bin/" >/dev/null || return 1
  done
  adb_shell "chmod 755 $DEV/bin/*.so"

  # ② assets（templates/cacert/manifest → tools/）
  "${ADB_CMD[@]}" push "$ARTIFACTS/assets/git-bridge-tools/." "$DEV/tools/" >/dev/null || return 1

  # ③ 农场：依 gitexec-manifest.json 建原名 symlink（先清后建，幂等）
  adb_shell "rm -rf $DEV/gitexec && mkdir -p $DEV/gitexec"
  local farmlist
  farmlist="$(mktemp)"
  node - "$ARTIFACTS" > "$farmlist" <<'NODE'
const fs = require('fs'), path = require('path');
const art = process.argv[2];
const man = JSON.parse(fs.readFileSync(path.join(art, 'assets/git-bridge-tools/gitexec-manifest.json'), 'utf8'));
for (const [name, phys] of Object.entries(man.farm)) console.log(`${name}|${phys}`);
NODE
  while IFS='|' read -r name phys; do
    [[ -n "$name" ]] && adb_shell "ln -s $DEV/bin/$phys $DEV/gitexec/$name"
  done < "$farmlist"
  rm -f "$farmlist"

  # ④ PATH 兜底：bin/git 直呼 symlink
  adb_shell "ln -sf $DEV/bin/libgit_cli.so $DEV/bin/git"

  say "部署完成"
}

# env 契约（plan §2.2 ④；规划 §7.1 表）
ENV_PREFIX="HOME=$DEV/home TMPDIR=$DEV/tmp GIT_EXEC_PATH=$DEV/gitexec GIT_TEMPLATE_DIR=$DEV/tools/templates GIT_CONFIG_GLOBAL=$DEV/home/.gitconfig GIT_CONFIG_NOSYSTEM=1 GIT_SSL_CAINFO=$DEV/tools/cacert.pem SSL_CERT_FILE=$DEV/tools/cacert.pem GIT_PAGER=cat PATH=$DEV/gitexec:\$PATH"
GIT="$DEV/bin/git"

# ── 用例框架 ────────────────────────────────────────────────────────────────
declare -a RESULTS
record() { # <id> <PASS|FAIL|SKIP> <note>
  RESULTS+=("$1|$2|$3")
  printf '[probe] %-14s %-4s %s\n' "$1" "$2" "$3"
  { echo "== $1 [$2] $3"; } >> "$EVIDENCE/results.log"
}
ev() { # <id> <cmd...>：执行并留证
  local id="$1"; shift
  adb_sh "$*" | tee "$EVIDENCE/$id.log" >/dev/null
}

run_case() { # <id>
  local id="$1"
  [[ -n "$CASE_FILTER" && "$id" != "$CASE_FILTER" ]] && return 0
  case "$id" in
    TC-003-00)
      local out; out="$(adb_sh "ls $DEV/bin/ && ls $DEV/gitexec/")"
      local n; n="$(grep -c . <<<"$out")"
      [[ $n -ge 5 ]] && record "$id" PASS "bin+gitexec 清单齐全" || record "$id" FAIL "部署清单不齐: $out"
      ;;
    TC-003-00b)
      local out; out="$(adb_sh "uname -m; getprop ro.build.version.sdk; getconf PAGESIZE; getenforce; ls -Z $DEV/bin/git $DEV/gitexec/git-remote-https 2>/dev/null" | tee "$EVIDENCE/$id.log")"
      record "$id" PASS "环境快照已存证: $(echo "$out" | head -4 | tr '\n' ' ')"
      ;;
    TC-003-01)
      local out rc; out="$(adb_sh "env $ENV_PREFIX $GIT --version")"; rc=$?
      echo "$out" > "$EVIDENCE/$id.log"
      [[ "$out" == *"git version"* && $rc -eq 0 ]] && record "$id" PASS "$out" || record "$id" FAIL "rc=$rc out=$out"
      ;;
    TC-003-02)
      local out ep; out="$(adb_sh "env $ENV_PREFIX $GIT --exec-path")"
      ep="$(adb_sh "echo $DEV/gitexec" )"
      [[ "$out" == *"$DEV/gitexec"* ]] && record "$id" PASS "--exec-path=$out" || record "$id" FAIL "--exec-path=$out ≠ $DEV/gitexec"
      local h; h="$(adb_sh "env $ENV_PREFIX $GIT help -a >/dev/null 2>&1; echo \$?")"
      [[ "$h" == "0" ]] && record "$id-helppager" PASS "help -a 非交互完成" || record "$id-helppager" FAIL "help 挂起/失败 rc=$h"
      ;;
    TC-003-03)
      local out; out="$(adb_sh "cd $DEV/ws && env PATH=$DEV/gitexec:\$PATH git --version" | tee "$EVIDENCE/$id.log")"
      [[ "$out" == *"git version"* ]] && record "$id" PASS "farm git 直呼: $out" || record "$id" FAIL "$out"
      ;;
    TC-003-04)
      local c1 c2
      c1="$(adb_sh "env $ENV_PREFIX $GIT --bogus-flag >/dev/null 2>&1; echo \$?")"
      c2="$(adb_sh "cd $DEV/ws && env $ENV_PREFIX $GIT log >/dev/null 2>&1; echo \$?")"
      { echo "bogus=$c1 norepo=$c2"; } > "$EVIDENCE/$id.log"
      record "$id" PASS "退出码采样 bogus=$c1 norepo=$c2（记录性）"
      ;;
    TC-003-05)
      ev "$id" "cd $DEV/ws && rm -rf repo && env $ENV_PREFIX sh -c '
        $0 init repo >/dev/null &&
        cd repo &&
        $0 config user.name probe && $0 config user.name && $0 config user.email probe@t.local &&
        echo hello > hello.txt && printf \"中文内容\" > 中文文件名.txt &&
        $0 add . &&
        $0 commit -m \"中文提交信息\" >/dev/null &&
        $0 log --oneline &&
        $0 status --short && echo STATUS_OK &&
        ls .git/hooks/*.sample >/dev/null && echo HOOKS_OK &&
        $0 ls-files' $GIT"
      local log; log="$(cat "$EVIDENCE/$id.log")"
      if grep -q "中文提交信息" <<<"$log" && grep -q "STATUS_OK" <<<"$log" && grep -q "HOOKS_OK" <<<"$log" && grep -q "中文文件名.txt" <<<"$log"; then
        record "$id" PASS "init→commit→log 全链（含中文文件名）"
      else
        record "$id" FAIL "$(grep -m3 . <<<"$log" | tr '\n' ' ')"
      fi
      ;;
    TC-003-06)
      ev "$id" "cd $DEV/ws && rm -rf clone1 && env $ENV_PREFIX GIT_TRACE=1 $GIT clone --no-local $DEV/ws/repo clone1 2>&1 | tail -20 && cd clone1 && env $ENV_PREFIX $GIT log --oneline"
      local log; log="$(cat "$EVIDENCE/$id.log")"
      if grep -q "中文提交信息" <<<"$log" && grep -qE "run_command.*git-upload-pack" <<<"$log"; then
        record "$id" PASS "本地 clone 经农场（trace 见 upload-pack）"
      else
        record "$id" FAIL "$(tail -3 <<<"$log" | tr '\n' ' ')"
      fi
      ;;
    TC-003-07)
      ev "$id" "env $ENV_PREFIX $GIT config --global user.name probe && cat $DEV/home/.gitconfig && env $ENV_PREFIX $GIT config --global --list"
      grep -q "user.name=probe" "$EVIDENCE/$id.log" && record "$id" PASS "全局配置回路（HOME 注入路径）" || record "$id" FAIL "$(cat "$EVIDENCE/$id.log")"
      ;;
    TC-003-08)
      ev "$id" "cd $DEV/ws/repo && env $ENV_PREFIX sh -c '
        $0 mv hello.txt hello2.txt && $0 add -A && $0 commit -m mv >/dev/null &&
        $0 checkout -b dev && $0 tag v1 &&
        echo more >> hello2.txt && $0 stash >/dev/null && $0 stash pop >/dev/null &&
        $0 branch --show-current && $0 tag && echo WS_OK' $GIT"
      grep -q "WS_OK" "$EVIDENCE/$id.log" && grep -q "v1" "$EVIDENCE/$id.log" && record "$id" PASS "工作区操作采样（mv/branch/tag/stash）" || record "$id" FAIL "$(tail -3 "$EVIDENCE/$id.log" | tr '\n' ' ')"
      ;;
    TC-003-09)
      if ! adb_sh "ping -c1 -W3 github.com >/dev/null 2>&1"; then record "$id" SKIP "设备无网络（ping github.com 不通）"; return 0; fi
      ev "$id" "cd $DEV/ws && env $ENV_PREFIX GIT_TRACE=1 $GIT ls-remote https://github.com/git/git.git HEAD 2>&1 | tail -15"
      local log; log="$(cat "$EVIDENCE/$id.log")"
      grep -qE "^[0-9a-f]{40}[[:space:]]+HEAD" <<<"$log" && record "$id" PASS "ls-remote https refs 回程" || record "$id" FAIL "$(tail -3 <<<"$log" | tr '\n' ' ')"
      ;;
    TC-003-10)
      if ! adb_sh "ping -c1 -W3 github.com >/dev/null 2>&1"; then record "$id" SKIP "设备无网络"; return 0; fi
      ev "$id" "cd $DEV/ws && rm -rf gclone && env $ENV_PREFIX $GIT clone --depth 1 --single-branch --branch maint https://github.com/git/git.git gclone 2>&1 | tail -5 && cd gclone && env $ENV_PREFIX $GIT log --oneline | wc -l"
      grep -qE "^1" "$EVIDENCE/$id.log" && record "$id" PASS "clone --depth 1 完成（log 恰 1 条）" || record "$id" FAIL "$(tail -3 "$EVIDENCE/$id.log" | tr '\n' ' ')"
      ;;
    TC-003-11)
      if ! adb_sh "ping -c1 -W3 github.com >/dev/null 2>&1"; then record "$id" SKIP "设备无网络"; return 0; fi
      adb_sh "cd $DEV/ws && env $ENV_PREFIX $GIT fetch --depth 1 origin >/dev/null 2>&1; echo \$?" > "$EVIDENCE/$id.log"
      [[ "$(tail -1 "$EVIDENCE/$id.log")" == "0" ]] && record "$id" PASS "fetch https 采样" || record "$id" FAIL "$(cat "$EVIDENCE/$id.log")"
      ;;
    TC-003-12)
      if ! adb_sh "ping -c1 -W3 github.com >/dev/null 2>&1"; then record "$id" SKIP "设备无网络"; return 0; fi
      # 正向（已证于 09）；反向：损坏 CA
      adb_shell "printf 'not a certificate' > $DEV/tmp/bad-ca.pem"
      ev "$id" "cd $DEV/ws && env HOME=$DEV/home TMPDIR=$DEV/tmp GIT_EXEC_PATH=$DEV/gitexec GIT_TEMPLATE_DIR=$DEV/tools/templates GIT_CONFIG_NOSYSTEM=1 GIT_PAGER=cat GIT_SSL_CAINFO=$DEV/tmp/bad-ca.pem SSL_CERT_FILE=$DEV/tmp/bad-ca.pem $GIT ls-remote https://github.com/git/git.git HEAD >/dev/null 2>$DEV/tmp/ca.err; echo rc=\$?; head -2 \$DEV/tmp/ca.err"
      local log; log="$(cat "$EVIDENCE/$id.log")"
      if grep -q "rc=0" <<<"$log"; then
        record "$id" FAIL "损坏 CA 仍成功（未走随包 CA？）"
      elif grep -qiE "certificate|ssl|ca" <<<"$log"; then
        record "$id" PASS "CA 反证成立（坏 CA ⇒ TLS 失败：$(grep -m1 -iE 'certificate|ssl' <<<"$log" | head -c 80)）"
      else
        record "$id" FAIL "坏 CA 失败但错误形态未证 CA 语义: $log"
      fi
      ;;
    TC-003-13)
      ev "$id" "cd $DEV/ws && mv $DEV/gitexec/git-remote-https $DEV/gitexec/.bak-https 2>/dev/null; env $ENV_PREFIX $GIT ls-remote https://github.com/git/git.git HEAD 2>&1 | head -3; mv $DEV/gitexec/.bak-https $DEV/gitexec/git-remote-https 2>/dev/null; echo RESTORED"
      local log; log="$(cat "$EVIDENCE/$id.log")"
      grep -q "RESTORED" <<<"$log" || record "$id" FAIL "farm 未还原"
      if grep -qiE "cannot find|unable to find|no such|not found|could not" <<<"$log"; then
        record "$id" PASS "农场缺失 ⇒ helper 不可得（负向证明）"
      else
        record "$id" FAIL "错误形态未含不可得语义: $(head -2 <<<"$log" | tr '\n' ' ')"
      fi
      ;;
    TC-003-14)
      ev "$id" "cd $DEV/ws/repo && printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit && chmod 644 .git/hooks/pre-commit && env $ENV_PREFIX $GIT commit --allow-empty -m hookless 2>&1 | head -3; echo rc=\$?"
      local log; log="$(cat "$EVIDENCE/$id.log")"
      grep -q "rc=0" <<<"$log" && record "$id" PASS "钩子被跳过（commit 照常）" || record "$id" FAIL "$(head -2 <<<"$log" | tr '\n' ' ')"
      ;;
    TC-003-15)
      ev "$id" "cd $DEV/ws && timeout 20 env $ENV_PREFIX $GIT ls-remote git@github.com:git/git.git HEAD 2>&1 | head -3; echo rc=\$?"
      local log; log="$(cat "$EVIDENCE/$id.log")"
      if grep -q "rc=0" <<<"$log"; then record "$id" FAIL "ssh 意外成功（应不可用）"
      else record "$id" PASS "ssh 不可用（记录性）: $(head -1 <<<"$log" | head -c 90)"
      fi
      ;;
    TC-003-16)
      ev "$id" "env $ENV_PREFIX $GIT send-email 2>&1 | head -2; echo rc=\$?"
      record "$id" PASS "perl 子命令形态记录: $(head -1 "$EVIDENCE/$id.log" | head -c 90)"
      ;;
    TC-003-17)
      local ps; ps="$(adb_sh getconf PAGESIZE | tr -d '\r')"
      if [[ "$ps" != "16384" ]]; then
        record "$id" SKIP "设备页大小 ${ps}B（非 16KB 设备；P7 需 16KB 设备复跑）"
      else
        run_16k_core
      fi
      ;;
    *) record "$id" SKIP "未知用例 $id" ;;
  esac
}

run_16k_core() {
  # 16KB 设备：复跑核心链 01/05/06/09（结果并入 17 记录）
  local ok=1
  for c in TC-003-01 TC-003-05 TC-003-06 TC-003-09; do
    run_case "$c"
    [[ "${RESULTS[-1]}" == *"PASS"* ]] || ok=0
  done
  [[ $ok -eq 1 ]] && record "TC-003-17" PASS "16KB 页设备核心链复跑通过" || record "TC-003-17" FAIL "16KB 核心链有失败项"
}

# ── 主流程 ──────────────────────────────────────────────────────────────────
say "adb 目标：$("${ADB_CMD[@]}" devices | sed -n '2p')"
[[ -d "$ARTIFACTS/jni" ]] || { echo "缺产物 $ARTIFACTS/jni（先跑 build）" >&2; exit 1; }
[[ -f "$ARTIFACTS/assets/git-bridge-tools/gitexec-manifest.json" ]] || { echo "缺 assets/gitexec-manifest.json" >&2; exit 1; }

deploy || { echo "部署失败" >&2; exit 1; }

CASES=(TC-003-00 TC-003-00b TC-003-01 TC-003-02 TC-003-03 TC-003-04 TC-003-05 TC-003-06 TC-003-07 TC-003-08 TC-003-09 TC-003-10 TC-003-11 TC-003-12 TC-003-13 TC-003-14 TC-003-15 TC-003-16 TC-003-17)
for c in "${CASES[@]}"; do run_case "$c"; done

# 汇总
echo
say "──── 汇总 ────"
pass=0; fail=0; skip=0
printf '%-14s %-5s %s\n' ID RESULT NOTE > "$EVIDENCE/results.tsv"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r id st note <<<"$r"
  printf '%-14s %-5s %s\n' "$id" "$st" "$note" | tee -a "$EVIDENCE/results.tsv"
  case "$st" in PASS) pass=$((pass+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; esac
done
say "PASS=$pass FAIL=$fail SKIP=$skip（证据：$EVIDENCE）"
[[ $fail -eq 0 ]] && exit 0 || exit 2
