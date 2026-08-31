import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import "../components"
import "../config"
import "../services"

Card {
    id: battCard
    property var batt: null
    property bool hasBattery: false
    property double battPct: 0

    cIcon: battCard.icon()
    cAccent: batt && batt.state === UPowerDeviceState.Charging ? "white" : "#eba0ac"
    cTitle: "BATER\u00cdA"
    cBig: hasBattery ? Math.round(battPct) + "%" : "--%"
    cVal: battPct
    cSub: battCard.battSub()
    dDel: 60
    cardOn: UIState.widgetMenuOpen
    visible: hasBattery && UIState.activeSection === "monitoreo"

    function icon() {
        if (batt && batt.state === UPowerDeviceState.Charging)
            return "\uf0e7";
        const p = battPct;
        if (p >= 90)
            return "\uf240";
        if (p >= 60)
            return "\uf242";
        if (p >= 30)
            return "\uf243";
        return "\uf244";
    }

    function watts() {
        const b = batt;
        if (!b)
            return 0;
        const t = b.state === UPowerDeviceState.Charging ? b.timeToFull : b.timeToEmpty;
        if (b.energy > 0 && t > 0)
            return b.energy * 3600 / t;
        return 0;
    }

    function stateText() {
        const s = batt ? batt.state : -1;
        switch (s) {
        case UPowerDeviceState.Charging:
            return "Cargando";
        case UPowerDeviceState.Discharging:
            return "Descargando";
        case UPowerDeviceState.FullyCharged:
            return "Cargada";
        case UPowerDeviceState.Empty:
            return "Vac\u00eda";
        default:
            return "---";
        }
    }

    function fmtEta(sec) {
        if (!sec || sec <= 0)
            return "";
        const h = Math.floor(sec / 3600);
        const m = Math.round((sec % 3600) / 60);
        if (h >= 100)
            return (h / 24).toFixed(0) + "d";
        if (h > 0)
            return h + "h " + String(m).padStart(2, "0") + "m";
        return m + "m";
    }

    function battSub() {
        if (!hasBattery)
            return "---";
        let s = battCard.stateText();
        const w = battCard.watts();
        if (w > 0)
            s += " \u00b7 " + w.toFixed(1) + "W";
        const b = batt;
        const t = b.state === UPowerDeviceState.Charging ? b.timeToFull : b.timeToEmpty;
        const eta = battCard.fmtEta(t);
        if (eta)
            s += " \u00b7 " + eta;
        return s;
    }
}