pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: dashboardService

    property double cpuUsage: 0
    property double cpuTemp: 0
    property double gpuUsage: 0
    property double gpuTemp: 0
    property double gpuMemory: 0
    property double gpuMemoryTotal: 0
    property double gpuPower: 0
    property double gpuPowerLimit: 0
    property double rootDisk: 0
    property string systemLoad: "--"
    property string systemUptime: "--"
    property bool gpuTelemetryAvailable: false
    property var cpuThreads: ListModel {}
    property var ramProcesses: ListModel {}

    function refreshMonitoring() {
        if (UIState.activeSection === "monitoreo" && !telemetryStatus.running)
            telemetryStatus.running = true;
    }

    function openMonitorDetail(detail) {
        UIState.monitorDetail = detail;
        refreshMonitoring();
        if (detail === "ram")
            ramOpen();
        if (detail === "cpu")
            cpuThreadsOpen();
    }

    function ramOpen() {
        ramProcesses.clear();
        ramProcessesStatus.running = true;
    }

    function cpuThreadsOpen() {
        cpuThreads.clear();
        cpuThreadsStatus.running = true;
    }

    Process {
        id: telemetryStatus
        command: ["bash", "-c", "read -r _ u n s i w irq sirq st _ < /proc/stat; a=$((u+n+s+i+w+irq+sirq+st)); b=$i; sleep .15; read -r _ u n s i w irq sirq st _ < /proc/stat; c=$((u+n+s+i+w+irq+sirq+st)); d=$i; cpu=$(awk -v da=$((c-a)) -v di=$((d-b)) 'BEGIN { if (da > 0) print 100 * (da-di) / da; else print 0 }'); temp=$(for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); case $n in coretemp|k10temp|zenpower|cpu_thermal) for f in $h/temp*_input; do awk '{print int($1/1000)}' $f; done;; esac; done | sort -nr | head -n1); [ -n $temp ] || temp=0; load=$(awk '{print $1}' /proc/loadavg); up=$(cut -d. -f1 /proc/uptime); disk=$(df -P / | awk 'NR==2 {print $5}'); gpu=none; if command -v nvidia-smi >/dev/null 2>&1; then gpu=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,power.limit --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' '); fi; printf '%s|%s|%s|%s|%s|%s\\n' $cpu $temp $load $up $disk $gpu"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split("|");
                if (p.length < 6)
                    return;
                dashboardService.cpuUsage = Math.max(0, Math.min(100, parseFloat(p[0]) || 0));
                dashboardService.cpuTemp = parseFloat(p[1]) || 0;
                dashboardService.systemLoad = p[2] || "--";
                dashboardService.systemUptime = p[3] || "--";
                dashboardService.rootDisk = parseFloat(p[4]) || 0;
                const g = p[5].split(",");
                dashboardService.gpuTelemetryAvailable = g.length >= 6;
                dashboardService.gpuUsage = parseFloat(g[0]) || 0;
                dashboardService.gpuTemp = parseFloat(g[1]) || 0;
                dashboardService.gpuMemory = parseFloat(g[2]) || 0;
                dashboardService.gpuMemoryTotal = parseFloat(g[3]) || 0;
                dashboardService.gpuPower = parseFloat(g[4]) || 0;
                dashboardService.gpuPowerLimit = parseFloat(g[5]) || 0;
            }
        }
    }

    Process {
        id: cpuThreadsStatus
        command: ["bash", "-c", "a=$(mktemp); b=$(mktemp); awk '/^cpu[0-9]+ / {print}' /proc/stat > $a; sleep .15; awk '/^cpu[0-9]+ / {print}' /proc/stat > $b; awk 'NR==FNR {u[$1]=$2; n[$1]=$3; s[$1]=$4; i[$1]=$5; w[$1]=$6; q[$1]=$7+$8+$9; next} {old=u[$1]+n[$1]+s[$1]+i[$1]+w[$1]+q[$1]; now=$2+$3+$4+$5+$6+$7+$8+$9; total=now-old; idle=$5-i[$1]; if (total > 0) print $1, 100*(total-idle)/total}' $a $b; rm -f $a $b"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const p = line.trim().split(/\s+/);
                if (p.length === 2)
                    dashboardService.cpuThreads.append({ threadName: p[0], threadUsage: p[1] });
            }
        }
    }

    Process {
        id: ramProcessesStatus
        command: ["bash", "-c", "ps -eo comm=,rss= --sort=-rss | awk 'NR <= 8 {printf \"%s|%.0f\\n\", $1, $2/1024}'"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { const p = line.trim().split("|"); if (p.length === 2) dashboardService.ramProcesses.append({ processName: p[0], memory: p[1] }); }
        }
    }

    Timer {
        interval: 2500
        running: UIState.widgetMenuOpen && UIState.activeSection === "monitoreo"
        repeat: true
        onTriggered: dashboardService.refreshMonitoring()
    }
}