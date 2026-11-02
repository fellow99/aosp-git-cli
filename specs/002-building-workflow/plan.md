# 002-building-workflow — 模块计划（plan.md，planned → 开发后回写 as-built）

> **模块**：002-building-workflow 构建流水线 · **性质**：技术实现计划（先写「怎么做」，落地后回写行号）。
> **依据**：[`../constitution.md`](../constitution.md)（C1–C8）· [`../../docs/000-工程规划.md`](../../docs/000-工程规划.md)（规划 §5.3/§6/§9/§10.1）· 本模块 [`spec.md`](./spec.md)（FR-002-xxx）。
> **版本**：v1.0 · 2026-11-02 · 状态：⬜ 未实现（现 provision 为单文件白名单 as-built，CI 为配置期门禁）。

---

## 1. 技术上下文

| 项 | 现状（as-built） | 目标（本模块） |
|---|---|---|
| `tools/provision.mjs` | 276 行：单文件七门禁 + jniLibs 单文件白名单 + `libnode.so` 禁入（000-scaffold/plan.md §4） | 多文件：helper 全集七门禁 + `matrix.jniLibsWhitelist` + manifest 一致性 + `--assets` |
| `git-cli.lock.json` | `matrix.allowedNeeded` 5 项；无 `jniLibsWhitelist` | 增 `matrix.jniLibsWhitelist`、`builtFrom.helpers`、gates 语义（T9 定稿：draft 全 false） |
| CI workflow | 50 行配置期门禁；⚠️ 退出码断言在 `bash -e` 下分支不可达（000 plan §7.0） | 真实流水线（fetch→build→provision→归档→Release→lock 回写）+ 断言修复 |
| 消费输入 | — | 001 产物：`build/out/libgit_*.so` + `assets/git-bridge-tools/` + helper-inventory.json |

---

## 2. provision 扩展设计（M1-T5）

### 2.1 命令面（增量）

| 命令 | 行为 | 退出码 |
|---|---|---|
| `--check`（现有） | 升级：`<jniLibs>/<abi>/` 内全部 `.so` 逐个过七门禁；白名单 = lock `matrix.jniLibsWhitelist`（缺省回落 `libgit_cli.so` 单文件，向后兼容）；随后 manifest 一致性 +（若已投放 assets）assets 校验 | 0/2 |
| `--out <dir> --from <dir|file>`（升级） | `--from` 接受**目录**（内含 `libgit_*.so` 全集，按白名单投放）或单文件（兼容旧用法）；逐文件门禁后统一落盘 | 0/1/2 |
| `--assets <dir>`（新增） | 校验并投放 assets 树到 `git-cli/src/main/assets/git-bridge-tools/`：纯数据检查（无 `.so`/无可执行位）+ 逐文件 sha256 → 生成/校验 `manifest.json`（含总 sha256） | 0/1/2 |
| `--inspect <file>`（现有） | 不变 | 0/2 |

### 2.2 白名单与一致性规则

```
jniLibsWhitelist = lock.matrix.jniLibsWhitelist ?? [rel.name]        // 回落兼容
投放目录内 .so 集合必须 == 白名单（多/少/错名均 exit 2）
gitexec-manifest.farm: {农场名 → 物理件} ⊆ jniLibsWhitelist（悬空 ⇒ exit 2）
反向：白名单每个物理件 ∈ farm 值集合 ∪ matrix.helperExempt（孤儿 ⇒ exit 2）
assets：{ 相对路径 → sha256 }；总 sha256 = sha256(排序拼接逐行 "<sha>  <path>")
```

### 2.3 元数据扩展

`META-INF/git-cli.properties` 追加：`helpers=<farm 名→物理件, 逗号串>`、
`deps=zlib@x,curl@y,openssl@z`、`gitVersion`（与 tool.version 同值时省略后者，保持向后可读）。

### 2.4 lock 字段扩展（001 §5 联动）

```json
"matrix": {
  "jniLibsWhitelist": ["libgit_cli.so", "libgit_remote_curl.so", …],
  "helperExempt": []                     // 显式豁免（无农场条目的物理件）登记+理由
}
"releases[i]": { "builtFrom": { "helpers": {"libgit_remote_curl.so": {"farm": ["git-remote-http","git-remote-https"], "sha256": "…"}} } }
```

---

## 3. CI 流水线设计（M1-T6，替换 scaffold workflow）

### 3.1 触发与矩阵

- `push(main)/PR`：build + gates（无 Release，FR-002-016）；
- `push(tag v<gitver>)` / `workflow_dispatch(gitVersion)`：build + gates + Release + lock 回写 PR（FR-002-014）；
- tag 与 lock `active.version` 一致性前置校验（不一致即 fail-fast）。

### 3.2 job 步骤（单 job 顺序，规划 §9）

```
checkout → JDK21/Gradle 9.4.1/Node20 → android-actions/setup-android + sdkmanager ndk;<lock 线>
→ apt: make gcc perl autoconf(可) tar xz file ccache
→ fetch（001 脚本）→ build（001 脚本）→ provision --inspect 全产物（七门禁）
→ provision --out + --assets（投放）→ gradle :git-cli:assembleRelease（AAR 组装）
→ 归档 tar.gz（lib*.so + assets + 双 METADATA + LICENSES/NOTICES + .dist/dl 四源包 + scripts/ 构建脚本副本）+ .sha256
→ [tag] gh release upload → lock 回写（releases[].size/sha256/helpers/gates=true/status=released）→ 自动 PR 或 artifact 附回写文件
```

缓存：`.dist/dl/`（五输入）+ 依赖 `.a` 阶段产物 + ccache（首轮 ⬜ 实测定策略）。

### 3.3 退出码断言修复（FR-002-012，000 plan §7.0）

```yaml
# 修法（不再受 bash -e 截断）：
code=0
node tools/provision.mjs --check || code=$?
[ "$code" -eq 2 ] || { echo "unexpected exit $code"; exit 1; }
```

配置期门禁步（gradle tasks / 语法门）保留在流水线头部（FR-002-020/021）。

---

## 4. 宪法符合性检查（逐条）

| 原则 | 判定 | 依据 |
|---|---|---|
| C2 lock 唯一事实源 | ✅ | 白名单/helpers/版本表全部进 lock；回写 draft→released 单向 |
| C3 二进制不入库 | ✅ | 投放落点仍 jniLibs/assets（gitignored）；CI 用 artifact/Release 分发 |
| C4 门禁强制 | ✅ | helper 全集逐个七门禁；manifest/assets 校验全硬判定（exit 2） |
| C5 发布卫生 | ✅ | 非 tag 不 Release；RELEASE=false（Maven 面）不动；凭据零入库 |
| C6 未实测标 ⬜ | ✅ | CI 全链 ⬜ 首跑后回写；本机预跑结论标 ✅（本机）/ CI 结论另计 |
| C7 GPLv2 对应源码 | ✅ | 归档含四源 tarball + 构建脚本（R5 措辞在 Release 前定稿） |
| C8 先改文档再改实现 | ✅ | 本文件先于 workflow 重写；首跑结论回写 |

---

## 5. FR 交叉引用

| FR | 实现落点 | 状态 |
|---|---|---|
| FR-002-001~006 | `tools/provision.mjs`（多文件门禁/白名单/manifest/assets/元数据/退出码） | ⬜ |
| FR-002-010~016 | `.github/workflows/build-git-cli-android.yml`（重写） | ⬜ |
| FR-002-020/021 | 同上（头部保留配置期门禁 + 语法门扩到全部脚本） | ⬜ |

---

## 6. 测试要点（详见 test-cases.md）

- 负例矩阵：白名单外 `.so` / `libnode.so` / manifest 悬空 / manifest 孤儿 / assets 可执行位 / assets sha 失配 / 退出码 1 场景；
- CI 断言语义：构造 `--check` 退出 1 的场景（如临时改坏 lock）断言步必须红；
- 幂等：重复 `--out`/`--assets` 结果一致。

---

## 7. 待实现清单

- [ ] provision 多文件门禁 + 白名单 + manifest 一致性（FR-002-001~003）
- [ ] `--assets` 命令 + manifest.json 生成/校验（FR-002-004）
- [ ] 元数据扩展 + 幂等复测（FR-002-005/006）
- [ ] lock `matrix.jniLibsWhitelist`/`helperExempt`/`builtFrom.helpers` 落字段（联动 001 T2/T8）
- [ ] workflow 重写（触发矩阵/装机/全链/归档/Release/lock 回写）+ 断言修复（FR-002-010~016）
- [ ] 本机预跑全链（等价步骤复演）→ CI 首跑结论回写
