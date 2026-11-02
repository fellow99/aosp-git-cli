# 001-building 任务拆解

> 对应：[spec.md](./spec.md)（FR-001-xxx）· [plan.md](./plan.md)。原则：先可复现取源，再逐级静态构建，实产探明后回写。

- [ ] T1 fetch 实现：PINS 五输入定稿（官方 sha256 一手实测）+ 下载/校验/解压/幂等 + FETCH-METADATA.json（FR-001-001~004、006；M1-T1）
- [ ] T2 lock `builtFrom.deps` 版本表回写 + `builtFrom.source` 结构化（FR-001-005；M1-T1）
- [ ] T3 zlib 静态交叉构建（S1，R9）（FR-001-010；M1-T2）
- [ ] T4 openssl 静态交叉构建（S2，R7）（FR-001-011；M1-T2）
- [ ] T5 curl 静态交叉构建（S3，R8；--without-* 裁剪）（FR-001-012/013；M1-T2）
- [ ] T6 git config.mak 生成 + NO_* 注入 + LDFLAGS 16KB（S4，FR-001-020/022/025；M1-T3）
- [ ] T7 git make 首轮试编（S5）+ 静态链入验证（门禁④）（FR-001-021/023；M1-T3）
- [ ] T8 helper 实产清单探明（S6，R1）→ helper-inventory.json → 回写规划 §5.2 / lock（FR-001-024；M1-T3）
- [ ] T9 strip + `libgit_*.so` 命名映射（S7）（FR-001-030/031；M1-T4）
- [ ] T10 assets 收集（templates/cacert/gitexec-manifest.json，纯数据）（S8）（FR-001-032/033；M1-T4）
- [ ] T11 BUILD-METADATA + 体积实测回填（S9）（FR-001-034/035；M1-T4）
- [ ] T12 本机全链跑通 + 七门禁自检（--inspect 全过）+ 用例执行（TC-001-*）
- [ ] T13 首轮试编结论回写 plan.md（⬜→✅）与规划 §4.2/§5.2（C8）
