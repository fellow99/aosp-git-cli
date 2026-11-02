#!/usr/bin/env node
/*
 * scripts/fetch-git-cli-source.mjs —— 取构建输入（git 官方源码包 + 静态依赖，不改源）
 *
 * 计划输出目录（默认 .dist/src）：
 *   <out>/git/                 git-<ver> 解压后的源码树
 *   <out>/zlib/  <out>/curl/  <out>/openssl/   静态依赖源码（版本随 lock 固定）
 *
 * 源码不改（工作区纪律：fetch 不打补丁；Android 缺项以 NO_* 配置关闭）。
 *
 * 用法（规划接口，M1 实现）：
 *   node scripts/fetch-git-cli-source.mjs --git 2.51.0 --out .dist/src
 *
 * 状态：000-scaffold 只固化接口与纪律；下载/解压/校验逻辑在 M1 落地。
 *
 * 退出码：0 成功 · 2 SCAFFOLD 未实现 · 1 用法/IO/下载错误
 */

import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
function argOf(name, fallback = null) {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
}

function usage() {
  process.stderr.write(
    [
      '用法: node scripts/fetch-git-cli-source.mjs --git <git 版本> [--out <dir>] [--deps <锁定的依赖版本表>]',
      '  --git   git 上游版本（= CLI_VERSION）',
      '  --out   输出目录（默认 .dist/src）',
    ].join('\n') + '\n',
  );
}

const gitver = argOf('--git');
const out = argOf('--out') ?? path.join(ROOT, '.dist', 'src');

if (args.includes('--help') || !gitver) {
  usage();
  process.exit(gitver ? 0 : 1);
}

process.stderr.write(
  [
    `[fetch] SCAFFOLD: 下载/解压/SHA-256 校验逻辑在 M1 实现（000-scaffold 只固化接口）。`,
    `[fetch] 计划输入: git-${gitver} @ https://github.com/git/git/releases + zlib/curl/openssl（版本随 lock）`,
    `[fetch] 计划输出: ${out}/`,
  ].join('\n') + '\n',
);
process.exit(2);
