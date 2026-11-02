# 003-cli 任务拆解

> 对应：[spec.md](./spec.md)（FR-003-xxx）· [plan.md](./plan.md) · [test-cases.md](./test-cases.md)。

- [ ] T1 `scripts/test-on-device/run-probes.sh`：部署（bin/tools）+ 农场创建（manifest 驱动、幂等）+ env 注入（FR-003-001~003）
- [ ] T2 用例执行框架（case 函数注册/独立工作区/PASS-FAIL-SKIP 断言/证据落盘/汇总表，FR-003-004）
- [ ] T3 主行为用例实现：TC-003-01~04（version/仓库全链/工作区采样/退出码）（FR-003-010~012/018）
- [ ] T4 本地传输用例：TC-003-05/06（clone/fetch/push + GIT_TRACE 农场证据）（FR-003-013）
- [ ] T5 https 用例：TC-003-09~13（ls-remote/clone/fetch/CA 反证/农场缺失对照）（FR-003-014~017）
- [ ] T6 env 契约用例：TC-003-05 内嵌断言 + TC-003-07（FR-003-030~034）
- [ ] T7 限制事实化用例：TC-003-14/15/16（钩子/ssh/perl）（FR-003-040~043）
- [ ] T8 16KB/环境快照：TC-003-00b/17 + 报告环境快照（FR-003-044）
- [ ] T9 设备策略执行：真机探测/缺省拉起 arm64 AVD；首轮全量执行
- [ ] T10 TEST_REPORT.md + test-cases.md 回填 + 规划 §7.2/§7.3 事实回写（R4/R11）（C8）
