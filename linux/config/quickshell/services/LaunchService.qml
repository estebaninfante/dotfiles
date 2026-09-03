pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// Launcher (rofi → quickshell). Dueño de las fuentes de datos (apps/files/
// scripts), el filtrado y el arranque. La UI en menus/Launcher.qml.
// IPC: qs ipc call launcher {toggle|open|close} (arg modo ignorado)
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

    function dataFor() {
        return allApps.concat(allFiles, allScripts);
    }

    function reload() {
        loading = true;
        query = "";
        allApps = [];
        allFiles = [];
        allScripts = [];
        appsProcess.running = false; appsProcess.running = true;
        filesProcess.running = false; filesProcess.running = true;
        scriptsProcess.running = false; scriptsProcess.running = true;
    }

    function updateSearch() {
        var q = query.trim().toLowerCase();
        var src = dataFor();
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
        // systemd-run --scope saca la app del cgroup de quickshell.service:
        // sobrevive restarts de quickshell (y no la mata un segundo launch).
        // --setenv: systemd-run --scope NO hereda env de Hyprland (hl.env()),
        // así que hay que pasar explícitamente las vars que las apps necesitan.
        runnerProcess.command = [
            "systemd-run", "--user", "--scope", "--collect", "--quiet",
            "--setenv", "ELECTRON_OZONE_PLATFORM_HINT=wayland",
        ].concat(args);
        runnerProcess.running = true;
    }

    function copyToClipboard(text) {
        run(["bash", "-c", 'printf %s "' + text + '" | wl-copy']);
    }

    // ── IPC (qs ipc call launcher toggle|open|close) ───────────
    IpcHandler {
        target: "launcher"

        function toggle(mode: string): void {
            UIState.launcherOpen = !UIState.launcherOpen;
        }

        function open(mode: string): void {
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
                launchService.reload();
            else
                launchService.results = [];
        }
    }

    // Los tres producers corren en paralelo: solo filtrar
    // cuando los tres hayan terminado (si no, resultados parciales).
    function onProducerDone() {
        if (appsProcess.running || filesProcess.running || scriptsProcess.running) return;
        loading = false;
        updateSearch();
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
                onProducerDone();
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
                onProducerDone();
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
                onProducerDone();
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