#!/usr/bin/env node
/*
 * tools/provision.mjs —— git-cli 投放与 ELF 门禁（exec 型 profile；多文件版）
 *
 * 唯一事实源是仓库根的 `git-cli.lock.json`（版本 + 大小 + SHA-256 + 门禁 + 出处 + 白名单）。
 * 二进制不入库：本工具把构建产物幂等投放进模块 jniLibs / assets。
 *
 * 门禁是 **exec 型 profile**（与 dlopen 库门禁的三处相反/差异，provision 文件头沿用）：
 *   1. PT_INTERP：exec 型必须恰有 1 个，且内容 = /system/bin/linker64；
 *   2. DT_NEEDED 白名单：只允许系统库 + lock matrix.allowedNeeded；
 *   3. 无 NAPI 门禁；4. useLegacyPackaging=true（物理落盘 nativeLibraryDir）。
 *
 * 命令面（002-building-workflow 扩展后）：
 *   node tools/provision.mjs --check                          # 校验 jniLibs 全部 .so（白名单集合相等）
 *                                                             #   + gitexec-manifest 一致性 + assets 纯数据（若已投放）
 *   node tools/provision.mjs --out <dir> --from <dir|file>    # 投放：--from 目录 = libgit_*.so 全集（按白名单）；
 *                                                             #   --from 单文件 = 仅主二进制（旧用法兼容）
 *   node tools/provision.mjs --assets <dir>                   # 校验并投放 assets 树（纯数据 + manifest.json sha256）
 *   node tools/provision.mjs --inspect <file>                 # 对任意文件跑七门禁
 *   node tools/provision.mjs --version 2.56.0 --abi arm64-v8a ...
 *
 * 退出码：0 全过 · 2 门禁不合格/未投放 · 1 用法/IO 错误
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// ── 仓库级常量（每仓一份 provision，仅此块不同）─────────────────────────────
const LOCK_FILE = 'git-cli.lock.json';
const MODULE_DIR = 'git-cli';
const RES_PROPERTIES = 'git-cli.properties';
const DEFAULT_BINARY = 'libgit_cli.so';
const ASSETS_DIR_NAME = 'git-bridge-tools';   // AAR 内 assets/<此名>/
const GITEXEC_MANIFEST = 'gitexec-manifest.json';
const ASSETS_MANIFEST = 'manifest.json';
// 绝不进入本 AAR 的文件（node-runtime 统一供给；同名库重复会造成包内冲突）。
const BANNED_IN_AAR = ['libnode.so'];
// ───────────────────────────────────────────────────────────────────────────

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LOCK_PATH = path.join(ROOT, LOCK_FILE);
const MODULE_JNILIBS = path.join(MODULE_DIR, 'src', 'main', 'jniLibs');
const MODULE_ASSETS = path.join(MODULE_DIR, 'src', 'main', 'assets', ASSETS_DIR_NAME);

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
function argOf(name, fallback = null) {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
}

function say(msg) {
  process.stdout.write(`[provision] ${msg}\n`);
}

// ── 极简 ELF64（小端）解析：只回答门禁需要的问题 ─────────────────────────────

function parseElf(buf) {
  if (buf.length < 64 || buf.readUInt32BE(0) !== 0x7f454c46) throw new Error('不是 ELF 文件');
  const little = buf[5] === 1;
  if (!little) throw new Error('只支持小端 ELF（AArch64 一定是小端）');
  const u16 = (o) => buf.readUInt16LE(o);
  const u32 = (o) => buf.readUInt32LE(o);
  const u64 = (o) => Number(buf.readBigUInt64LE(o));

  const eType = u16(16);
  const eMachine = u16(18);
  const ePhoff = u64(32);
  const ePhentsize = u16(54);
  const ePhnum = u16(56);
  const eShoff = u64(40);
  const eShentsize = u16(58);
  const eShnum = u16(60);
  const eShstrndx = u16(62);

  let ptInterp = 0;
  let interp = null;
  const loadAligns = [];
  for (let i = 0; i < ePhnum; i++) {
    const o = ePhoff + i * ePhentsize;
    const pType = u32(o);
    const pAlign = u64(o + 48);
    if (pType === 3) {
      ptInterp++;
      const pOffset = u64(o + 8);
      const pFilesz = u64(o + 32);
      interp = buf.toString('utf8', pOffset, pOffset + pFilesz).replace(/\0+$/, '');
    }
    if (pType === 1) loadAligns.push(pAlign);
  }

  const sections = [];
  for (let i = 0; i < eShnum; i++) {
    const o = eShoff + i * eShentsize;
    sections.push({
      nameOff: u32(o),
      type: u32(o + 4),
      offset: u64(o + 24),
      size: u64(o + 32),
    });
  }
  const shstr = sections[eShstrndx];
  const strAt = (base, off) => {
    const s = base + off;
    let e = s;
    while (e < buf.length && buf[e] !== 0) e++;
    return buf.toString('utf8', s, e);
  };
  const byName = new Map();
  for (const s of sections) byName.set(strAt(shstr.offset, s.nameOff), s);

  const dynamic = byName.get('.dynamic');
  const needed = [];
  const soname = [];
  if (dynamic) {
    for (let i = 0; i * 16 < dynamic.size; i++) {
      const o = dynamic.offset + i * 16;
      const tag = Number(buf.readBigInt64LE(o));
      const val = u64(o + 8);
      if (tag === 0) break;
      if (tag === 1 || tag === 14) {
        const nm = strAt(byName.get('.dynstr').offset, val);
        if (tag === 1) needed.push(nm);
        else soname.push(nm);
      }
    }
  }

  return { eType, eMachine, ptInterp, interp, loadAligns, needed, soname };
}

/**
 * 七门禁（exec 型 profile）。
 * relFor：⑤⑥ 的锁值来源 —— 主二进制用 releases[] 条目；helper 用 builtFrom.helpers[文件名]；
 * **⑤⑥ 硬比对仅在 status==='released' 时生效**（宪法 C2：draft→released 单向；
 * draft 期锁值是 CI 钉选的参考值，只记录 + 失配告警——产物不必比特级可复现也不误杀投放）。
 */
function gates(buf, relFor, allowedNeeded, enforceHash) {
  let elf;
  try {
    elf = parseElf(buf);
  } catch (e) {
    return { ok: false, results: [{ id: 'parse', ok: false, detail: e.message }], sha256: null };
  }
  const sha256 = crypto.createHash('sha256').update(buf).digest('hex');
  const minAlign = elf.loadAligns.length ? Math.min(...elf.loadAligns) : 0;
  const expectSha = relFor?.sha256 && relFor.sha256.length === 64 ? relFor.sha256 : null;
  const expectSize = relFor?.size && relFor.size > 0 ? relFor.size : null;
  const r = [];
  const add = (id, ok, detail) => r.push({ id, ok, detail });

  add('① e_type = ET_DYN（PIE 可执行）', elf.eType === 3, `e_type=${elf.eType}`);
  add('② PT_INTERP 恰 1 个且 = /system/bin/linker64',
    elf.ptInterp === 1 && elf.interp === '/system/bin/linker64',
    `PT_INTERP=${elf.ptInterp} interp=${JSON.stringify(elf.interp)}`);
  add('③ e_machine = AArch64', elf.eMachine === 183, `e_machine=${elf.eMachine}`);
  const banned = elf.needed.filter((n) => !allowedNeeded.includes(n));
  add('④ DT_NEEDED 全部在白名单', banned.length === 0,
    `NEEDED=${JSON.stringify(elf.needed)}；白名单外=${banned.length ? JSON.stringify(banned) : '无'}`);
  if (enforceHash && expectSha) add('⑤ SHA-256 与锁一致（released 硬比对）', sha256 === expectSha, `${sha256.slice(0, 16)}… vs ${expectSha.slice(0, 16)}…`);
  else if (expectSha) add('⑤ SHA-256（draft：锁值为 CI 参考值，只记录' + (sha256 === expectSha ? '，一致' : '，⚠ 与锁失配但放行') + ')', true, sha256);
  else add('⑤ SHA-256（draft 无锁值，仅记录）', true, sha256);
  if (enforceHash && expectSize) add('⑥ 大小与锁一致（released 硬比对）', buf.length === expectSize, `${buf.length} vs ${expectSize}`);
  else if (expectSize) add('⑥ 大小（draft：锁值为 CI 参考值，只记录' + (buf.length === expectSize ? '，一致' : '，⚠ 与锁失配但放行') + ')', true, `${buf.length}`);
  else add('⑥ 大小（draft 无锁值，仅记录）', true, `${buf.length}`);
  add('⑦ 16 KB 页对齐', minAlign >= 0x4000, `min LOAD align=0x${minAlign.toString(16)}（小于 0x4000=16KB，16 KB 页设备不合格）`);

  const allow4k = has('--allow-page-align-4k');
  const gateAlign = r.find((x) => x.id.startsWith('⑦'));
  const hardOk = r.every((x) => (allow4k && x === gateAlign ? true : x.ok));
  if (allow4k && gateAlign && !gateAlign.ok) {
    say('⚠ --allow-page-align-4k 放行「16 KB 页对齐」：仅 bring-up，上架/16 KB 设备不合格');
  }
  return { ok: hardOk, results: r, elf, sha256 };
}

function printGates(g) {
  for (const x of g.results) say(`  ${x.ok ? '✔' : '✘'} ${x.id} — ${x.detail}`);
}

// ── assets：纯数据校验 + manifest.json（逐文件 sha256 + 总 sha256）──────────

function walkFiles(dir, base = dir) {
  const out = [];
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) out.push(...walkFiles(p, base));
    else if (ent.isFile()) out.push(path.relative(base, p).replaceAll('\\', '/'));
  }
  return out;
}

function sha256FileSync(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function validateAssetsPure(dir) {
  const problems = [];
  for (const rel of walkFiles(dir)) {
    const p = path.join(dir, rel);
    if (rel.endsWith('.so')) problems.push(`出现 .so：${rel}`);
    const st = fs.lstatSync(p);
    if (st.isSymbolicLink()) problems.push(`symlink 不允许：${rel}（assets 必须纯数据实体文件）`);
    else if (st.mode & 0o111) problems.push(`可执行位：${rel}（mode=${(st.mode & 0o777).toString(8)}）`);
  }
  return problems;
}

function totalChecksum(pairs) {
  // 排序拼接逐行 "<sha256>  <relpath>\n" 再取 sha256
  const text = [...pairs].sort((a, b) => a.path.localeCompare(b.path))
    .map((x) => `${x.sha256}  ${x.path}`).join('\n') + '\n';
  return crypto.createHash('sha256').update(text).digest('hex');
}

// ── gitexec-manifest 一致性（FR-002-003）────────────────────────────────────

function checkGitexecManifest(manifestPath, whitelist, exempt) {
  const problems = [];
  const man = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const farm = man.farm ?? {};
  const physicalUsed = new Set(Object.values(farm));
  for (const [name, phys] of Object.entries(farm)) {
    if (!whitelist.includes(phys)) problems.push(`悬空：farm['${name}'] → '${phys}' 不在 jniLibsWhitelist`);
  }
  for (const phys of whitelist) {
    if (!physicalUsed.has(phys) && !(exempt ?? []).includes(phys)) {
      problems.push(`孤儿：白名单 '${phys}' 无 farm 条目且未登记豁免（matrix.helperExempt）`);
    }
  }
  return { problems, farm };
}

// ── 主流程 ──────────────────────────────────────────────────────────────────

function readLock() {
  if (!fs.existsSync(LOCK_PATH)) throw new Error(`缺 ${LOCK_PATH}`);
  return JSON.parse(fs.readFileSync(LOCK_PATH, 'utf8'));
}

function main() {
  const lock = readLock();
  const allowedNeeded = lock.matrix?.allowedNeeded ?? ['libc.so', 'libm.so', 'libdl.so', 'libz.so', 'liblog.so'];
  const whitelist = lock.matrix?.jniLibsWhitelist ?? null; // null = 回落单文件（000 兼容）
  const exempt = lock.matrix?.helperExempt ?? [];
  const wantVersion = argOf('--version') || lock.active.version;
  const wantAbi = argOf('--abi') || lock.active.abi;
  const rel = lock.releases.find((x) => x.version === wantVersion && x.abi === wantAbi);
  if (!rel) {
    throw new Error(
      `${LOCK_FILE} 里没有记录 version=${wantVersion} abi=${wantAbi}；现有：` +
      lock.releases.map((x) => `${x.version}/${x.abi}`).join(', '),
    );
  }
  const active = { version: rel.version, abi: rel.abi, name: rel.name || DEFAULT_BINARY };

  say(`目标 release：version=${rel.version} abi=${rel.abi}（独立 semver，无配对）`);
  const enforceHash = rel.status === 'released';
  if (rel.status === 'draft') {
    say('⚠ lock 中该 release 为 draft：⑤⑥ 只记录' +
      ((rel.sha256 && rel.sha256.length === 64) || (rel.size && rel.size > 0)
        ? '（锁值 = CI 钉选参考值，失配告警不拦截）；released 后转硬比对'
        : '（无锁值）'));
  }
  if (!whitelist) say('⚠ lock 无 matrix.jniLibsWhitelist：回落 000 单文件口径（仅 ' + active.name + '）');

  // helper 的 ⑤⑥ 锁值来源（draft 期通常为空 → 只记录）
  const relFor = (fileName) => {
    if (fileName === active.name) return rel;
    const h = rel.builtFrom?.helpers?.[fileName];
    return h ? { sha256: h.sha256, size: h.size } : null;
  };

  const inspectPath = argOf('--inspect');
  if (inspectPath) {
    const buf = fs.readFileSync(inspectPath);
    const g = gates(buf, relFor(path.basename(inspectPath)), allowedNeeded, enforceHash);
    printGates(g);
    say(g.ok ? '门禁：全过' : '门禁：不合格');
    process.exit(g.ok ? 0 : 2);
  }

  // ── --assets <dir>：校验并投放 assets 树（FR-002-004）────────────────────
  const assetsArg = argOf('--assets');
  if (assetsArg) {
    const srcDir = path.resolve(assetsArg);
    if (!fs.existsSync(srcDir)) throw new Error(`--assets 目录不存在：${srcDir}`);
    const pure = validateAssetsPure(srcDir);
    if (pure.length) {
      for (const p of pure) say(`✘ assets 纯数据：${p}`);
      say('assets 校验：不合格 ⇒ 拒绝投放');
      process.exit(2);
    }
    say('✔ assets 纯数据（无 .so / 无可执行位）');
    // 生成 manifest.json（排除自身）
    const files = walkFiles(srcDir).filter((f) => f !== ASSETS_MANIFEST);
    const pairs = files.map((f) => ({ path: f, sha256: sha256FileSync(path.join(srcDir, f)) }));
    const manifest = {
      $schema: 'git-bridge-tools-assets/1',
      generatedAt: new Date().toISOString(),
      files: pairs,
      totalSha256: totalChecksum(pairs),
    };
    // 若源目录已有 manifest.json，核对总哈希（防投放旧清单）
    const srcMan = path.join(srcDir, ASSETS_MANIFEST);
    if (fs.existsSync(srcMan)) {
      const prev = JSON.parse(fs.readFileSync(srcMan, 'utf8'));
      if (prev.totalSha256 && prev.totalSha256 !== manifest.totalSha256) {
        say(`⚠ 源 manifest.json 总哈希与实测不一致（源侧旧文件将以外侧为准重生成）`);
      }
    }
    // 投放（幂等：整目录替换，先清后拷）
    fs.rmSync(path.join(ROOT, MODULE_ASSETS), { recursive: true, force: true });
    fs.mkdirSync(path.join(ROOT, MODULE_ASSETS), { recursive: true });
    for (const f of files) {
      const dst = path.join(ROOT, MODULE_ASSETS, f);
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      fs.copyFileSync(path.join(srcDir, f), dst);
    }
    fs.writeFileSync(path.join(ROOT, MODULE_ASSETS, ASSETS_MANIFEST), JSON.stringify(manifest, null, 2) + '\n');
    // 投放后必须仍纯净（.json 无执行位由 chmod 保证）
    for (const f of walkFiles(path.join(ROOT, MODULE_ASSETS))) fs.chmodSync(path.join(ROOT, MODULE_ASSETS, f), 0o644);
    say(`✔ assets 投放：${files.length} 文件 + ${ASSETS_MANIFEST}（total=${manifest.totalSha256.slice(0, 16)}…）`);
    process.exit(0);
  }

  const outDir = argOf('--out');
  const from = argOf('--from');

  if (!outDir) {
    // ── --check：校验已投放产物（多文件白名单 + manifest 一致性 + assets）──
    const abiDir = path.join(ROOT, MODULE_JNILIBS, active.abi);
    if (!fs.existsSync(abiDir)) {
      say(`未投放：${abiDir}（先跑 --out …）`);
      process.exit(2);
    }
    const present = fs.readdirSync(abiDir).filter((f) => f.endsWith('.so'));
    const want = whitelist ?? [active.name];
    const illegal = present.filter((f) => !want.includes(f));
    const missing = want.filter((f) => !present.includes(f));
    say(`${illegal.length === 0 && missing.length === 0 ? '✔' : '✘'} jniLibs 白名单集合比对（在=${JSON.stringify(present)}；须=${JSON.stringify(want)}）`);
    if (illegal.length) for (const f of illegal) say(`✘ 白名单外：${f}`);
    if (missing.length) for (const f of missing) say(`✘ 缺投放：${f}`);

    let ok = illegal.length === 0 && missing.length === 0;
    for (const f of present) {
      if (illegal.includes(f)) continue;
      say(`门禁：${f}`);
      const g = gates(fs.readFileSync(path.join(abiDir, f)), relFor(f), allowedNeeded, enforceHash);
      printGates(g);
      ok = ok && g.ok;
    }
    // 禁入检查（libnode.so 永远拒绝）
    for (const banned of BANNED_IN_AAR) {
      if (fs.existsSync(path.join(abiDir, banned))) {
        say(`✘ ${banned} 禁入本 AAR（node-runtime 统一供给）`);
        ok = false;
      }
    }
    // gitexec-manifest 一致性（assets 已投放时）
    const manPath = path.join(ROOT, MODULE_ASSETS, GITEXEC_MANIFEST);
    if (fs.existsSync(manPath) && whitelist) {
      const { problems } = checkGitexecManifest(manPath, whitelist, exempt);
      if (problems.length) {
        for (const p of problems) say(`✘ manifest 一致性：${p}`);
        ok = false;
      } else {
        say('✔ gitexec-manifest 一致性（引用 ⊆ 白名单；无孤儿）');
      }
    }
    // assets 纯数据复核（已投放时）
    if (fs.existsSync(path.join(ROOT, MODULE_ASSETS))) {
      const pure = validateAssetsPure(path.join(ROOT, MODULE_ASSETS));
      if (pure.length) {
        for (const p of pure) say(`✘ assets 纯数据：${p}`);
        ok = false;
      } else {
        say('✔ assets 纯数据复核');
      }
    }
    say(ok ? '门禁：全过' : '门禁：不合格');
    process.exit(ok ? 0 : 2);
  }

  // ── --out <dir> --from <dir|file>：投放 ──────────────────────────────────
  if (!from) throw new Error(`--out 需要配 --from <目录或 ${DEFAULT_BINARY}>`);
  const fromResolved = path.resolve(from);
  const isDir = fs.statSync(fromResolved).isDirectory();
  const want = whitelist ?? [active.name];
  const sources = []; // {srcFile, name}
  if (isDir) {
    for (const name of want) {
      const p = path.join(fromResolved, name);
      if (!fs.existsSync(p)) {
        say(`✘ 缺白名单产物：${p}（构建侧未产出或白名单漂移）`);
        process.exit(2);
      }
      sources.push({ srcFile: p, name });
    }
  } else {
    sources.push({ srcFile: fromResolved, name: active.name });
  }

  const results = [];
  for (const { srcFile, name } of sources) {
    say(`门禁：${name}`);
    const buf = fs.readFileSync(srcFile);
    const g = gates(buf, relFor(name), allowedNeeded, enforceHash);
    printGates(g);
    results.push({ name, buf, g });
  }
  if (results.some((x) => !x.g.ok)) {
    say('门禁不合格 ⇒ 拒绝投放');
    process.exit(2);
  }

  const destDir = path.resolve(ROOT, outDir, active.abi);
  fs.mkdirSync(destDir, { recursive: true });
  for (const { name, buf, g } of results) {
    fs.writeFileSync(path.join(destDir, name), buf);
    say(`✔ 投放：${path.join(destDir, name)}（sha256=${g.sha256.slice(0, 16)}…）`);
  }
  for (const banned of BANNED_IN_AAR) {
    if (fs.existsSync(path.join(destDir, banned))) {
      throw new Error(`${banned} 不得进入本 AAR（应由配对 runtime 供给，避免包内同名冲突）`);
    }
  }

  // 版本元数据（供 AAR resources 使用；002 扩展 helpers/deps 行）
  const farmEntries = [];
  const manPath = path.join(ROOT, MODULE_ASSETS, GITEXEC_MANIFEST);
  if (fs.existsSync(manPath)) {
    const { farm } = checkGitexecManifest(manPath, whitelist ?? [active.name], exempt);
    for (const [k, v] of Object.entries(farm)) farmEntries.push(`${k}→${v}`);
  }
  const deps = rel.builtFrom?.deps;
  const depsLine = deps && typeof deps === 'object'
    ? Object.entries(deps).map(([k, v]) => `${k}@${v.version}`).join(',')
    : '';
  const resDir = path.join(ROOT, MODULE_DIR, 'src', 'main', 'resources', 'META-INF');
  fs.mkdirSync(resDir, { recursive: true });
  fs.writeFileSync(
    path.join(resDir, RES_PROPERTIES),
    [
      `tool.version=${rel.version}`,
      `abi=${rel.abi}`,
      `name=${active.name}`,
      `size=${results[0].buf.length}`,
      `sha256=${results[0].g.sha256}`,
      ...(farmEntries.length ? [`helpers=${farmEntries.join(',')}`] : []),
      ...(depsLine ? [`deps=${depsLine}`] : []),
      `provisionedAt=${new Date().toISOString()}`,
      '',
    ].join('\n'),
  );
  say('投放完成');
}

try {
  main();
} catch (e) {
  process.stderr.write(`[provision] 失败：${e.message}\n`);
  process.exit(1);
}
