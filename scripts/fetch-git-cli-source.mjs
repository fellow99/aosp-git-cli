#!/usr/bin/env node
/*
 * scripts/fetch-git-cli-source.mjs —— 取构建输入（git 官方源码包 + 静态依赖 + CA，不改源）
 *
 * 五输入钉选（PINS）：官方出处 + 版本 + SHA-256，全部内置；不引入表外源（C1/FR-001-006）。
 *   git     kernel.org（git 官方分发源；GitHub Releases 同源）        ⬅ 2026-11-03 钉选（2.56.0 = 当时最新稳定版，回写规划 §4.1/lock）
 *   zlib    zlib.net 不可达时用维护者官方仓库 madler/zlib Releases（1.3.1 官方包，sha256 与 zlib.net 公布值一致）
 *   openssl OpenSSL 官方 GitHub Releases（3.5.x LTS 线，避开 4.x 新线）
 *   curl    curl.se 官方下载
 *   cacert  curl.se/ca（Mozilla CA bundle；Last-Modified = 钉选日期）
 *
 * 源码不改（工作区纪律：fetch 不打补丁；Android 缺项以 NO_* 配置关闭）。
 * 幂等：缓存命中且哈希一致跳过下载；解压前清旧目录（FR-001-003/004）。
 * lock 回写：builtFrom.source/deps 升级为结构化版本表（FR-001-005，规划 §8；--no-lock-write 关闭）。
 *
 * 用法：
 *   node scripts/fetch-git-cli-source.mjs [--git <ver>] [--out <dir>] [--dl <dir>] [--no-lock-write]
 *   （--git 缺省 = PINS.git.version；表外版本 ⇒ exit 2，FR-001-006）
 *
 * 退出码：0 成功 · 2 哈希校验失败 / 版本不在钉选表 · 1 用法/IO 错误
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// ── PINS：五输入钉选表（sha256 = 2026-11-03 官方包一手实测，下载后与公布值核对）──
const PINS = {
  git: {
    version: '2.56.0',
    url: (v) => `https://www.kernel.org/pub/software/scm/git/git-${v}.tar.gz`,
    file: (v) => `git-${v}.tar.gz`,
    sha256: '826817fd3671b8565586d6d49f688298de8354ab11db829c02720e5c74b9b39f',
  },
  zlib: {
    version: '1.3.1',
    url: () => 'https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz',
    file: () => 'zlib-1.3.1.tar.gz',
    sha256: '9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23',
  },
  openssl: {
    version: '3.5.9',
    url: () => 'https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz',
    file: () => 'openssl-3.5.9.tar.gz',
    sha256: '603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a',
  },
  curl: {
    version: '8.23.0',
    url: () => 'https://curl.se/download/curl-8.23.0.tar.xz',
    file: () => 'curl-8.23.0.tar.xz',
    sha256: '8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5',
  },
  cacert: {
    // Last-Modified 2026-10-20（curl.se/ca 稳定 URL；日期即版本）
    version: '2026-10-20',
    url: () => 'https://curl.se/ca/cacert.pem',
    file: () => 'cacert.pem',
    sha256: '796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe',
  },
};

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
function argOf(name, fallback = null) {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
}

function say(msg) {
  process.stdout.write(`[fetch] ${msg}\n`);
}
function die(code, msg) {
  process.stderr.write(`[fetch] ${msg}\n`);
  process.exit(code);
}

function usage() {
  process.stderr.write(
    [
      '用法: node scripts/fetch-git-cli-source.mjs [--git <ver>] [--out <dir>] [--dl <dir>] [--no-lock-write]',
      '  --git           git 上游版本（缺省 = PINS 钉选 2.56.0；表外版本拒绝）',
      '  --out           源码输出目录（默认 .dist/src）',
      '  --dl            下载缓存目录（默认 .dist/dl）',
      '  --no-lock-write 不回写 git-cli.lock.json 的 builtFrom 版本表',
    ].join('\n') + '\n',
  );
}

// ── 下载/校验/解压 ───────────────────────────────────────────────────────────

function sha256Of(file) {
  return new Promise((resolve, reject) => {
    const h = crypto.createHash('sha256');
    const s = fs.createReadStream(file);
    s.on('data', (d) => h.update(d));
    s.on('end', () => resolve(h.digest('hex')));
    s.on('error', reject);
  });
}

async function ensureDownload(name, pin, dlDir) {
  const target = path.join(dlDir, pin.file(name === 'git' ? pin.version : undefined));
  if (fs.existsSync(target)) {
    const got = await sha256Of(target);
    if (got === pin.sha256) {
      say(`✔ ${name}: 缓存命中（sha256 一致，跳过下载）`);
      return target;
    }
    say(`⚠ ${name}: 缓存损坏（sha256 不一致），删除重下`);
    fs.rmSync(target);
  }
  const url = pin.url(name === 'git' ? pin.version : undefined);
  say(`↓ ${name}: ${url}`);
  // node 内置 fetch 流式落盘
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) die(1, `${name} 下载失败 HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(target, buf);
  const got = await sha256Of(target);
  if (got !== pin.sha256) {
    fs.rmSync(target);
    die(2, `${name} sha256 校验失败：got=${got} want=${pin.sha256}（缓存已删；请核对官方公布值）`);
  }
  say(`✔ ${name}: sha256 一致`);
  return target;
}

// Windows 盘符路径 → MSYS POSIX 形式（D:\x → /d/x）；MSYS tar 对反斜杠/盘符冒号敏感
function toPosix(p) {
  const m = /^([A-Za-z]):[\\/](.*)$/.exec(p);
  if (!m) return p.replaceAll('\\', '/');
  return `/${m[1].toLowerCase()}/${m[2].replaceAll('\\', '/')}`;
}

function extract(archive, destDir) {
  fs.rmSync(destDir, { recursive: true, force: true });
  fs.mkdirSync(destDir, { recursive: true });
  // 用系统 tar 解压（git-bash / CI 均自带）；--strip-components=1 去顶层目录；路径统一 POSIX
  execFileSync('tar', ['-xf', toPosix(archive), '-C', toPosix(destDir), '--strip-components=1'], { stdio: 'pipe' });
}

// ── lock 回写（builtFrom 版本表，FR-001-005）────────────────────────────────

function writeLock(gitVersion) {
  const lockPath = path.join(ROOT, 'git-cli.lock.json');
  const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
  const rel = lock.releases.find((x) => x.version === gitVersion);
  if (!rel) return false; // 版本条目由人工/CI 建（fetch 不新增 release 条目）
  rel.builtFrom.source = {
    version: gitVersion,
    url: PINS.git.url(gitVersion),
    sha256: PINS.git.sha256,
    note: 'unmodified official tarball (kernel.org); NDK cross-compile',
  };
  rel.builtFrom.deps = {
    zlib: { version: PINS.zlib.version, sha256: PINS.zlib.sha256, url: 'https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz (official; sha256 matches zlib.net)' },
    openssl: { version: PINS.openssl.version, sha256: PINS.openssl.sha256, url: PINS.openssl.url() },
    curl: { version: PINS.curl.version, sha256: PINS.curl.sha256, url: PINS.curl.url() },
  };
  rel.builtFrom.assets = `git templates (source tree) + cacert.pem ${PINS.cacert.version} (sha256 ${PINS.cacert.sha256}) + gitexec-manifest.json`;
  fs.writeFileSync(lockPath, JSON.stringify(lock, null, 2) + '\n');
  say(`✔ lock.builtFrom 版本表已回写（${lockPath}）`);
  return true;
}

// ── 主流程 ──────────────────────────────────────────────────────────────────

async function main() {
  const gitVersion = argOf('--git', PINS.git.version);
  if (has('--help') || has('-h')) {
    usage();
    process.exit(0);
  }
  if (gitVersion !== PINS.git.version) {
    die(2, `git ${gitVersion} 不在钉选表（当前仅 ${PINS.git.version}；升级 = 改 PINS + sha256 实测 + lock，C2/C8）`);
  }
  const out = path.resolve(ROOT, argOf('--out', path.join('.dist', 'src')));
  const dlDir = path.resolve(ROOT, argOf('--dl', path.join('.dist', 'dl')));
  fs.mkdirSync(out, { recursive: true });
  fs.mkdirSync(dlDir, { recursive: true });

  const archives = {};
  for (const name of ['git', 'zlib', 'openssl', 'curl', 'cacert']) {
    archives[name] = await ensureDownload(name, PINS[name], dlDir);
  }

  for (const name of ['git', 'zlib', 'openssl', 'curl']) {
    const dest = path.join(out, name);
    extract(archives[name], dest);
    say(`✔ ${name}: 解压 → ${dest}`);
  }
  fs.copyFileSync(archives.cacert, path.join(out, 'cacert.pem'));
  say(`✔ cacert.pem → ${out}/cacert.pem`);

  // 树存在性自检（FR-001-004）
  const expect = {
    git: ['Makefile', 'GIT-VERSION-GEN', 'templates'],
    zlib: ['configure', 'zlib.h'],
    openssl: ['Configure', 'VERSION.dat'],
    curl: ['configure', 'lib/easy.c'],
  };
  for (const [name, files] of Object.entries(expect)) {
    for (const f of files) {
      if (!fs.existsSync(path.join(out, name, f))) die(1, `${name} 解压后缺 ${f}`);
    }
  }
  say('✔ 源码树自检通过');

  // FETCH-METADATA.json（FR-001-034 取侧）
  const meta = {
    fetchedAt: new Date().toISOString(),
    inputs: ['git', 'zlib', 'openssl', 'curl', 'cacert'].map((n) => ({
      name: n,
      version: n === 'git' ? gitVersion : PINS[n].version,
      url: PINS[n].url(n === 'git' ? gitVersion : undefined),
      sha256: PINS[n].sha256,
    })),
  };
  fs.writeFileSync(path.join(ROOT, '.dist', 'FETCH-METADATA.json'), JSON.stringify(meta, null, 2) + '\n');
  say('✔ FETCH-METADATA.json 已写（.dist/）');

  if (!has('--no-lock-write')) writeLock(gitVersion);
  say('完成：五输入就绪（.dist/src），可运行 scripts/build-git-cli-android.sh');
}

main().catch((e) => die(1, e.message));
