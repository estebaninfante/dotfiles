import QtQuick
import Quickshell.Services.UPower
import "../config"
import "../services"

Rectangle {
    id: batteryRow
    visible: BatteryService.hasBattery
    width: batteryInner.implicitWidth + 16
    height: 22
    radius: 8
    color: UIState.powerMenuOpen ? "white" : battArea.containsMouse ? "#1d1d26" : "#141414"

    function icon() {
        const p = BatteryService.battPct;
        if (BatteryService.batt.state === UPowerDeviceState.Charging)
            return "\uf0e7";
        if (p >= 90)
            return "\uf240";
        if (p >= 75)
            return "\uf241";
        if (p >= 50)
            return "\uf242";
        if (p >= 25)
            return "\uf243";
        return "\uf244";
    }

    Row {
        id: batteryInner
        anchors.centerIn: parent
        spacing: 4

        Text {
            id: batteryIcon
            text: batteryRow.icon()
            color: batteryText.color
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
        }

        Text {
            id: batteryText
            text: Math.round(BatteryService.battPct) + "%"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            color: UIState.powerMenuOpen ? "#000000" : BatteryService.battPct <= 20 ? "#eba0ac" : "white"
        }
    }

    MouseArea {
        id: battArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            UIState.powerMenuPendingAction = "";
            UIState.powerMenuProfilesOpen = true;
            UIState.powerMenuOpen = !UIState.powerMenuOpen;
        }
    }
}