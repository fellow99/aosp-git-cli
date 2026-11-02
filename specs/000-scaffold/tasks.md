# 000-scaffold 任务拆解

> 对应：[spec.md](./spec.md)。原则：骨架完整、简单编译通过；真实交叉编译属 M1。

- [x] T1 Gradle 骨架（settings/toml/properties/local.example/publish/模块 build，
      **useLegacyPackaging=true**，CLI_VERSION=2.51.0 draft）
- [x] T2 `git-cli.lock.json`（draft；builtFrom.deps 登记静态依赖计划）
- [x] T3 `tools/provision.mjs`（exec profile 同款；禁入 libnode.so；META-INF/git-cli.properties）
- [x] T4 脚本骨架：`fetch-git-cli-source.mjs` / `build-git-cli-android.sh`（NO_* 纪律 + 静态依赖注释）
- [x] T5 scaffold CI（配置期门禁 + 自检）
- [x] T6 `.gitignore` / THIRD-PARTY（**GPLv2 对应源码义务**）/ README 中英 / docs/000
- [x] T7 specs（三件套）
- [x] T8 验证（assembleDebug + provision 退出码 + 语法门）+ 提交（父工程不提交）
- [ ] T9 残留收口（2026-11-02 立项，规划 §10.2 模块 000 行）：
      ① NC-1 定稿——`gates` 语义 =「门禁结论存档」，draft 初值全部改 `false`（未实测不当事实，C6），
        lock 增加 `$comment` 说明；provision 维持不读取（每次解析产物为准）；
      ② provision.mjs 兜底 allowedNeeded 对齐 lock（补 `liblog.so`，消除 STRUCTURE §5-3 漂移）；
      ③ 残留清理：`gradle.properties` `VERSION_NAME`（无读取方）、provision.mjs `pairedRuntime`（pty 线残留）；
      ④ 负例用例 TC-000-07~10 执行（依赖 001 产物，随 001/002 开发完成后跑）；
      ⑤ 000-scaffold/plan.md §7 NC-1 关闭回写。
      （②③ 代码变更归本模块；CI 退出码断言修复归 002 模块 M1-T6，不在 T9 内）
