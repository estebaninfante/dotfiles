pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "../config"

Item {
    id: batteryService

    readonly property var batt: UPower.displayDevice
    readonly property bool hasBattery: batt != null && batt.isPresent && batt.type === UPowerDeviceType.Battery
    readonly property double battPct: batteryService.hasBattery ? batteryService.batt.percentage * 100 : 0
    readonly property bool isCharging: batteryService.batt.state === UPowerDeviceState.Charging
}