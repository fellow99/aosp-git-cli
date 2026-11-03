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
- [x] T9 残留收口（2026-11-03 完成）：① lock `gates` 定稿落地（draft 初值全 false + $comment；首个真实构建 run 41573860213 过门禁后实测回写 true）；② provision 兜底白名单补 `liblog.so`；③ `VERSION_NAME`/`pairedRuntime` 残留清理；⑤ plan.md NC-1 关闭。（④ 负例用例待本地投放产物后执行）
