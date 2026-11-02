# 003-cli — 模块计划（plan.md，planned → 开发后回写 as-built）

> **模块**：003-cli CLI 运行期验证 · **性质**：技术实现计划（测试 harness 设计 + 用例实现方案）。
> **依据**：[`../constitution.md`](../constitution.md) · [`../../docs/000-工程规划.md`](../../docs/000-工程规划.md)（规划 §7.1 env 表 / §7.2 限制 / §7.3 P1–P7）· 本模块 [`spec.md`](./spec.md)（FR-003-xxx）· [`test-cases.md`](./test-cases.md)（主用例全集）。
> **版本**：v1.0 · 2026-11-02 · 状态：⬜ 未实现。

---

## 1. 技术上下文

| 项 | 值 |
|---|---|
| 载体 | adb（本机 SDK platform-tools）+ arm64 Android：真机（有则连）或模拟器 `python_arm64_api35`（android-35 google_apis arm64-v8a，AVD 已在本机）；正在跑的 `Medium_Phone_API_37.0` 为 x86_64 **不可用**（本仓只发 arm64） |
| 设备工作目录 | `/data/local/tmp/git-cli-probe/`（shell 域可 exec、可建 symlink；探针唯一活动区，FR-003-005） |
| 目录布局 | `bin/`（物化后的 `libgit_*.so` 全集，农场 symlink 也在此层之上）· `gitexec/`（农场）· `home/`（HOME）· `tmp/`（TMPDIR）· `tools/`（物化 assets：templates/cacert.pem/gitexec-manifest.json）· `ws/`（用例工作区） |
| 驱动 | `scripts/test-on-device/run-probes.sh`（bash，宿主侧）：部署/农场/env/用例执行/报告聚合；用例定义于同目录 `cases/`（每个用例一个函数） |
| 证据 | 逐用例 stdout/stderr/exit code 存 `logs/<date>-N/evidence/`（devflow 日志目录），汇总进 TEST_REPORT.md |

### 1.1 与规划 §7.3 探针（P1–P7）的映射

| 探针 | 本模块等价用例 | 差异（诚实口径） |
|---|---|---|
| P1 版本回程 | TC-003-01 | 启动方式 = adb shell 直 exec（非 pty.spawn）；进程生命周期同构（exec 型） |
| P2 本地全链 | TC-003-05/06/08 | 同判据（trace 见 upload-pack 经农场）；中文文件名包含 |
| P3 ls-remote https | TC-003-09 | 同判据 |
| P4 clone --depth 1 | TC-003-10/11 | 同判据 |
| P5 农场 SELinux | TC-003-03/13（间接：行为级）；`ls -Z` 标签记录为证据 | **shell 域标签 ≠ app 域标签**：P5 的 app 域结论仍 ⬜（消费方）；shell 域 symlink exec 放行是本模块 ✅ 可证的 |
| P6 CA 反证 | TC-003-12 | 同判据（正反两向） |
| P7 16KB/中文 | TC-003-05（中文）+ TC-003-00b/17（页大小采样） | 16KB 设备可用性取决于测试机（API 35 模拟器页大小实测后记录） |

---

## 2. harness 设计

### 2.1 run-probes.sh 命令面

```bash
scripts/test-on-device/run-probes.sh --serial <adb serial> --artifacts <build/out> [--case <ID>] [--keep]
  --serial      adb -s 目标（缺省唯一设备）
  --artifacts   001 产物目录（含 libgit_*.so 与 assets/git-bridge-tools/）
  --case        只跑指定用例（缺省全跑）
  --keep        不清理设备工作目录（调试用；默认跑完保留，--clean 显式清）
```

### 2.2 部署流程（FR-003-001/002/003）

```
① adb push <artifacts>/libgit_cli.so 等 → /data/local/tmp/git-cli-probe/bin/（chmod +x）
② adb push assets/git-bridge-tools/* → tools/（templates/ 保持目录结构；纯数据）
③ 农场：读 gitexec-manifest.json，rm -rf gitexec && 逐条 ln -s ../bin/<物理件> gitexec/<农场名>
④ env 文件（device env）：GIT_EXEC_PATH/GIT_TEMPLATE_DIR/GIT_CONFIG_GLOBAL/GIT_CONFIG_NOSYSTEM=1/
   GIT_SSL_CAINFO/SSL_CERT_FILE/PATH=<bin>:<gitexec>:/system/bin/HOME/TMPDIR/GIT_PAGER=cat
⑤ 自检：/data/local/tmp/git-cli-probe/bin/git --version（farm `git` symlink 或直指主件）
```

### 2.3 用例执行框架

- 每用例 = `case_<id>()`：前置检查 → 命令序列（`adb shell cd ws && env … git …`）→ 断言（exit/output/文件态）→ `PASS/FAIL/SKIP + 证据路径`；
- https 用例前置网络探测（`adb shell ping -c1 -W2 github.com || curl HEAD` 失败 ⇒ SKIP 并记录，不误报 FAIL）；
- 每用例独立子工作区 `ws/<id>/`，互不污染；
- 输出：stdout 汇总表 + `results.tsv`（ID/结果/duration/evidence）。

---

## 3. 宪法符合性检查

| 原则 | 判定 | 依据 |
|---|---|---|
| C3 二进制不入库 | ✅ | 探针脚本入库；推送的制品来自本地 build/out（gitignored）；证据进 logs/（不入库或按需归档） |
| C6 未实测标 ⬜ | ✅ | 用例状态初始 ⬜；只有执行后回填 ✅/❌/SKIP + 环境快照；shell 域结论不冒充 app 域 |
| C8 先文档后实现 | ✅ | 本文件 + test-cases.md 先行；结果回写规划 §7.2/§7.3（如钩子行为 R11、中文路径 R4） |
| 发布卫生/门禁/lock | ➖ | 本模块只读消费 001/002 产物，不触碰 |

---

## 4. FR 交叉引用

| FR | 实现落点 | 状态 |
|---|---|---|
| FR-003-001~005 | `scripts/test-on-device/run-probes.sh`（部署/农场/env/框架/活动域限制） | ⬜ |
| FR-003-010~018 | `cases/` 主行为用例（TC-003-01~13） | ⬜ |
| FR-003-030~034 | env 契约用例（TC-003-05 内嵌 + 专项） | ⬜ |
| FR-003-040~044 | 限制事实化用例（TC-003-12/13/14/15） | ⬜ |

---

## 5. 测试计划（设备策略）

1. **设备选择**：`adb devices` 有真机（arm64）⇒ 用真机；否则启动 arm64 AVD（`python_arm64_api35`；
   x86 宿主上 QEMU 全仿真，启动慢属预期）；x86_64 模拟器**不用**（ABI 不符）。
2. **顺序**：L1 门禁全绿（001/002 用例）→ 部署 harness → P1 等价（TC-003-01）先行（最小闭环）→
   本地链 → https 链 → 负例/限制族 → 报告。
3. **失败处理**：MUST 用例 FAIL ⇒ 进入 devflow bugfix 阶段（定位→修复→回归）；设备侧不可复现的
   构建问题回 001。
4. **环境快照**（报告必录）：设备型号/ABI/API/页大小/SELinux 模式/网络方式/制品 sha256/时间。

---

## 6. 待实现清单

- [ ] run-probes.sh（部署/农场/env/框架/报告）
- [ ] cases/：主行为 13 条 + env 契约 + 限制事实化（对照 test-cases.md 全表）
- [ ] arm64 AVD 拉起与设备探测脚本辅助（或文档化手动步骤）
- [ ] 首轮执行 → TEST_REPORT.md + test-cases.md 状态回填 + 规划 §7.2/§7.3 事实回写（R4/R11 等）
