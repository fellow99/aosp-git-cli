# THIRD-PARTY-NOTICES — aosp-git-cli

本 AAR 随包分发的第三方组件与许可：

- **git**（`libgit_cli.so` 本体）—— GPLv2（含例外条款，随 git 源码 COPYING 分发）：
  https://github.com/git/git/blob/master/COPYING
- **zlib**（静态链入）—— zlib License
- **libcurl**（静态链入，https 传输）—— curl License（MIT 派生）
- **OpenSSL**（静态链入，https 传输）—— Apache-2.0（OpenSSL 3.x）
- **CA bundle**（随包根证书集合）——按所选来源（如 cURL 的 cacert.pem）随 Release 归档分发

纪律：

- 二进制不入库，由 CI 从官方 git 源码构建（sha256 校验，源码不改；
  Android 缺项（iconv/tcltk/gettext/regex）以 NO_* 配置关闭，不引入源码补丁）；
- **注意**：git 为 GPLv2，随 AAR 分发时必须随包提供对应源码获取方式
  （GitHub Release 归档同时分发构建所用源码 tarball 与构建脚本，满足 GPL 的对应源码义务）；
- 完整许可全文随 GitHub Release 归档分发；
- 本仓库自身代码适用仓库根 [LICENSE](../LICENSE)（MIT）。
