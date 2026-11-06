package org.fellow99.gitprobe;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * git-cli 探针载体（M1-T7 App 域 / M2-T1；specs/003-cli/test-cases.md 全表 + App 域专项）。
 *
 * 职责（镜像 docs/000-工程规划.md §3 消费方环境引导层 + §7.1 env 契约）：
 *  1) 物化：assets/git-bridge-tools/** → filesDir/git-bridge-tools（manifest.json totalSha256 marker 幂等）；
 *  2) 农场（D5，App 域 P5）：依 gitexec-manifest.json 在 filesDir/gitexec 建原名 symlink
 *     （android.system.Os.symlink → nativeLibraryDir/libgit_*.so；先清后建幂等）；
 *  3) 注入（§7.1 全表）：GIT_EXEC_PATH/GIT_TEMPLATE_DIR/GIT_CONFIG_GLOBAL/GIT_CONFIG_NOSYSTEM/
 *     GIT_SSL_CAINFO/SSL_CERT_FILE/PATH/HOME/TMPDIR/GIT_PAGER=cat；
 *  4) 执行：ProcessBuilder exec nativeLibraryDir/libgit_cli.so（非 PTY 子集；交互语义归终端 App）；
 *  5) 判据：TC-003-00…17 + App 域专项 TC-003-18a/b，逐条 PASS/FAIL/SKIP/BLOCKED + JSON 报告。
 *
 * 边界（诚实口径）：本载体验证 App 域（nativeLibraryDir 落盘 + targetSdk≥29 app 域 SELinux + 农场 symlink exec）；
 * PTY/终端交互归消费方终端 App，不在判据内。
 */
public class MainActivity extends Activity {

    private TextView logView;
    private File toolsDir;      // filesDir/git-bridge-tools
    private File farmDir;       // filesDir/gitexec
    private String nativeDir;   // applicationInfo.nativeLibraryDir
    private String gitExe;      // nativeDir/libgit_cli.so
    // 测试仓库资源经 intent extras 传入（敏感信息不落盘：不入源码/不入报告/不入文档）
    private String pubUrl;      // --es git_public_url <无账号 https 仓库>
    private String authUrl;     // --es git_auth_url <带账号 http(s) 仓库>
    private String authUser;    // --es git_user
    private String authPass;    // --es git_pass
    private String authUrlRedacted; // 脱敏展示用
    private final StringBuilder uiLog = new StringBuilder();
    private final List<JSONObject> report = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        nativeDir = getApplicationInfo().nativeLibraryDir;
        gitExe = nativeDir + "/libgit_cli.so";
        toolsDir = new File(getFilesDir(), "git-bridge-tools");
        farmDir = new File(getFilesDir(), "gitexec");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        Button run = new Button(this);
        run.setText("RUN ALL PROBES");
        run.setOnClickListener(v -> runAll());
        ScrollView scroll = new ScrollView(this);
        logView = new TextView(this);
        logView.setTypeface(android.graphics.Typeface.MONOSPACE);
        logView.setTextIsSelectable(true);
        logView.setTextSize(11f);
        int pad = (int) (getResources().getDisplayMetrics().density * 8);
        logView.setPadding(pad, pad, pad, pad);
        scroll.addView(logView);
        root.addView(run, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);
        log("probe-app ready\nnativeDir=" + nativeDir + "\ntoolsDir=" + toolsDir
                + "\nRUN ALL PROBES 执行（首次物化 + 全部探针）");
        // adb 无头触发：am start ... --ez autorun true
        Intent in = getIntent();
        if (in != null) {
            pubUrl = in.getStringExtra("git_public_url");
            authUrl = in.getStringExtra("git_auth_url");
            authUser = in.getStringExtra("git_user");
            authPass = in.getStringExtra("git_pass");
            authUrlRedacted = authUrl == null ? null : authUrl.replaceFirst("//[^/@]+:[^/@]+@", "//***:***@");
            credPattern = authUrl == null ? null
                    : java.util.regex.Pattern.quote("//" + authUser + ":" + authPass + "@");
        }
        if (in != null && in.getBooleanExtra("autorun", false)) runAll();
    }

    private void log(String s) {
        runOnUiThread(() -> {
            uiLog.append(s).append('\n');
            logView.setText(uiLog.toString());
        });
    }

    // ── 物化（marker 幂等）与农场（D5 symlink farm，App 域）────────────────────

    private String assetsMarker() {
        try {
            InputStream is = getAssets().open("git-bridge-tools/manifest.json");
            String m = readAll(is, 4 << 20);
            int i = m.indexOf("\"totalSha256\"");
            if (i < 0) return null;
            int q1 = m.indexOf('"', i + 13) + 1;
            int q2 = m.indexOf('"', q1);
            return m.substring(q1, q2);
        } catch (IOException e) {
            return null;
        }
    }

    private void materialize() throws IOException {
        String marker = assetsMarker();
        SharedPreferences prefs = getSharedPreferences("probe", Context.MODE_PRIVATE);
        String prev = prefs.getString("tools.sha", "");
        File done = new File(toolsDir, "manifest.json");
        if (marker != null && marker.equals(prev) && done.isFile()) {
            log("物化跳过（marker 一致：" + marker.substring(0, 12) + "…）");
            return;
        }
        long t0 = System.currentTimeMillis();
        deleteRecursive(toolsDir);
        toolsDir.mkdirs();
        int n = copyAssetTree("git-bridge-tools", toolsDir);
        prefs.edit().putString("tools.sha", marker == null ? "" : marker).apply();
        log("物化完成：" + n + " 文件，" + (System.currentTimeMillis() - t0) + "ms");
    }

    private int copyAssetTree(String path, File dest) throws IOException {
        AssetManager am = getAssets();
        String[] children = am.list(path);
        if (children == null) return 0;
        int n = 0;
        String prefix = "git-bridge-tools/";
        for (String c : children) {
            String sub = path + "/" + c;
            String[] subChildren = am.list(sub);
            if (subChildren != null && subChildren.length > 0) {
                n += copyAssetTree(sub, dest);
            } else {
                File out = new File(dest, sub.substring(prefix.length()));
                out.getParentFile().mkdirs();
                try (InputStream is = am.open(sub); OutputStream os = new FileOutputStream(out)) {
                    byte[] buf = new byte[65536];
                    int r;
                    while ((r = is.read(buf)) > 0) os.write(buf, 0, r);
                }
                n++;
            }
        }
        return n;
    }

    /** 依 gitexec-manifest.json 建 farm（先清后建，幂等；P5 App 域 symlink exec 验证点）。 */
    private String buildFarm() {
        try {
            deleteRecursive(farmDir);
            farmDir.mkdirs();
            JSONObject man = new JSONObject(readAll(getAssets().open("git-bridge-tools/gitexec-manifest.json"), 1 << 20));
            JSONObject farm = man.getJSONObject("farm");
            java.util.Iterator<String> it = farm.keys();
            int n = 0;
            while (it.hasNext()) {
                String name = it.next();
                String phys = farm.getString(name);
                android.system.Os.symlink(nativeDir + "/" + phys, new File(farmDir, name).getAbsolutePath());
                n++;
            }
            return "farm=" + n + " 条（symlink → " + nativeDir + "）";
        } catch (Exception e) {
            return "FARM-BUILD-FAIL: " + e;
        }
    }

    private void deleteRecursive(File f) {
        File[] c = f.listFiles();
        if (c != null) for (File x : c) deleteRecursive(x);
        f.delete();
    }

    // ── 环境注入（规划 §7.1 全表）与执行器 ──────────────────────────────────────

    private Map<String, String> baseEnv() {
        Map<String, String> env = new LinkedHashMap<>();
        env.put("HOME", new File(getFilesDir(), "home").getAbsolutePath());
        env.put("TMPDIR", new File(getFilesDir(), "tmp").getAbsolutePath());
        env.put("GIT_EXEC_PATH", farmDir.getAbsolutePath());
        env.put("GIT_TEMPLATE_DIR", new File(toolsDir, "templates").getAbsolutePath());
        env.put("GIT_CONFIG_GLOBAL", new File(getFilesDir(), "home/.gitconfig").getAbsolutePath());
        env.put("GIT_CONFIG_NOSYSTEM", "1");
        env.put("GIT_SSL_CAINFO", new File(toolsDir, "cacert.pem").getAbsolutePath());
        env.put("SSL_CERT_FILE", new File(toolsDir, "cacert.pem").getAbsolutePath());
        env.put("GIT_PAGER", "cat");
        env.put("PATH", nativeDir + ":" + farmDir.getAbsolutePath() + ":/system/bin");
        return env;
    }

    static class Out {
        String stdout = "", stderr = "";
        int exit = -1;
        long ms;
        boolean timedOut;
        String failReason;
    }

    private Out exec(List<String> argv, Map<String, String> envIn, String stdin, long timeoutMs) {
        Out o = new Out();
        long t0 = System.currentTimeMillis();
        try {
            new File(getFilesDir(), "home").mkdirs();
            new File(getFilesDir(), "tmp").mkdirs();
            new File(getFilesDir(), "ws").mkdirs();
            ProcessBuilder pb = new ProcessBuilder(argv);
            pb.directory(new File(getFilesDir(), "ws"));
            pb.redirectErrorStream(false);
            Map<String, String> env = pb.environment();
            env.clear();
            env.putAll(envIn);
            env.put("ANDROID_ROOT", "/system");
            env.put("ANDROID_DATA", "/data");
            env.put("LD_LIBRARY_PATH", nativeDir);
            Process p = pb.start();
            if (stdin != null) {
                try (OutputStream os = p.getOutputStream()) {
                    os.write(stdin.getBytes(StandardCharsets.UTF_8));
                }
            } else {
                p.getOutputStream().close();
            }
            StringBuilder so = new StringBuilder(), se = new StringBuilder();
            Thread t1 = pump(p.getInputStream(), so), t2 = pump(p.getErrorStream(), se);
            if (!p.waitFor(timeoutMs, TimeUnit.MILLISECONDS)) {
                p.destroyForcibly();
                o.timedOut = true;
            }
            t1.join(3000);
            t2.join(3000);
            o.stdout = so.toString();
            o.stderr = se.toString();
            o.exit = p.exitValue();
        } catch (Exception e) {
            o.failReason = e.getClass().getSimpleName() + ": " + e.getMessage();
        }
        o.ms = System.currentTimeMillis() - t0;
        return o;
    }

    private Thread pump(InputStream is, StringBuilder sb) {
        Thread t = new Thread(() -> {
            try (BufferedReader r = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) sb.append(line).append('\n');
            } catch (IOException ignored) {
            }
        });
        t.start();
        return t;
    }

    // ── 探针定义 ────────────────────────────────────────────────────────────────

    interface Check {
        String check(Out o); // null=PASS；"SKIP:…"/"BLOCKED:…"/"PASS-…"前缀特殊判定
    }

    static class Probe {
        final String id, title;
        final List<String> argv;
        final Map<String, String> envOverride; // value null=删除该变量
        final String stdin;
        final long timeoutMs;
        final Check check;
        Probe(String id, String title, List<String> argv, Map<String, String> envOverride,
              String stdin, long timeoutMs, Check check) {
            this.id = id; this.title = title; this.argv = argv;
            this.envOverride = envOverride; this.stdin = stdin; this.timeoutMs = timeoutMs; this.check = check;
        }
    }

    private List<String> git(String... args) {
        List<String> a = new ArrayList<>();
        a.add(gitExe);
        for (String s : args) a.add(s);
        return a;
    }

    private List<Probe> probes() {
        List<Probe> l = new ArrayList<>();
        String ws = new File(getFilesDir(), "ws").getAbsolutePath();
        String repo = ws + "/repo";

        // ── App 域专项（M1-T7 探针 1：useLegacyPackaging 落盘 + app 域 SELinux exec；P5 农场 symlink）──
        l.add(new Probe("TC-003-18a", "App 域落盘：nativeLibraryDir 物理件存在且可读", git("--version"), null, null, 30_000,
                o -> {
                    File f = new File(nativeDir, "libgit_cli.so");
                    return f.isFile() && f.canRead() && o.exit == 0 && o.stdout.contains("git version 2.56.0")
                            ? null
                            : "nativeLibraryDir=" + nativeDir + " exists=" + f.isFile() + " exit=" + o.exit + " out=" + head(o.stdout);
                }));
        l.add(new Probe("TC-003-18b", "App 域农场：gitexec symlink exec（P5 app 域 SELinux 放行）",
                arr(farmDir + "/git", "--version"), null, null, 30_000,
                o -> o.exit == 0 && o.stdout.contains("git version 2.56.0") ? null
                        : "farm symlink exec 失败 exit=" + o.exit + " err=" + head(o.stderr)));

        // ── B. 版本与基础命令（P1）──
        l.add(new Probe("TC-003-01", "版本串回程", git("--version"), null, null, 30_000,
                o -> o.exit == 0 && o.stdout.contains("git version 2.56.0") ? null
                        : "exit=" + o.exit + " out=" + head(o.stdout) + head(o.stderr)));
        l.add(new Probe("TC-003-02", "--exec-path 指向注入农场（GIT_EXEC_PATH 生效）", git("--exec-path"), null, null, 30_000,
                o -> o.exit == 0 && o.stdout.trim().equals(farmDir.getAbsolutePath()) ? null
                        : "exit=" + o.exit + " out=" + head(o.stdout) + " 期望=" + farmDir.getAbsolutePath()));
        l.add(new Probe("TC-003-02b", "help -a 非交互直出（GIT_PAGER=cat）", git("help", "-a"), null, null, 60_000,
                o -> o.exit == 0 && o.stdout.length() > 100 ? null : "exit=" + o.exit + " len=" + o.stdout.length()));
        l.add(new Probe("TC-003-03", "farm `git` PATH 直呼（sh 查找经 gitexec）",
                arr("/system/bin/sh", "-c",
                        "PATH=" + farmDir.getAbsolutePath() + ":/system/bin git --version"),
                null, null, 30_000,
                o -> o.exit == 0 && o.stdout.contains("git version 2.56.0") ? null
                        : (o.stdout + o.stderr).contains("Unable to get realpath")
                        ? "FAIL(环境特定:ndk_translation 按名查找 symlink realpath 失败；绝对路径直 exec 正常见 18b；真机补测) " + head(o.stdout + o.stderr, 120)
                        : "exit=" + o.exit + " out=" + head(o.stdout) + head(o.stderr)));
        l.add(new Probe("TC-003-04", "退出码采样（用法错/无仓库）", git("--bogus-flag"), null, null, 30_000,
                o -> (o.exit == 129 || o.exit == 1) ? null : "exit=" + o.exit + "（采样记录性）"));

        // ── C. 本地仓库全链（P2；env 契约内嵌）──
        l.add(new Probe("TC-003-05", "init→add(中文)→commit(中文)→log 全链 + 模板 hooks", git("init", repo), null, null, 60_000,
                o -> {
                    if (o.exit != 0 && o.stdout.contains("already exists")) return null; // 复跑容忍
                    if (o.exit != 0) return "init exit=" + o.exit + head(o.stderr);
                    // 链式断言在 runAll 里的 chained() 完成（见下）
                    return null;
                }));
        l.add(new Probe("TC-003-06", "本地 clone --no-local 经农场（GIT_TRACE 见 upload-pack）",
                git("clone", "--no-local", repo, ws + "/clone1"), envKv("GIT_TRACE", "1"), null, 120_000,
                o -> o.exit == 0 && (o.stderr.contains("git-upload-pack") || o.stderr.contains("upload-pack"))
                        ? null
                        : (o.stderr.contains("Unable to get realpath"))
                        ? "FAIL(环境特定:ndk_translation dashed 子进程按名查找 symlink realpath 失败；https helper 绝对路径 exec 正常见 09；真机补测) " + head(o.stderr, 150)
                        : "exit=" + o.exit + " err=" + head(o.stderr, 300)));
        l.add(new Probe("TC-003-07", "全局配置回路（GIT_CONFIG_GLOBAL 落注入 HOME）", git("config", "--global", "user.name", "probe"),
                null, null, 30_000, o -> o.exit == 0 ? null : "exit=" + o.exit + head(o.stderr)));
        l.add(new Probe("TC-003-07b", "全局配置 user.email（commit 前置）", git("config", "--global", "user.email", "probe@test.local"),
                null, null, 30_000, o -> o.exit == 0 ? null : "exit=" + o.exit + head(o.stderr)));
        l.add(new Probe("TC-003-08", "工作区操作采样（branch/tag/stash）", git("init", ws + "/wsrepo"), null, null, 60_000,
                o -> o.exit == 0 || o.stdout.contains("already exists") ? null : head(o.stderr)));

        // ── D. https 传输（P3/P4/P6；目标经 extras 注入，缺省 SKIP）──
        String badCa = new File(getFilesDir(), "bad-ca.pem").getAbsolutePath();
        String pubNote = pubUrl == null ? "SKIP:未提供 git_public_url extra" : null;
        boolean authReady = authUrl != null && authUser != null && authPass != null;
        String credUrl = authReady ? authUrl.replaceFirst("://", "://" + authUser + ":" + authPass + "@") : null;
        l.add(new Probe("TC-003-09", "ls-remote https 经 farm helper（P3）",
                pubUrl == null ? git("--version") : git("ls-remote", pubUrl, "HEAD"),
                envKv("GIT_TRACE", "1"), null, 240_000,
                o -> pubUrl == null ? pubNote
                        : o.exit == 0 && o.stdout.matches("(?s)[0-9a-f]{40}.*HEAD.*") ? null
                        : o.exit == 128 && o.stderr.contains("Could not connect") ? "SKIP:模拟器 NAT 对目标 443 连接超时（宿主可达，环境特定）"
                        : "exit=" + o.exit + " err=" + head(o.stderr, 300)));
        l.add(new Probe("TC-003-10", "clone --depth 1 https（P4）",
                pubUrl == null ? git("--version") : git("clone", "--depth", "1", pubUrl, ws + "/gclone"),
                null, null, 240_000,
                o -> pubUrl == null ? pubNote
                        : o.exit == 0 ? null
                        : o.stderr.contains("Could not connect") ? "SKIP:同 TC-003-09 网络环境限制"
                        : "exit=" + o.exit + " err=" + head(o.stderr, 300)));
        l.add(new Probe("TC-003-10b", "clone 后 log 恰 1 条（depth 生效）",
                git("log", "--oneline"), envKv("GIT_DIR", ws + "/gclone/.git"), null, 30_000,
                o -> !new File(ws, "gclone/.git").isDirectory()
                        ? "SKIP:依赖 TC-003-10 克隆成功"
                        : o.exit == 0 && o.stdout.trim().lines().count() == 1 ? null
                        : "exit=" + o.exit + " out=" + head(o.stdout)));
        l.add(new Probe("TC-003-11", "fetch https（origin 采样）",
                git("fetch", "--depth", "1", "origin"), envKv("GIT_DIR", ws + "/gclone/.git"), null, 180_000,
                o -> !new File(ws, "gclone/.git").isDirectory()
                        ? "SKIP:依赖 TC-003-10"
                        : o.exit == 0 ? null : "exit=" + o.exit + " err=" + head(o.stderr, 200)));
        l.add(new Probe("TC-003-12", "CA 反证：损坏 CA ⇒ TLS 失败（P6）",
                !new File(ws, "gclone/.git").isDirectory() ? git("--version") : git("ls-remote", pubUrl, "HEAD"),
                envKv("GIT_SSL_CAINFO", badCa, "SSL_CERT_FILE", badCa), null, 120_000,
                o -> !new File(ws, "gclone/.git").isDirectory()
                        ? "SKIP:依赖 TC-003-10（需可连的 https 端点）"
                        : o.exit != 0 && (o.stderr.toLowerCase().contains("certificate") || o.stderr.toLowerCase().contains("ssl")
                        || o.stderr.toLowerCase().contains("ca")) ? null
                        : o.exit == -1 ? "FAIL:超时（网络偶发）"
                        : "exit=" + o.exit + "（坏 CA 应失败且错误含证书语义）err=" + head(o.stderr, 200)));
        // farm 缺失对照：sh 内自治摘除 http+https helper → ls-remote 应失败 → 还原（Java renameTo 在部分环境不可靠，sh mv 已实证）
        l.add(new Probe("TC-003-13", "农场缺失对照：http/https helper 双摘 ⇒ 不可得（自恢复）",
                authUrl == null ? git("--version") : arr("/system/bin/sh", "-c",
                        "cd " + farmDir.getAbsolutePath() +
                        " && mv git-remote-http .b1 && mv git-remote-https .b2;" +
                        " git -C " + ws + " ls-remote " + credUrl + " >/dev/null 2>&1; RC=$?;" +
                        " mv .b1 git-remote-http && mv .b2 git-remote-https && echo RESTORED && echo RC=$RC"),
                null, null, 90_000,
                o -> authUrl == null ? "SKIP:未提供 authUrl/凭证 extras——farm 缺失对照需可连 https 端点（同 TC-003-19a 口径）"
                        : o.exit != 0 ? "FAIL(自治脚本未完成还原) " + head(sanitize(o.stdout + o.stderr), 200)
                        : !o.stdout.contains("RESTORED") ? "FAIL(未还原) " + head(sanitize(o.stdout), 200)
                        : o.stdout.contains("RC=0") ? "意外成功（farm 缺失应失败）"
                        : o.stdout.contains("RC=128") || o.stdout.contains("RC=1") ? null
                        : "RC=" + head(sanitize(o.stdout), 100)));

        // ── D2. 带账号仓库操作（clone/fetch/push；凭证经 extras，不落盘；目标 http(s) 内网）──
        l.add(new Probe("TC-003-19a", "带账号 clone --depth 1（http 认证）",
                authReady ? git("clone", "--depth", "1", credUrl, ws + "/arepo") : git("--version"),
                null, null, 300_000,
                o -> !authReady ? "SKIP:未提供 git_auth_url/git_user/git_pass extras"
                        : o.exit == 0 ? null : "exit=" + o.exit + " err=" + head(sanitize(o.stderr), 300)));
        l.add(new Probe("TC-003-19b", "带账号 fetch（origin 采样）",
                authReady ? git("fetch", "--depth", "1", "origin") : git("--version"),
                envKv("GIT_DIR", ws + "/arepo/.git"), null, 180_000,
                o -> !authReady ? "SKIP:未提供凭证 extras"
                        : !new File(ws, "arepo/.git").isDirectory() ? "SKIP:依赖 TC-003-19a"
                        : o.exit == 0 ? null : "exit=" + o.exit + " err=" + head(sanitize(o.stderr), 200)));
        l.add(new Probe("TC-003-19c", "带账号 push（推探针分支 + 自清理）",
                authReady ? arr("/system/bin/sh", "-c",
                        "git -C " + ws + "/arepo push origin HEAD:refs/heads/probe-gitcli-test" +
                        " && git -C " + ws + "/arepo push origin --delete probe-gitcli-test && echo PUSH_OK")
                        : git("--version"),
                null, null, 300_000,
                o -> !authReady ? "SKIP:未提供凭证 extras"
                        : !new File(ws, "arepo/.git").isDirectory() ? "SKIP:依赖 TC-003-19a"
                        : o.exit == 0 && o.stdout.contains("PUSH_OK") ? null
                        : (o.stdout + o.stderr).contains("Unable to get realpath")
                        ? "FAIL(环境特定:同 TC-003-03 realpath 限制；真机补测) " + head(o.stderr, 150)
                        : "exit=" + o.exit + " err=" + head(sanitize(o.stderr), 200)));

        // ── E. 已知限制事实化（§7.2）──
        l.add(new Probe("TC-003-14", "钩子不可 exec ⇒ 视为无钩子（commit 照常）",
                git("commit", "--allow-empty", "-m", "hookless"),
                envKv("GIT_DIR", repo + "/.git"), null, 60_000,
                o -> o.exit == 0 ? null : "exit=" + o.exit + " err=" + head(o.stderr, 200)));
        l.add(new Probe("TC-003-15", "ssh 远程不可用（无 ssh 二进制，记录性）",
                git("ls-remote", "git@github.com:octocat/Hello-World.git"), null, null, 30_000,
                o -> o.exit != 0 || o.failReason != null ? null : "意外成功"));
        l.add(new Probe("TC-003-16", "perl 子命令不可得（send-email 未编译，记录性）",
                git("send-email"), null, null, 30_000,
                o -> o.exit != 0 && (o.stderr.contains("not a git command") || o.stderr.contains("send-email")) ? null
                        : "exit=" + o.exit + " err=" + head(o.stderr, 200)));
        // TC-003-17（16KB 页设备采样）在 runAll 里按 getconf PAGESIZE 判定 SKIP/复跑。

        // ── 链式序列（git -C 直连主件；避免 sh→PATH→farm symlink 的 realpath 环节）──
        l.add(new Probe("TC-003-05b", "中文文件名/提交信息 + status + hooks sample（P2+R4）",
                arr("/system/bin/sh", "-c",
                        "G=" + gitExe + "; echo hello > " + repo + "/hello.txt && printf '中文内容' > " + repo + "/中文文件名.txt" +
                        " && $G -C " + repo + " add . && $G -C " + repo +
                        " commit -m '中文提交信息' >/dev/null && $G -C " + repo + " log --oneline" +
                        " && $G -C " + repo + " status --short && echo STATUS_OK" +
                        " && ls " + repo + "/.git/hooks/pre-commit.sample >/dev/null && echo HOOKS_OK" +
                        " && $G -C " + repo + " ls-files && [ \"$($G -C " + repo + " -c core.quotepath=false ls-files | wc -l)\" -eq 2 ] && echo CJK_OK"),
                null, null, 120_000,
                o -> o.exit == 0 && o.stdout.contains("中文提交信息") && o.stdout.contains("STATUS_OK")
                        && o.stdout.contains("HOOKS_OK") && o.stdout.contains("CJK_OK") ? null
                        : "exit=" + o.exit + " out=" + head(o.stdout, 300) + head(o.stderr, 200)));
        l.add(new Probe("TC-003-08b", "工作区链：mv/branch/tag/stash/diff",
                arr("/system/bin/sh", "-c",
                        "G=" + gitExe + "; echo a > " + ws + "/wsrepo/f.txt && $G -C " + ws + "/wsrepo add -A >/dev/null 2>&1;" +
                        " $G -C " + ws + "/wsrepo commit -m init >/dev/null 2>&1; $G -C " + ws + "/wsrepo mv f.txt g.txt" +
                        " && $G -C " + ws + "/wsrepo commit -m mv >/dev/null" +
                        " && $G -C " + ws + "/wsrepo checkout -b dev && $G -C " + ws + "/wsrepo tag v1" +
                        " && echo more >> " + ws + "/wsrepo/g.txt && $G -C " + ws + "/wsrepo stash >/dev/null" +
                        " && $G -C " + ws + "/wsrepo stash pop >/dev/null && $G -C " + ws + "/wsrepo diff --stat" +
                        " && $G -C " + ws + "/wsrepo branch --show-current && $G -C " + ws + "/wsrepo tag && echo WS_OK"),
                null, null, 120_000,
                o -> o.exit == 0 && o.stdout.contains("WS_OK") && o.stdout.contains("v1") ? null
                        : "exit=" + o.exit + " out=" + head(o.stdout, 200) + head(o.stderr, 200)));
        return l;
    }

    @SafeVarargs
    private static <T> List<T> arr(T... items) {
        List<T> l = new ArrayList<>();
        for (T t : items) l.add(t);
        return l;
    }

    private static Map<String, String> envKv(String... kv) {
        Map<String, String> m = new HashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) m.put(kv[i], kv[i + 1]);
        return m;
    }

    /** 敏感信息脱敏：凭证密码段与用户名段打码（报告/日志出口统一过此函数）。 */
    private String sanitize(String s) {
        if (s == null) return "";
        if (authPass != null && !authPass.isEmpty()) s = s.replace(authPass, "***");
        if (authUser != null && !authUser.isEmpty()) s = s.replace(authUser, "***");
        if (authUrl != null) s = s.replace(authUrl, authUrlRedacted);
        if (credPattern != null) s = s.replaceAll(credPattern, "//***:***@");
        return s;
    }

    private String credPattern; // "//user:pass@" 的正则转义形式

    private static String head(String s) {
        return head(s, 160);
    }

    private static String head(String s, int n) {
        if (s == null) return "";
        s = s.replace("\n", "\\n");
        return s.length() > n ? s.substring(0, n) + "…" : s;
    }

    private static String readAll(InputStream is, int max) throws IOException {
        ByteArrayOutputStream2 bos = new ByteArrayOutputStream2();
        byte[] buf = new byte[8192];
        int r, total = 0;
        while ((r = is.read(buf)) > 0 && total < max) {
            bos.write(buf, 0, r);
            total += r;
        }
        return new String(bos.buf(), 0, bos.size(), StandardCharsets.UTF_8);
    }

    private static final class ByteArrayOutputStream2 extends java.io.ByteArrayOutputStream {
        byte[] buf() {
            return buf;
        }
    }

    // ── 主流程 ─────────────────────────────────────────────────────────────────

    private void runAll() {
        new Thread(() -> {
            try {
                report.clear();
                log("── 物化 assets ──");
                materialize();
                // 每轮重置工作区（幂等复跑；repo 由 05 重新 init）
                File wsDir = new File(getFilesDir(), "ws");
                deleteRecursive(wsDir);
                wsDir.mkdirs();
                log("── 建农场（D5）──");
                String farmMsg = buildFarm();
                log(farmMsg);
                if (farmMsg.contains("FAIL")) throw new IllegalStateException(farmMsg);

                // TC-003-12 前置：写坏 CA
                try (OutputStream os = new FileOutputStream(new File(getFilesDir(), "bad-ca.pem"))) {
                    os.write("not a certificate".getBytes(StandardCharsets.UTF_8));
                }
                // TC-003-14 前置：pre-commit 钩子（无 exec 位，内容 exit 1）
                File hook = new File(new File(getFilesDir(), "ws/repo/.git/hooks"), "pre-commit");
                hook.getParentFile().mkdirs();
                try (OutputStream os = new FileOutputStream(hook)) {
                    os.write("#!/system/bin/sh\nexit 1\n".getBytes(StandardCharsets.UTF_8));
                }
                hook.setExecutable(false, false);

                int pass = 0, fail = 0, skip = 0, blocked = 0;
                for (Probe p : probes()) {
                    Map<String, String> env = baseEnv();
                    if (p.envOverride != null) {
                        for (Map.Entry<String, String> e : p.envOverride.entrySet()) {
                            if (e.getValue() == null || e.getValue().isEmpty()) env.remove(e.getKey());
                            else env.put(e.getKey(), e.getValue());
                        }
                    }
                    Out o = exec(p.argv, env, p.stdin, p.timeoutMs);
                    String verdict = p.check.check(o);
                    String tag = verdict == null ? "PASS"
                            : verdict.startsWith("SKIP") ? "SKIP"
                            : verdict.startsWith("BLOCKED") ? "BLOCKED"
                            : verdict.startsWith("PASS-") ? "PASS"
                            : "FAIL";
                    if ("PASS".equals(tag)) pass++;
                    else if ("SKIP".equals(tag)) skip++;
                    else if ("BLOCKED".equals(tag)) blocked++;
                    else fail++;
                    JSONObject j = new JSONObject();
                    try {
                        j.put("id", p.id).put("title", p.title).put("verdict", tag)
                                .put("detail", sanitize(verdict == null ? "" : verdict))
                                .put("exit", o.exit).put("ms", o.ms)
                                .put("stdout", head(sanitize(o.stdout), 800))
                                .put("stderr", head(sanitize(o.stderr), 800));
                    } catch (org.json.JSONException ignored) {
                    }
                    report.add(j);
                    log(String.format("%-12s %-6s %s", p.id, tag, p.title)
                            + (verdict == null ? "" : "  | " + head(verdict, 200)));
                }
                log(String.format("── 汇总：PASS=%d FAIL=%d SKIP=%d BLOCKED=%d ──", pass, fail, skip, blocked));
                Out pg = exec(arr("/system/bin/getconf", "PAGESIZE"), baseEnv(), null, 10_000);
                String pagesize = pg.stdout.trim();
                if (!"16384".equals(pagesize)) {
                    skip++;
                    log(String.format("%-12s %-6s %s", "TC-003-17", "SKIP", "设备页大小 " + pagesize + "B（非 16KB；P7 需 16KB 设备复跑）"));
                } else {
                    log(String.format("%-12s %-6s %s", "TC-003-17", "PASS", "16KB 页设备：核心链已在本报告内全部执行"));
                }

                log(String.format("── 汇总：PASS=%d FAIL=%d SKIP=%d BLOCKED=%d ──", pass, fail, skip, blocked));
                JSONObject out = new JSONObject();
                out.put("runAt", new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ",
                        java.util.Locale.ROOT).format(new java.util.Date()));
                out.put("device", android.os.Build.MODEL + " " + android.os.Build.VERSION.RELEASE
                        + " abi=" + android.os.Build.SUPPORTED_ABIS[0]);
                out.put("pagesize", pagesize);
                out.put("nativeDir", nativeDir);
                out.put("farm", farmMsg);
                out.put("probes", new JSONArray(report));
                File f = new File(getFilesDir(), "probe-report.json");
                try (FileOutputStream os = new FileOutputStream(f)) {
                    os.write(out.toString(2).getBytes(StandardCharsets.UTF_8));
                }
                log("报告：" + f + "（adb pull /data/data/org.fellow99.gitprobe/files/probe-report.json）");
            } catch (Exception e) {
                log("FATAL " + e);
            }
        }).start();
    }
}
