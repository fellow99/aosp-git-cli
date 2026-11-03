// probe-app —— M1-T7/M2-T1 探针载体（specs/003-cli tasks T4；参考 aosp-python-cli/probe-app）
// 独立 Gradle 工程（不在 aosp-git-cli settings.gradle 内——000 的单模块红线不动）。
// 依赖本仓 CI 产物 AAR：把 Release artifact 里的 *-aar.aar 放到 app/libs/git-cli-release.aar 后构建。
plugins {
    id("com.android.application") version "9.2.1" apply false
}
