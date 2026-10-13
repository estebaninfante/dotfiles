import QtQuick
import Quickshell.Services.UPower
import "Model.js" as Model

QtObject {
  id: root

  property var settings: ({})
  property bool panelOpen: false
  property int phraseIndex: 0

  property PowerSampler sampler: PowerSampler {
    id: sampler
    settings: root.settings
    panelOpen: root.panelOpen
  }

  readonly property var upowerStates: ({
    Charging: UPowerDeviceState.Charging,
    Discharging: UPowerDeviceState.Discharging,
    FullyCharged: UPowerDeviceState.FullyCharged,
    PendingCharge: UPowerDeviceState.PendingCharge
  })

  readonly property bool batteryPresent: sampler.batteryPresent
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: Model.chargeThresholdActive(UPower.displayDevice, root.discharging, root.upowerStates)
  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive)
  }
  readonly property real batteryFraction: Model.batteryFraction(UPower.displayDevice)
  readonly property bool batteryFull: root.fullyCharged || (!root.discharging && root.batteryFraction >= 1)
  readonly property bool batteryFlowIdle: root.batteryFull || root.chargeThresholdActive
  readonly property bool charging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && !UPower.onBattery && !root.batteryFlowIdle)
  }

  readonly property string batteryGlyph: Model.batteryIcon(UPower.displayDevice, root.discharging, root.upowerStates)
  readonly property string modeText: Model.modeLabel(UPower.displayDevice, root.discharging, root.upowerStates)
  readonly property string profileGlyph: Model.profileIcon(root.activeProfile)
  readonly property string percentText: root.batteryPresent ? Model.percentageText(sampler.batteryInfo.percentage) : "—"
  readonly property string wattsText: Model.wattReadout(sampler.currentWatts, sampler.currentChargeWatts)
  readonly property string averageText: Model.formatWatts(sampler.averageWatts)
  readonly property string peakText: Model.formatWatts(sampler.peakWatts)
  readonly property string energyText: sampler.energyWh.toFixed(2) + "Wh"
  readonly property string cpuText: String(sampler.systemInfo.cpu || "—")
  readonly property string memoryText: String(sampler.systemInfo.memory || "—")
  readonly property string uptimeText: Model.uptimeText(sampler.systemInfo.uptime)
  readonly property string cpuTempText: Model.temperatureText(sampler.systemInfo.cpu_temp)
  readonly property string gpuTempText: Model.temperatureText(sampler.systemInfo.gpu_temp)
  readonly property string healthText: sampler.systemInfo.health ? sampler.systemInfo.health + "%" : "—"
  readonly property string sizeText: String(sampler.batteryInfo.size || "—")
  readonly property string cyclesText: String(sampler.batteryInfo.cycles || "—")
  readonly property string thresholdText: String(sampler.batteryInfo.threshold || "—")
  readonly property string stateText: Model.stateLabel(sampler.batteryInfo.state)
  readonly property string timeText: Model.timeLabel(sampler.batteryInfo.state, sampler.batteryInfo.time)
  readonly property string runtimeText: Model.runtimeEstimate(sampler.batteryInfo, sampler.averageWatts, root.discharging)

  readonly property var samples: sampler.samples
  readonly property int samplesRevision: sampler.samplesRevision
  readonly property int graphMinutes: sampler.graphMinutes
  readonly property int statsMinutes: sampler.statsMinutes
  readonly property var scaleOptions: sampler.scaleOptions
  readonly property var profiles: sampler.profiles
  readonly property string activeProfile: sampler.activeProfile
  readonly property int profileIndex: sampler.profileIndex
  readonly property string fastChargeState: sampler.fastChargeState

  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]

  readonly property var activePhrases: {
    if (root.fullyCharged) return []
    if (root.charging) return root.chargingPhrases
    if (root.discharging) return root.onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: root.activePhrases.length > 0

  readonly property string heroStatusText: {
    if (root.fullyCharged) return "Fully charged"
    if (root.rotatingPhrases) return root.activePhrases[root.phraseIndex % root.activePhrases.length]
    return root.modeText
  }

  function refresh() { sampler.refresh() }

  function setStatsMinutes(minutes) { sampler.setStatsMinutes(minutes) }

  function setProfileIndex(index) { sampler.profileIndex = index }

  function selectProfileByDelta(delta) { sampler.selectProfileByDelta(delta) }

  function activateSelectedProfile() { sampler.activateSelectedProfile() }

  function setProfile(profile) { sampler.setProfile(profile) }

  function toggleFastCharge() { sampler.toggleFastCharge() }

  property Timer phraseTimer: Timer {
    interval: 2800
    running: root.panelOpen && root.rotatingPhrases
    repeat: true
    onTriggered: {
      var count = root.activePhrases.length
      if (count > 0) root.phraseIndex = (root.phraseIndex + 1) % count
    }
  }
}
