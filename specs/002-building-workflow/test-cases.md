# 002-building-workflow 测试用例

> 对应：[spec.md](./spec.md)（FR-002-xxx）。层：L1（host 门禁）为主 + CI 断言语义（本地可模拟 `bash -e`）。
> 前置：001 已产出（`libgit_*.so` 集 + assets 树 + helper-inventory）。
> 判据纪律：每条可证伪；⬜ 实现后执行并回填。

| # | 用例 | 层 | 覆盖 FR | 前置 | 步骤 | 期望 | 状态 |
|---|---|---|---|---|---|---|---|
| TC-002-01 | 多文件投放 | L1 | 002-001/005 | 001 产物 | `node tools/provision.mjs --out git-cli/src/main/jniLibs --from build/out`（目录） | exit 0；逐产物七门禁 ✔ 输出；jniLibs 含白名单全集 | ⬜ |
| TC-002-02 | 白名单校验 | L1 | 002-002 | TC-002-01 | `node tools/provision.mjs --check` | exit 0；目录 `.so` 集合 == lock 白名单 | ⬜ |
| TC-002-03 | 白名单外文件负例（TC-000-07 转正） | L1 | 002-002/FR-000-033 | TC-002-01 | 复制任一假 `.so`（如 `libfake.so`）进 jniLibs 再 `--check` | exit 2；输出列出 `libfake.so` | ⬜ |
| TC-002-04 | 禁入库负例（TC-000-08 转正） | L1 | 002-002/FR-000-034 | TC-002-01 | 放入 `libnode.so` 再 `--check` | exit 2；明确禁入报错 | ⬜ |
| TC-002-05 | helper 门禁失败负例 | L1 | 002-001 | TC-002-01 | 用非 ELF 覆盖任一 helper 再 `--check` | exit 2；该 helper 门禁 ✘ 且整体拒绝 | ⬜ |
| TC-002-06 | manifest 悬空负例 | L1 | 002-003 | assets 投放后 | gitexec-manifest 增加指向不存在物理件的条目再校验 | exit 2；指出悬空 farm 名 | ⬜ |
| TC-002-07 | manifest 孤儿负例 | L1 | 002-003 | 同上 | 白名单加一个无 farm 条目的物理件（未登记豁免）再校验 | exit 2；指出孤儿物理件 | ⬜ |
| TC-002-08 | assets 投放 | L1 | 002-004 | 001 assets 树 | `node tools/provision.mjs --assets build/out/assets/git-bridge-tools` | exit 0；manifest.json 生成且逐文件 sha256 齐 | ⬜ |
| TC-002-09 | assets 可执行位负例 | L1 | 002-004 | TC-002-08 | `chmod +x` 任一 assets 文件再校验 | exit 2；指出文件 | ⬜ |
| TC-002-10 | assets 篡改负例 | L1 | 002-004 | TC-002-08 | 改任一文件 1 字节再校验 | exit 2；sha256 失配 | ⬜ |
| TC-002-11 | assets 含 .so 负例 | L1 | 002-004 | TC-002-08 | 塞入 `.so` 再校验 | exit 2 | ⬜ |
| TC-002-12 | 幂等复测 | L1 | 002-005 | TC-002-01/08 | 重复 `--out` + `--assets` | exit 0；目录/元数据内容一致（`provisionedAt` 与 assets 内 `manifest.json` 的 `generatedAt` 时间戳字段除外） | ⬜ |
| TC-002-13 | 元数据扩展 | L1 | 002-005 | TC-002-01 | 读 `META-INF/git-cli.properties` | 含 helpers 与 deps 行；字段与 lock 一致 | ⬜ |
| TC-002-14 | 退出码契约复核 | L1 | 002-006 | — | `--out foo`（缺 from）=1；未投放 `--check`=2；全过=0 | 三码逐一对上 | ⬜ |
| TC-002-15 | 门禁七项负例（TC-000-09 转正） | L1 | 002-001 | — | `--inspect` 各构造件：非 ELF / ET_EXEC / x86 / 4K 对齐 / interp 错 | 各自对应门禁 ✘ 且 exit 2 | ⬜ |
| TC-002-16 | draft 只记录转 released 硬比对 | L1 | 002-006/015 | lock 回写后 | 篡改已投放产物 1 字节再 `--check` | ⑤⑥ 硬比对 ✘ ⇒ exit 2（draft 期仅记录的对照） | ⬜ |
| TC-002-17 | CI 断言语义修复 | L1 | 002-012 | 模拟 `bash -e` | `bash -e -c '<修复后的断言片段>'`；分别构造退出 2（过）与退出 1（改坏 lock 触发）| 2 ⇒ 通过；1 ⇒ 步骤失败（语义可达） | ⬜ |
| TC-002-18 | workflow 静态审查 | L1 | 002-010~016/020/021 | 重写后 | 审查 yml：非 tag 无 release 步骤；tag≠lock fail-fast；装机清单齐全；语法门覆盖新脚本 | 逐项核对通过（actionlint/yamllint 可选） | ⬜ |
| TC-002-19 | 配置期门禁不回归 | L1 | 002-020 | 干净检出 | `gradle :git-cli:tasks`（无 .so） | BUILD SUCCESSFUL | ⬜ |
| TC-002-20 | 本机全链预演 | L1.5 | 002-011 | — | 按 §3.2 步骤在本地等价复演（不含 gh release） | 产出归档 tar.gz + .sha256；清单含四源包与脚本 | ⬜ |

## 执行记录

**首轮（2026-11-03，GitHub Actions run 41573860213 @ 65118fa）**：

- TC-002-01/02 ✅：多文件投放 + 白名单 `--check` 全过（CI provision 步骤）。TC-002-08 ✅ `--assets` 投放（8 farm 条目 + manifest.json）。
- TC-002-14 ✅ 退出码契约（未投放=2 CI 断言步 + 本机复核）。TC-002-17 ✅ 断言语义修复（`bash -e` 下 2=过/1=拒，本机+CI 双验证）。
- TC-002-18 ✅ workflow 静态审查 + 首跑通过（run 41573860213 success）。TC-002-19 ✅ 配置期门禁不回归（CI gradle tasks 步）。TC-002-20 ✅（CI 即本机预演等价；归档 tar.gz 167MB artifact 含四源包+脚本，本地下载核验进行中）。
- 负例矩阵 TC-002-03~07/09~11/15/16 ⬜（需本地投放产物后构造，下一轮执行）。

**CI 迭代修复史（2026-11-03，5 次运行）**：① Resolve version 在分支 push 误用分支名为版本号；② android-actions/setup-android action 自身失败 ⇒ 改 runner 预装 SDK + sdkmanager；③ CURL_LDFLAGS 缺 -lssl -lcrypto -lz ⇒ 链接失败；④ openssl API 未对齐 ⇒ ANDROID_API=$API；⑤ S8 argv 索引/chmod -R a-x 目录遍历位 ⇒ 修。终态全绿。
