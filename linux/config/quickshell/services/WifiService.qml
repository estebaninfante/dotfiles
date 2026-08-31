pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: wifiService

    property bool wifiOn: false
    property string network: "Sin conexión"
    property bool wifiDetailsOpen: false
    property string wifiMessage: ""
    property string selectedSsid: ""
    property string wifiState: "disconnected" // off | disconnected | connecting | connected | failed
    property string lastError: ""
    property int wifiSignal: 0
    property string wifiPassword: ""
    property bool wifiAdvancedOpen: false
    property string wifiIdentity: ""
    property string wifiAnonymousIdentity: ""
    property string wifiEap: "peap"
    property string wifiPhase2: "mschapv2"
    property string wifiCaCert: ""
    property string wifiClientCert: ""
    property string wifiClientKey: ""
    property string wifiDomain: ""
    property var wifiNetworks: ListModel {}
    property var wifiScanNetworks: ListModel {}

    function refreshNetworks() {
        wifiService.wifiMessage = "Buscando redes...";
        wifiScanNetworks.clear();
        wifiScan.running = false;
        wifiScan.running = true;
    }

    function toggleNetwork(index) {
        for (let i = 0; i < wifiNetworks.count; i++)
            wifiNetworks.setProperty(i, "expanded", i === index ? !wifiNetworks.get(i).expanded : false);
        wifiService.selectedSsid = wifiNetworks.get(index).ssid;
        wifiService.wifiAdvancedOpen = false;
        wifiService.wifiMessage = wifiService.selectedSsid + " seleccionada";
    }

    function connectNetwork(ssid) {
        wifiService.selectedSsid = ssid;
        if (wifiService.wifiState === "connecting")
            return;
        wifiConnect.command = wifiService.connectCommand();
        wifiService.wifiState = "connecting";
        wifiService.lastError = "";
        wifiService.wifiMessage = "Conectando a " + ssid + "…";
        wifiConnect.running = false;
        wifiConnect.running = true;
    }

    function connErrorMessage(raw, code) {
        const t = (raw || "").trim();
        if (!t)
            return "No se pudo conectar (error " + code + ")";
        if (/secret|password|contrase/i.test(t))
            return "Contraseña incorrecta o rechazada";
        if (/timed?[\s-]*out|timeout/i.test(t))
            return "Tiempo agotado — reintenta cerca del router";
        if (/no network with ssid/i.test(t))
            return "Red no encontrada — escanea de nuevo";
        if (/no suitable device|not enabled|not available/i.test(t))
            return "Wi-Fi desactivado o sin adaptador";
        const lines = t.split("\n").filter(l => l.trim());
        const reason = lines.length ? lines[lines.length - 1].trim().replace(/^.*?:\s*/, "") : "";
        if (!reason)
            return "No se pudo conectar (error " + code + ")";
        return "No se pudo conectar: " + (reason.length > 70 ? reason.slice(0, 67) + "…" : reason);
    }

    function parseNetwork(line) {
        const match = line.trim().match(/^(.*):([0-9]+):(.*)$/);
        if (!match || !match[1])
            return;
        const ssid = match[1].replace(/\\\\:/g, ":").replace(/\\\\\\\\/g, "\\\\");
        const signal = match[2];
        const security = match[3];
        for (let i = 0; i < wifiService.wifiNetworks.count; i++) {
            if (wifiService.wifiNetworks.get(i).ssid === ssid)
                return;
        }
        wifiScanNetworks.append({
            ssid: ssid,
            signal: signal,
            security: security || "Abierta",
            expanded: false
        });
    }

    function connectCommand() {
        let args = ["nmcli", "dev", "wifi", "connect", wifiService.selectedSsid];
        if (wifiService.wifiPassword)
            args.push("password", wifiService.wifiPassword);
        if (wifiService.wifiAdvancedOpen && wifiService.wifiIdentity) {
            args.push("wifi-sec.key-mgmt", "wpa-eap");
            args.push("802-1x.identity", wifiService.wifiIdentity);
            args.push("802-1x.eap", wifiService.wifiEap || "peap");
            args.push("802-1x.phase2-auth", wifiService.wifiPhase2 || "mschapv2");
            if (wifiService.wifiAnonymousIdentity)
                args.push("802-1x.anonymous-identity", wifiService.wifiAnonymousIdentity);
            if (wifiService.wifiCaCert)
                args.push("802-1x.ca-cert", wifiService.wifiCaCert);
            if (wifiService.wifiClientCert)
                args.push("802-1x.client-cert", wifiService.wifiClientCert);
            if (wifiService.wifiClientKey)
                args.push("802-1x.private-key", wifiService.wifiClientKey);
            if (wifiService.wifiDomain)
                args.push("802-1x.domain", wifiService.wifiDomain);
        }
        return args;
    }

    Process {
        id: wifiScan
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => wifiService.parseNetwork(line)
        }
        onExited: {
            if (wifiService.wifiScanNetworks.count) {
                wifiService.wifiNetworks.clear();
                for (let i = 0; i < wifiService.wifiScanNetworks.count; i++) {
                    const network = wifiService.wifiScanNetworks.get(i);
                    wifiService.wifiNetworks.append({ ssid: network.ssid, signal: network.signal, security: network.security, expanded: false });
                }
                wifiService.wifiMessage = "Selecciona una red";
            } else if (!wifiService.wifiNetworks.count) {
                wifiService.wifiMessage = "nmcli no disponible o sin redes";
            } else {
                wifiService.wifiMessage = "No se encontraron redes nuevas";
            }
            wifiService.wifiScanNetworks.clear();
        }
    }

    Process {
        id: wifiConnect
        command: ["nmcli", "dev", "wifi", "connect", ""]
        running: false
        stderr: StdioCollector {
            id: wifiConnectErr
        }
        onExited: {
            if (exitCode === 0) {
                wifiService.wifiState = "connected";
                wifiService.lastError = "";
                wifiService.wifiMessage = "Conectado a " + wifiService.selectedSsid;
                wifiService.wifiPassword = "";
            } else {
                wifiService.wifiState = "failed";
                wifiService.lastError = wifiService.connErrorMessage(wifiConnectErr.text, exitCode);
                wifiService.wifiMessage = wifiService.lastError;
            }
            wifiStatus.running = false;
            wifiStatus.running = true;
        }
    }

    Process {
        id: wifiStatus
        command: ["bash", "-c", "export LC_ALL=C; enabled=$(nmcli -t -f WIFI g | head -n1); network=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1==\"yes\"{sub(/^yes:/,\"\"); print; exit}'); signal=$(nmcli -t -f active,signal dev wifi | awk -F: '$1==\"yes\"{print $2; exit}'); wired=$(nmcli -t -f TYPE,STATE,CONNECTION dev | awk -F: '$1==\"ethernet\" && $2==\"connected\"{print $3; exit}'); printf '%s|%s|%s|%s' \"$enabled\" \"$network\" \"$wired\" \"$signal\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                if (wifiService.wifiState === "connecting")
                    return;
                const parts = this.text.trim().split("|");
                wifiService.wifiOn = parts[0] === "enabled";
                wifiService.wifiSignal = parseInt(parts[3]) || 0;
                const net = parts[1] || "";
                const wired = parts[2] || "";
                if (!wifiService.wifiOn) {
                    wifiService.network = "Desactivado";
                    wifiService.wifiState = "off";
                } else if (net) {
                    wifiService.network = net;
                    wifiService.wifiState = "connected";
                } else if (wired) {
                    wifiService.network = "Cable: " + wired;
                    wifiService.wifiState = "connected";
                } else {
                    wifiService.network = "Sin conexión";
                    if (wifiService.wifiState !== "failed")
                        wifiService.wifiState = "disconnected";
                }
            }
        }
    }

    Process {
        id: wifiToggle
        command: ["nmcli", "radio", "wifi", "toggle"]
        running: false

        onExited: {
            wifiStatus.running = false;
            wifiStatus.running = true;
        }
    }

    Timer {
        interval: 20000
        running: UIState.widgetMenuOpen && UIState.activeSection === "conexiones"
        repeat: true
        onTriggered: {
            wifiStatus.running = true;
            if (wifiService.wifiOn && !wifiScan.running)
                wifiService.refreshNetworks();
        }
    }
}