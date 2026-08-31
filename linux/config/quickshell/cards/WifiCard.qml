import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

Rectangle {
    id: wifiCard
    width: parent.width
    height: wifiDetailsOpen ? 70 + wifiDetails.implicitHeight + 12 : 70
    radius: 12
    color: "#000000"
    border.color: wifiCard.wifiState === "failed" ? "#eba0ac" : "#333"
    border.width: 1
    visible: UIState.activeSection === "conexiones"

    readonly property bool wifiScanning: wifiScan.running

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
        wifiCard.wifiMessage = "Buscando redes...";
        wifiScanNetworks.clear();
        wifiScan.running = false;
        wifiScan.running = true;
    }

    function toggleNetwork(index) {
        for (let i = 0; i < wifiNetworks.count; i++)
            wifiNetworks.setProperty(i, "expanded", i === index ? !wifiNetworks.get(i).expanded : false);
        wifiCard.selectedSsid = wifiNetworks.get(index).ssid;
        wifiCard.wifiAdvancedOpen = false;
        wifiCard.wifiMessage = wifiCard.selectedSsid + " seleccionada";
    }

    function connectNetwork(ssid) {
        wifiCard.selectedSsid = ssid;
        if (wifiCard.wifiState === "connecting")
            return;
        wifiConnect.command = wifiCard.connectCommand();
        wifiCard.wifiState = "connecting";
        wifiCard.lastError = "";
        wifiCard.wifiMessage = "Conectando a " + ssid + "…";
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
        for (let i = 0; i < wifiCard.wifiNetworks.count; i++) {
            if (wifiCard.wifiNetworks.get(i).ssid === ssid)
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
        let args = ["nmcli", "dev", "wifi", "connect", wifiCard.selectedSsid];
        if (wifiCard.wifiPassword)
            args.push("password", wifiCard.wifiPassword);
        if (wifiCard.wifiAdvancedOpen && wifiCard.wifiIdentity) {
            args.push("wifi-sec.key-mgmt", "wpa-eap");
            args.push("802-1x.identity", wifiCard.wifiIdentity);
            args.push("802-1x.eap", wifiCard.wifiEap || "peap");
            args.push("802-1x.phase2-auth", wifiCard.wifiPhase2 || "mschapv2");
            if (wifiCard.wifiAnonymousIdentity)
                args.push("802-1x.anonymous-identity", wifiCard.wifiAnonymousIdentity);
            if (wifiCard.wifiCaCert)
                args.push("802-1x.ca-cert", wifiCard.wifiCaCert);
            if (wifiCard.wifiClientCert)
                args.push("802-1x.client-cert", wifiCard.wifiClientCert);
            if (wifiCard.wifiClientKey)
                args.push("802-1x.private-key", wifiCard.wifiClientKey);
            if (wifiCard.wifiDomain)
                args.push("802-1x.domain", wifiCard.wifiDomain);
        }
        return args;
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 10
        height: 58
        spacing: 10

        Text {
            text: wifiCard.wifiOn ? "\uf1eb" : "\uf127"
            color: wifiCard.wifiState === "connected" ? "white" : wifiCard.wifiState === "connecting" ? "white" : wifiCard.wifiState === "failed" ? "#eba0ac" : wifiCard.wifiOn ? "white" : "#555"
            font.family: Theme.fontFamily
            font.pixelSize: 24
            Layout.preferredWidth: 28
        }

        Column {
            spacing: 2

            Text {
                text: "WI-FI"
                color: "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 1.5
            }

            Text {
                text: {
                    if (!wifiCard.wifiOn)
                        return "Desactivado";
                    if (wifiCard.wifiState === "connecting")
                        return "Conectando a " + (wifiCard.selectedSsid || "red") + "…";
                    if (wifiCard.wifiState === "failed")
                        return wifiCard.lastError || "No se pudo conectar";
                    const sig = wifiCard.wifiSignal > 0 && wifiCard.wifiState === "connected" && !wifiCard.network.startsWith("Cable:") ? "  ·  " + wifiCard.wifiSignal + "%" : "";
                    return wifiCard.network + sig;
                }
                color: wifiCard.wifiState === "failed" ? "#eba0ac" : wifiCard.wifiState === "connecting" ? "white" : wifiCard.wifiState === "connected" ? "white" : "white"
                font.family: Theme.fontFamily
                font.pixelSize: 17
                elide: Text.ElideRight
                width: 245
                MouseArea {
                    anchors.fill: parent
                    onClicked: wifiCard.wifiDetailsOpen = !wifiCard.wifiDetailsOpen
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            visible: wifiCard.wifiState === "connecting"
            text: "\uf110"
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: 13

            RotationAnimation on rotation {
                running: wifiCard.wifiState === "connecting"
                loops: Animation.Infinite
                duration: 1000
                from: 0
                to: 360
            }
        }

        Rectangle {
            width: 48
            height: 30
            radius: 9
            color: wifiToggleArea.containsMouse ? "white" : "#141414"

            Text {
                anchors.centerIn: parent
                text: wifiCard.wifiOn ? "ON" : "OFF"
                color: wifiToggleArea.containsMouse ? "#000000" : "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
            }

            MouseArea {
                id: wifiToggleArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    wifiToggle.running = false;
                    wifiToggle.running = true;
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.bottomMargin: parent.height - 78
        anchors.rightMargin: 62
        z: 1
        onClicked: wifiCard.wifiDetailsOpen = !wifiCard.wifiDetailsOpen
    }

    Column {
        id: wifiDetails
        anchors.top: parent.top
        anchors.topMargin: 84
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 9
        visible: wifiCard.wifiDetailsOpen
        opacity: wifiCard.wifiDetailsOpen ? 1 : 0

        RowLayout {
            visible: false
            width: parent.width
            spacing: 6

            TextInput {
                id: wifiPasswordInput
                Layout.fillWidth: true
                height: 34
                color: "white"
                text: wifiCard.wifiPassword
                font.family: Theme.fontFamily
                font.pixelSize: 11
                echoMode: TextInput.Password
                padding: 7
                selectByMouse: true
                clip: true
                onTextChanged: wifiCard.wifiPassword = text
                Rectangle {
                    anchors.fill: parent
                    z: -1
                    radius: 8
                    color: "#000000"
                    border.color: "#333"
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Contraseña"
                    color: "#555"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    visible: !wifiPasswordInput.text
                }
            }

            Rectangle {
                width: 96
                height: 34
                radius: 8
                color: wifiRefreshArea.containsMouse ? "white" : "#141414"
                Text {
                    anchors.centerIn: parent
                    text: "ESCANEAR"
                    color: wifiRefreshArea.containsMouse ? "#000000" : "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                }
                MouseArea {
                    id: wifiRefreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: wifiCard.refreshNetworks()
                }
            }

        }

        Rectangle {
            visible: false
            width: parent.width
            height: 32
            radius: 8
            color: wifiCard.wifiAdvancedOpen ? "white" : wifiAdvancedArea.containsMouse ? "#1d1d26" : "#141414"
            Text {
                anchors.centerIn: parent
                text: wifiCard.wifiAdvancedOpen ? "OCULTAR CONFIGURACIÓN EMPRESARIAL" : "CONFIGURACIÓN EMPRESARIAL (802.1X)"
                color: wifiCard.wifiAdvancedOpen ? "#000000" : "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.bold: true
            }
            MouseArea {
                id: wifiAdvancedArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: wifiCard.wifiAdvancedOpen = !wifiCard.wifiAdvancedOpen
            }
        }

        Column {
            width: parent.width
            spacing: 6
            visible: false

            Text {
                text: "RED UNIVERSITARIA O DE EMPRESA"
                color: "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.bold: true
            }

            Text {
                width: parent.width
                text: "Usa esta opción solo si la red pide usuario además de contraseña."
                color: "#555"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                wrapMode: Text.WordWrap
            }

            RowLayout {
                width: parent.width
                spacing: 6
                TextInput {
                    Layout.fillWidth: true
                    height: 32
                    color: "white"
                    text: wifiCard.wifiIdentity
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    padding: 7
                    onTextChanged: wifiCard.wifiIdentity = text
                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                    Text { anchors.fill: parent; anchors.margins: 7; text: "Usuario / identidad"; color: "#555"; font: parent.font; visible: !parent.text }
                }
                TextInput {
                    Layout.fillWidth: true
                    height: 32
                    color: "white"
                    text: wifiCard.wifiEap
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    padding: 7
                    onTextChanged: wifiCard.wifiEap = text
                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                    Text { anchors.fill: parent; anchors.margins: 7; text: "EAP: peap / tls"; color: "#555"; font: parent.font; visible: !parent.text }
                }
            }

            RowLayout {
                width: parent.width
                spacing: 6
                TextInput {
                    Layout.fillWidth: true
                    height: 32
                    color: "white"
                    text: wifiCard.wifiPhase2
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    padding: 7
                    onTextChanged: wifiCard.wifiPhase2 = text
                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                    Text { anchors.fill: parent; anchors.margins: 7; text: "Fase 2: mschapv2"; color: "#555"; font: parent.font; visible: !parent.text }
                }
                TextInput {
                    Layout.fillWidth: true
                    height: 32
                    color: "white"
                    text: wifiCard.wifiAnonymousIdentity
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    padding: 7
                    onTextChanged: wifiCard.wifiAnonymousIdentity = text
                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                    Text { anchors.fill: parent; anchors.margins: 7; text: "Identidad anónima (opcional)"; color: "#555"; font: parent.font; visible: !parent.text }
                }
            }

            RowLayout {
                width: parent.width
                spacing: 6
                TextInput {
                    Layout.fillWidth: true
                    height: 32
                    color: "white"
                    text: wifiCard.wifiCaCert
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    padding: 7
                    onTextChanged: wifiCard.wifiCaCert = text
                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                    Text { anchors.fill: parent; anchors.margins: 7; text: "Certificado CA (opcional)"; color: "#555"; font: parent.font; visible: !parent.text }
                }
                TextInput {
                    Layout.fillWidth: true
                    height: 32
                    color: "white"
                    text: wifiCard.wifiDomain
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    padding: 7
                    onTextChanged: wifiCard.wifiDomain = text
                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                    Text { anchors.fill: parent; anchors.margins: 7; text: "Dominio (opcional)"; color: "#555"; font: parent.font; visible: !parent.text }
                }
            }

            RowLayout {
                width: parent.width
                spacing: 6
                TextInput {
                    Layout.fillWidth: true
                    height: 32
                    color: "white"
                    text: wifiCard.wifiClientCert
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    padding: 7
                    onTextChanged: wifiCard.wifiClientCert = text
                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                    Text { anchors.fill: parent; anchors.margins: 7; text: "Certificado cliente (EAP-TLS)"; color: "#555"; font: parent.font; visible: !parent.text }
                }
                TextInput {
                    Layout.fillWidth: true
                    height: 32
                    color: "white"
                    text: wifiCard.wifiClientKey
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    padding: 7
                    onTextChanged: wifiCard.wifiClientKey = text
                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                    Text { anchors.fill: parent; anchors.margins: 7; text: "Clave privada (EAP-TLS)"; color: "#555"; font: parent.font; visible: !parent.text }
                }
            }
        }

        RowLayout {
            width: parent.width
            spacing: 6
            Text {
                text: wifiCard.wifiNetworks.count ? "REDES DISPONIBLES" : wifiCard.wifiMessage
                color: "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Rectangle {
                width: 86
                height: 28
                radius: 7
                color: wifiScanArea.containsMouse ? "white" : "#141414"
                Text { anchors.centerIn: parent; text: "ESCANEAR"; color: wifiScanArea.containsMouse ? "#000000" : "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 8; font.bold: true }
                MouseArea { id: wifiScanArea; anchors.fill: parent; hoverEnabled: true; onClicked: wifiCard.refreshNetworks() }
            }
        }

        ListView {
            width: parent.width
            height: Math.min(contentHeight, 360)
            visible: count > 0
            clip: true
            model: wifiCard.wifiNetworks
            spacing: 3
            delegate: Rectangle {
                required property string ssid
                required property string signal
                required property string security
                required property bool expanded
                width: wifiDetails.width
                height: expanded ? 34 + networkDetails.implicitHeight + 10 : 34
                radius: 7
                color: wifiNetworkArea.containsMouse ? "#1d1d26" : "#141414"
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 34
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    Text {
                        Layout.fillWidth: true
                        text: ssid + "  " + signal + "%"
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        text: security
                        color: "#aaa"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                }
                MouseArea {
                    id: wifiNetworkArea
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 34
                    hoverEnabled: true
                    onClicked: {
                        wifiCard.toggleNetwork(index);
                        if (wifiCard.wifiState === "failed") {
                            wifiCard.wifiState = "disconnected";
                            wifiCard.lastError = "";
                        }
                    }
                }

                Column {
                    id: networkDetails
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 40
                    spacing: 6
                    visible: expanded

                    RowLayout {
                        width: parent.width
                        spacing: 6
                        TextInput {
                            id: networkPasswordInput
                            Layout.fillWidth: true
                            height: 32
                            color: "white"
                            text: wifiCard.wifiPassword
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            echoMode: TextInput.Password
                            padding: 7
                            onTextChanged: wifiCard.wifiPassword = text
                            Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                            Text { anchors.fill: parent; anchors.margins: 7; text: "Contraseña"; color: "#555"; font: parent.font; visible: !parent.text }
                        }
                        Rectangle {
                            width: 84
                            height: 32
                            radius: 8
                            color: wifiCard.wifiAdvancedOpen ? "white" : networkAdvancedArea.containsMouse ? "#1d1d26" : "#141414"
                            Text { anchors.centerIn: parent; text: "AVANZADO"; color: wifiCard.wifiAdvancedOpen ? "#000000" : "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 8; font.bold: true }
                            MouseArea { id: networkAdvancedArea; anchors.fill: parent; hoverEnabled: true; onClicked: wifiCard.wifiAdvancedOpen = !wifiCard.wifiAdvancedOpen }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 6
                        visible: wifiCard.wifiAdvancedOpen
                        Text { text: "RED EMPRESARIAL / 802.1X"; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 8; font.bold: true }
                        RowLayout {
                            width: parent.width
                            spacing: 6
                            TextInput {
                                Layout.fillWidth: true; height: 32; color: "white"; text: wifiCard.wifiIdentity; font.family: Theme.fontFamily; font.pixelSize: 10; padding: 7
                                onTextChanged: wifiCard.wifiIdentity = text
                                Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                                Text { anchors.fill: parent; anchors.margins: 7; text: "Usuario / identidad"; color: "#555"; font: parent.font; visible: !parent.text }
                            }
                            TextInput {
                                Layout.fillWidth: true; height: 32; color: "white"; text: wifiCard.wifiEap; font.family: Theme.fontFamily; font.pixelSize: 10; padding: 7
                                onTextChanged: wifiCard.wifiEap = text
                                Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                                Text { anchors.fill: parent; anchors.margins: 7; text: "EAP: peap / tls"; color: "#555"; font: parent.font; visible: !parent.text }
                            }
                        }
                        TextInput {
                            width: parent.width; height: 32; color: "white"; text: wifiCard.wifiPhase2; font.family: Theme.fontFamily; font.pixelSize: 10; padding: 7
                            onTextChanged: wifiCard.wifiPhase2 = text
                            Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                            Text { anchors.fill: parent; anchors.margins: 7; text: "Fase 2: mschapv2"; color: "#555"; font: parent.font; visible: !parent.text }
                        }
                        TextInput {
                            width: parent.width; height: 32; color: "white"; text: wifiCard.wifiAnonymousIdentity; font.family: Theme.fontFamily; font.pixelSize: 10; padding: 7
                            onTextChanged: wifiCard.wifiAnonymousIdentity = text
                            Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                            Text { anchors.fill: parent; anchors.margins: 7; text: "Identidad anónima (opcional)"; color: "#555"; font: parent.font; visible: !parent.text }
                        }
                        TextInput {
                            width: parent.width; height: 32; color: "white"; text: wifiCard.wifiCaCert; font.family: Theme.fontFamily; font.pixelSize: 10; padding: 7
                            onTextChanged: wifiCard.wifiCaCert = text
                            Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                            Text { anchors.fill: parent; anchors.margins: 7; text: "Certificado CA (opcional)"; color: "#555"; font: parent.font; visible: !parent.text }
                        }
                        TextInput {
                            width: parent.width; height: 32; color: "white"; text: wifiCard.wifiDomain; font.family: Theme.fontFamily; font.pixelSize: 10; padding: 7
                            onTextChanged: wifiCard.wifiDomain = text
                            Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                            Text { anchors.fill: parent; anchors.margins: 7; text: "Dominio (opcional)"; color: "#555"; font: parent.font; visible: !parent.text }
                        }
                        TextInput {
                            width: parent.width; height: 32; color: "white"; text: wifiCard.wifiClientCert; font.family: Theme.fontFamily; font.pixelSize: 10; padding: 7
                            onTextChanged: wifiCard.wifiClientCert = text
                            Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                            Text { anchors.fill: parent; anchors.margins: 7; text: "Certificado cliente (EAP-TLS)"; color: "#555"; font: parent.font; visible: !parent.text }
                        }
                        TextInput {
                            width: parent.width; height: 32; color: "white"; text: wifiCard.wifiClientKey; font.family: Theme.fontFamily; font.pixelSize: 10; padding: 7
                            onTextChanged: wifiCard.wifiClientKey = text
                            Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#000000"; border.color: "#333" }
                            Text { anchors.fill: parent; anchors.margins: 7; text: "Clave privada (EAP-TLS)"; color: "#555"; font: parent.font; visible: !parent.text }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 34
                        radius: 8
                        color: wifiCard.wifiState === "connecting" ? "#141414" : networkConnectArea.containsMouse ? "white" : "#141414"
                        Text { anchors.centerIn: parent; text: wifiCard.wifiState === "connecting" ? "CONECTANDO…" : "CONECTAR"; color: wifiCard.wifiState === "connecting" ? "#555" : networkConnectArea.containsMouse ? "#000000" : "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 9; font.bold: true }
                        MouseArea { id: networkConnectArea; anchors.fill: parent; hoverEnabled: true; onClicked: wifiCard.connectNetwork(ssid) }
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: wifiCard.wifiNetworks.count ? wifiCard.wifiMessage : (wifiCard.wifiMessage || "Buscando redes...")
            color: wifiCard.wifiState === "failed" ? "#eba0ac" : wifiCard.wifiState === "connecting" ? "white" : "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
            visible: text !== ""
        }

        Rectangle {
            visible: false
            width: parent.width
            height: 34
            radius: 8
            color: wifiCard.wifiState === "connecting" ? "#141414" : wifiConnectArea.containsMouse ? "white" : "#141414"
            Text {
                anchors.centerIn: parent
                text: wifiCard.wifiState === "connecting" ? "CONECTANDO…" : "CONECTAR" + (wifiCard.selectedSsid ? " · " + wifiCard.selectedSsid : "")
                color: wifiCard.wifiState === "connecting" ? "#555" : wifiConnectArea.containsMouse ? "#000000" : "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.bold: true
                elide: Text.ElideRight
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
            }
            MouseArea {
                id: wifiConnectArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (!wifiCard.selectedSsid || wifiCard.wifiState === "connecting")
                        return;
                    wifiConnect.command = wifiCard.connectCommand();
                    wifiCard.wifiState = "connecting";
                    wifiCard.lastError = "";
                    wifiCard.wifiMessage = "Conectando a " + wifiCard.selectedSsid + "…";
                    wifiConnect.running = false;
                    wifiConnect.running = true;
                }
            }
        }
    }

    Process {
        id: wifiScan
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => wifiCard.parseNetwork(line)
        }
        onExited: {
            if (wifiCard.wifiScanNetworks.count) {
                wifiCard.wifiNetworks.clear();
                for (let i = 0; i < wifiCard.wifiScanNetworks.count; i++) {
                    const network = wifiCard.wifiScanNetworks.get(i);
                    wifiCard.wifiNetworks.append({ ssid: network.ssid, signal: network.signal, security: network.security, expanded: false });
                }
                wifiCard.wifiMessage = "Selecciona una red";
            } else if (!wifiCard.wifiNetworks.count) {
                wifiCard.wifiMessage = "nmcli no disponible o sin redes";
            } else {
                wifiCard.wifiMessage = "No se encontraron redes nuevas";
            }
            wifiCard.wifiScanNetworks.clear();
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
                wifiCard.wifiState = "connected";
                wifiCard.lastError = "";
                wifiCard.wifiMessage = "Conectado a " + wifiCard.selectedSsid;
                wifiCard.wifiPassword = "";
                wifiPasswordInput.text = "";
            } else {
                wifiCard.wifiState = "failed";
                wifiCard.lastError = wifiCard.connErrorMessage(wifiConnectErr.text, exitCode);
                wifiCard.wifiMessage = wifiCard.lastError;
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
                if (wifiCard.wifiState === "connecting")
                    return;
                const parts = this.text.trim().split("|");
                wifiCard.wifiOn = parts[0] === "enabled";
                wifiCard.wifiSignal = parseInt(parts[3]) || 0;
                const net = parts[1] || "";
                const wired = parts[2] || "";
                if (!wifiCard.wifiOn) {
                    wifiCard.network = "Desactivado";
                    wifiCard.wifiState = "off";
                } else if (net) {
                    wifiCard.network = net;
                    wifiCard.wifiState = "connected";
                } else if (wired) {
                    wifiCard.network = "Cable: " + wired;
                    wifiCard.wifiState = "connected";
                } else {
                    wifiCard.network = "Sin conexión";
                    if (wifiCard.wifiState !== "failed")
                        wifiCard.wifiState = "disconnected";
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
        running: true
        repeat: true
        onTriggered: {
            wifiStatus.running = true;
            if (UIState.activeSection === "conexiones" && wifiCard.wifiOn && !wifiScan.running)
                wifiCard.refreshNetworks();
        }
    }
}