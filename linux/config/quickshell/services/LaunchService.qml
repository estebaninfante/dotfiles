pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// Launcher (rofi → quickshell). Dueño de las fuentes de datos (apps/files/
// scripts), el filtrado y el arranque. La UI en menus/Launcher.qml.
// IPC: qs ipc call launcher {toggle|open|close} [mode]
Item {
    id: launchService

    property var results: []
    property string query: ""
    property bool loading: false

    property var allApps: []
    property var allFiles: []
    property var allScripts: []

    readonly property string codeExts: "py|sh|lua|qml|json|conf|md|txt|js|ts|tsx|jsx|html|css|rasi|yaml|toml|zsh|bash|env|ini|sql|lock|csv|xml|nix"

    function isCodeFile(path) {
        return path.search(RegExp("\\.(" + codeExts + ")$", "i")) >= 0;
    }

    function dataFor(mode) {
        if (mode === "apps") return allApps;
        if (mode === "files") return allFiles;
        return allScripts;
    }

    function reload(mode) {
        loading = true;
        query = "";
        if (mode === "apps") {
            allApps = [];
            appsProcess.running = false; appsProcess.running = true;
        } else if (mode === "files") {
            allFiles = [];
            filesProcess.running = false; filesProcess.running = true;
        } else {
            allScripts = [];
            scriptsProcess.running = false; scriptsProcess.running = true;
        }
    }

    function updateSearch() {
        var q = query.trim().toLowerCase();
        var src = dataFor(UIState.launcherMode);
        var out = [];
        for (var i = 0; i < src.length; i++) {
            var e = src[i];
            var hay = e.name + " " + (e.sub || "");
            if (hay.toLowerCase().indexOf(q) >= 0) {
                out.push(e);
                if (out.length >= 200) break;
            }
        }
        results = out;
    }

    // ── Arranque (paridad exacta con rofi) ─────────────────────
    function launch(item) {
        if (item.kind === "app") {
            run(["sh", "-c", item.exec]);
        } else if (item.kind === "script") {
            runScript(item.path);
        } else {
            openFile(item);
        }
        UIState.launcherOpen = false;
    }

    function openFile(item) {
        if (item.isDir) {
            run(["xdg-open", item.path]);
        } else if (launchService.isCodeFile(item.path)) {
            run(["kitty", "-d", item.dir, "-e", "nvim", item.path]);
        } else {
            run(["xdg-open", item.path]);
        }
    }

    function runScript(path) {
        if (path.indexOf("/scripts/") >= 0 || path.indexOf("/linux/") >= 0)
            run(["kitty", "-e", path]);
        else
            run(["sh", "-c", path]);
    }

    function run(args) {
        runnerProcess.running = false;
        // Fork (sh hijo) + scope: la app queda como nieto de quickshell
        // y en cgroup propio → sobrevive hot-reload Y restart.
        var cmd = args.map(function(a) { return "'" + a.replace(/'/g, "'\\''") + "'"; }).join(" ");
        runnerProcess.command = [
            "systemd-run", "--user", "--scope", "--collect", "--quiet",
            "sh", "-c", "sh -c " + cmd + " &"
        ];
        runnerProcess.running = true;
    }

    function copyToClipboard(text) {
        run(["bash", "-c", 'printf %s "' + text + '" | wl-copy']);
    }

    // ── IPC (qs ipc call launcher toggle|open|close) ───────────
    IpcHandler {
        target: "launcher"

        function toggle(mode: string): void {
            if (UIState.launcherOpen && UIState.launcherMode === mode)
                UIState.launcherOpen = false;
            else {
                UIState.launcherMode = mode;
                UIState.launcherOpen = true;
            }
        }

        function open(mode: string): void {
            UIState.launcherMode = mode;
            UIState.launcherOpen = true;
        }

        function close(): void {
            UIState.launcherOpen = false;
        }
    }

    // ── Disparos de carga / filtrado ───────────────────────────
    Connections {
        target: UIState
        function onLauncherOpenChanged() {
            if (UIState.launcherOpen)
                launchService.reload(UIState.launcherMode);
            else
                launchService.results = [];
        }
        function onLauncherModeChanged() {
            if (UIState.launcherOpen)
                launchService.reload(UIState.launcherMode);
        }
    }

    // ── Producers ──────────────────────────────────────────────
    function parseFileLine(line) {
        var p = line.split("\t");
        if (p.length < 6) return null;
        return { kind: "file", name: p[0], path: p[1], dir: p[2], sub: p[3], isDir: p[4] === "1", isExec: p[5] === "1" };
    }

    Process {
        id: appsProcess
        command: ["bash", "-c", 'exec "$HOME/.local/bin/apps-list.sh"']
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.length === 0) return;
                var p = data.split("\t");
                if (p.length >= 2)
                    allApps.push({ kind: "app", name: p[0], exec: p[1], icon: p.length >= 3 ? p[2] : "" });
            }
        }
        onRunningChanged: {
            if (!running) {
                loading = false;
                updateSearch();
            }
        }
    }

    Process {
        id: filesProcess
        command: ["bash", "-c", 'exec "$HOME/.local/bin/file-list.sh"']
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.length === 0) return;
                var p = launchService.parseFileLine(data);
                if (p !== null) allFiles.push(p);
            }
        }
        onRunningChanged: {
            if (!running) {
                loading = false;
                updateSearch();
            }
        }
    }

    Process {
        id: scriptsProcess
        command: ["bash", "-c", 'exec "$HOME/.local/bin/script-list.sh"']
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.length === 0) return;
                var p = data.split("\t");
                if (p.length >= 2)
                    allScripts.push({ kind: "script", name: p[0], path: p[1] });
            }
        }
        onRunningChanged: {
            if (!running) {
                loading = false;
                updateSearch();
            }
        }
    }

    // ── Lanzador genérico ──────────────────────────────────────
    Process {
        id: runnerProcess
        command: ["true"]
        running: false
    }
}