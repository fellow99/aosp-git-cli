# 101-probe-app 任务拆解

> 对应：[spec.md](./spec.md)（FR-101-PROBE-001…011）· [plan.md](./plan.md)（as-built）。
> 本模块**已是实现态**：tasks 记录「已完成建仓/首轮跑批 + 本批构建修齐 + 遗留执行项」，不是规划。

## T1 载体建仓（已闭环，M1-T7 / M2-T1）
- [x] T1.1 独立 Gradle 工程 `probe-app/`（根 `build.gradle.kts` + `settings.gradle.kts` + `app/`），
  不在根 settings 内（000 单模块红线；`probe-app/build.gradle.kts:1-6`）
- [x] T1.2 `app/build.gradle.kts`：仅 arm64 ABI + `useLegacyPackaging=true` + AAR 依赖
  （`app/build.gradle.kts:16, 20-22, 38`）
- [x] T1.3 `MainActivity.java`：物化 / 农场 / env 注入 / exec 包装 / 探针表 / JSON 报告（625 行）
- [x] T1.4 manifest：仅 INTERNET + `extractNativeLibs=true`（`AndroidManifest.xml:4, 8`）

## T2 探针正典映射与设备首跑（已闭环，M2-T2 骨架）
- [x] T2.1 实现 26 条探针（probes()，`MainActivity.java:301-479`）+ runAll 内 TC-003-17
  （`MainActivity.java:596-603`）：TC-003-01…19 + App 域 18a/18b + 链式 05b/08b
- [x] T2.2 2026-11-03 App 域首轮跑批（翻译模拟器）：PASS 22 / FAIL 4 / SKIP 0，结论回填
  `specs/003-cli/test-cases.md` §F（FAIL 4 项均环境限制，真机补测）
- [x] T2.3 端点 SKIP 口径落地：依赖 `git_public_url`/`git_auth_url` extras 用例判据首行即
  `"SKIP:…"` 分支（test-cases.md §二 口径表）

## T3 本批构建修齐（2026-11-06）
- [x] T3.1 下载 Release AAR：`https://github.com/fellow99/aosp-git-cli/releases/download/v2.56.0/`
  `git-cli-v2.56.0-android-arm64-v8a-aar.aar` → `probe-app/app/libs/git-cli-release.aar`
  （6,152,277 B；经代理论证；Release 侧无 `.sha256` 资产）
- [x] T3.2 完整性校验：AAR 内两件 `.so` sha256 对 `git-cli.lock.json` 逐条比对通过
  （libgit_cli 精确一致；libgit_remote_curl 为 lock 登记已知两值之一）——plan §5
- [x] T3.3 构建验证：`gradle :app:assembleDebug --console=plain`（Gradle 9.4.1）BUILD SUCCESSFUL
  （1m24s / 35 tasks）；APK `app/build/outputs/apk/debug/app-debug.apk`（7,416,309 B）
- [x] T3.4 AAR 不入库确认：`probe-app/.gitignore:4` 忽略 `app/libs/*.aar`，git status 应为
  untracked（C3）
- [x] T3.5 本模块 as-built 文档归档（spec.md / plan.md / test-cases.md / tasks.md）+
  `logs/20261105-1/DEV_CHECKLIST.md` + SPECS_CHECKLIST / specs-README 索引更新

## T4 遗留执行项（非文档缺口）
- [ ] T4.1 设备实跑（APK 安装 + `--ez autorun true` + `--es git_public_url/git_auth_url…`）
  ——编排者统一排队；结论回填 test-cases 事实区
- [ ] T4.2 原生 arm64 复测（正式 G3；翻译模拟器结果仅记录；FAIL 4 项复核）
- [ ] T4.3 TC-003-17 16KB 页设备采样（P7，需 16KB 设备）
- [ ] T4.4 探针版本号 C2 化（judge 内嵌 `git version 2.56.0` → lock/PROBE_APP_VERSION 常量统一，
  见 plan §7#1——随换版执行）
- [ ] T4.5 （登记，非本模块处置）Release AAR `manifest.json` 列出 `templates/.gitignore` 但未随包
  ——生产侧 001/002 追踪（plan §7#2）
