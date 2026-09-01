pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// Pomodoro + recordatorio de ojos. Estado y notificaciones viven en
// ~/.local/bin/pomodoro.sh (archivos runtime + notify-send), así el timer
// sigue vivo aunque quickshell se reinicie. Este servicio solo consulta
// (1 s) y dispara subcomandos.
Item {
    id: pomodoroService

    property string state: "idle"   // idle|work|break|paused_work|paused_break
    property int remaining: 0
    property int workMin: 25
    property int breakMin: 5
    property int eyesMin: 20
    property bool eyesOn: true
    property int eyesIn: -1
    property int cycle: 0

    readonly property bool active: state !== "idle"
    readonly property bool paused: state === "paused_work" || state === "paused_break"

    function fmt(secs) {
        if (secs < 0) secs = 0;
        const m = Math.floor(secs / 60);
        const s = secs % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    function cmd(sub) {
        runProc.running = false;
        runProc.command = ["bash", "-c", 'exec "$HOME/.local/bin/pomodoro.sh" ' + sub];
        runProc.running = true;
    }

    function start() { cmd("start"); }
    function pause() { cmd("pause"); }
    function resume() { cmd("resume"); }
    function stop() { cmd("stop"); }
    function skip() { cmd("skip"); }
    function setConfig(k, v) { cmd("config " + k + " " + v); }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statusProc.running = false;
            statusProc.running = true;
        }
    }

    Process {
        id: statusProc
        command: ["bash", "-c", 'exec "$HOME/.local/bin/pomodoro.sh" status']
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split("\t");
                if (p.length < 8) return;
                pomodoroService.state = p[0];
                pomodoroService.remaining = parseInt(p[1]) || 0;
                pomodoroService.workMin = parseInt(p[2]) || 25;
                pomodoroService.breakMin = parseInt(p[3]) || 5;
                pomodoroService.eyesMin = parseInt(p[4]) || 20;
                pomodoroService.eyesOn = p[5] === "1";
                pomodoroService.eyesIn = parseInt(p[6]);
                pomodoroService.cycle = parseInt(p[7]) || 0;
            }
        }
    }

    Process {
        id: runProc
        command: ["true"]
        running: false
        onExited: {
            statusProc.running = false;
            statusProc.running = true;
        }
    }
}
