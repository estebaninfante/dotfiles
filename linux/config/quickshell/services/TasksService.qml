pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// Tareas del centro (DateMenu): lee/escribe la nota diaria del vault
// Obsidian vía ~/.local/bin/tasks-ctl.sh. La nota es la fuente de verdad.
Item {
    id: tasksService

    property var tasks: []          // {idx, done, prio, text}
    property var acc: []
    property bool loading: false
    property bool vaultOk: true

    function refresh() {
        loading = true;
        acc = [];
        listProc.running = false;
        listProc.running = true;
    }

    function add(text) {
        const t = text.trim();
        if (t.length === 0) return;
        runOp("add", t);
    }

    function toggle(idx) { runOp("toggle", String(idx)); }
    function del(idx) { runOp("del", String(idx)); }

    function runOp(op, arg) {
        opProc.running = false;
        opProc.command = ["bash", "-c", 'exec "$HOME/.local/bin/tasks-ctl.sh" ' + op + ' "$1"', "sh", arg];
        opProc.running = true;
    }

    Connections {
        target: UIState
        function onDateMenuOpenChanged() {
            if (UIState.dateMenuOpen) tasksService.refresh();
        }
    }

    Process {
        id: listProc
        command: ["bash", "-c", 'exec "$HOME/.local/bin/tasks-ctl.sh" list']
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.length === 0) return;
                const p = data.split("\t");
                if (p.length < 3) return;
                const text = p.slice(2).join("\t");
                let prio = "";
                if (text.indexOf("\u{1F53A}") === 0) prio = "alta";
                else if (text.indexOf("\u{1F53C}") === 0) prio = "media";
                else if (text.indexOf("\u{1F53D}") === 0) prio = "baja";
                tasksService.acc.push({ idx: parseInt(p[0]), done: p[1] === "1", prio: prio, text: text });
            }
        }
        onRunningChanged: {
            if (!running) {
                tasksService.vaultOk = exitCode === 0;
                tasksService.tasks = tasksService.acc;
                tasksService.loading = false;
            }
        }
    }

    Process {
        id: opProc
        command: ["true"]
        running: false
        onExited: tasksService.refresh()
    }
}
