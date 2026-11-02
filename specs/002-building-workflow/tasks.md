# 002-building-workflow 任务拆解

> 对应：[spec.md](./spec.md)（FR-002-xxx）· [plan.md](./plan.md）。前置：001 产物可用（helper-inventory + assets 树）。

- [ ] T1 provision 多文件投放：`--from <dir>` + helper 全集逐个七门禁（FR-002-001）
- [ ] T2 jniLibs 白名单升级：lock `matrix.jniLibsWhitelist` 驱动 `--check`（FR-002-002；TC-000-07/08 转正）
- [ ] T3 gitexec-manifest 一致性校验（悬空/孤儿双向，FR-002-003）
- [ ] T4 `--assets` 投放与校验（纯数据 + 逐文件 sha256 + manifest.json 总哈希，FR-002-004）
- [ ] T5 元数据扩展（helpers/deps 行）+ 幂等复测 + 退出码复核（FR-002-005/006）
- [ ] T6 lock 字段扩展落地（jniLibsWhitelist/helperExempt/builtFrom.helpers；联动 001）
- [ ] T7 workflow 重写：装机 + 全链 + 归档（四源 tarball + 脚本，C7）+ tag/非 tag 矩阵（FR-002-010/011/013/014/016）
- [ ] T8 退出码断言修复（FR-002-012，000-scaffold plan §7.0 缺陷关闭）
- [ ] T9 lock 回写步骤（size/sha256/helpers/gates=true/status=released → PR，FR-002-015）
- [ ] T10 配置期门禁保留验证 + 语法门扩展（FR-002-020/021）
- [ ] T11 用例执行（TC-002-*）+ 本机预跑记录回写 plan.md
