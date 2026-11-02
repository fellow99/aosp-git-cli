# 000-scaffold 测试用例

> 对应：[spec.md](./spec.md)。执行环境：Windows + Gradle 9.4.1 + Temurin 21。

| # | 用例 | 步骤 | 期望 |
|---|---|---|---|
| TC-01 | 干净工程可配置 | `gradle :git-cli:tasks` | BUILD SUCCESSFUL |
| TC-02 | AAR 容器可产出 | `gradle :git-cli:assembleDebug` | aar 产物存在 |
| TC-03 | provision 未投放语义 | `node tools/provision.mjs --check` | 退出码 = 2 |
| TC-04 | 语法门 | `node --check` ×2 + `bash -n` | 全过 |
| TC-05 | 二进制不入库 | `git status --porcelain` | jniLibs/assets 无条目 |

## 执行记录（2026-11-02，scaffold 提交前）

- TC-01/02：✅ `assembleDebug` BUILD SUCCESSFUL（git-cli-debug.aar 产出）。
- TC-03：✅（exit=2，文案含"未投放"）。TC-04：✅（node --check ×2 + bash -n 全过）。
- TC-05：✅。
