import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "Model.js" as Model

QtObject {
  id: root

  property var settings: ({})
  property bool panelOpen: false
  property int statsMinutes: 10
  property int profileIndex: 0

  property real currentWatts: 0
  property real currentChargeWatts: 0
  property var samples: []
  property int samplesRevision: 0
  property bool historyLoaded: false
  property string activeProfile: ""
  property var profiles: []
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property string fastChargeState: ""
  property real averageWatts: 0
  property real peakWatts: 0
  property real energyWh: 0
  property string trendGlyph: "→"

  readonly property var scaleOptions: [10, 30, 60, 180, 360]
  readonly property int graphMinutes: Math.max(5, Math.round(Number(root.setting("graphMinutes", 10))))
  readonly property int profileRefreshSec: Math.max(5, Math.round(Number(root.setting("profileRefreshSec", 30))))
  readonly property int panelRefreshSec: Math.max(1, Math.round(Number(root.setting("panelRefreshSec", 5))))

  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function pluginScript(name) {
    var url = String(Qt.resolvedUrl("scripts/" + name)).replace("file://", "")
    return decodeURIComponent(url)
  }

  readonly property int samplingSeconds: {
    if (!UPower.onBattery) return Math.max(1, Number(root.setting("acSampleIntervalSec", 1)))
    if (root.activeProfile === "power-saver") return Math.max(1, Number(root.setting("powerSaverSampleIntervalSec", 5)))
    if (root.activeProfile === "performance") return Math.max(1, Number(root.setting("performanceSampleIntervalSec", 1)))
    return Math.max(1, Number(root.setting("batterySampleIntervalSec", 2)))
  }

  function refresh() {
    if (root.batteryPresent) {
      if (!sampleProc.running) sampleProc.running = true
      if (!profilesProc.running) profilesProc.running = true
      if (!fastChargeProc.running) fastChargeProc.running = true
    }
    if (!systemProc.running) systemProc.running = true
    if (!extrasProc.running) extrasProc.running = true
  }

  function applyKeyValue(raw, kind) {
    var next = Model.parseKeyValue(raw)
    if (Object.keys(next).length === 0) return
    if (kind === "battery") root.batteryInfo = next
    else root.systemInfo = Object.assign({}, root.systemInfo, next)
  }

  function applyProfiles(raw) {
    var parsed = Model.parseProfiles(raw, root.profileIndex)
    if (parsed.profiles.length === 0) return
    root.profiles = parsed.profiles
    root.activeProfile = parsed.activeProfile
    root.profileIndex = parsed.profileIndex
    if (root.panelOpen) {
      var index = root.profiles.indexOf(root.activeProfile)
      if (index >= 0) root.profileIndex = index
    }
  }

  function appendSample(sample) {
    if (!sample) return
    root.currentWatts = sample.w
    root.currentChargeWatts = sample.c
    if (sample.w > 0.05 || sample.c > 0.05) {
      root.samples.push(sample)
      var cap = 24000
      if (root.samples.length > cap) root.samples.splice(0, root.samples.length - cap)
      root.samplesRevision++
    }
    root.recomputeStats()
    root.updateTrend()
  }

  function backfill() {
    if (root.historyLoaded) return
    tailProc.running = true
  }

  function parseTail(raw) {
    root.samples = Model.parseHistory(raw, 24000)
    root.samplesRevision++
    root.historyLoaded = true
    if (root.panelOpen) {
      root.recomputeStats()
      root.updateTrend()
    }
  }

  function recomputeStats() {
    var stats = Model.computeStats(root.samples, root.statsMinutes, Date.now() / 1000)
    root.averageWatts = stats.average
    root.peakWatts = stats.peak
    root.energyWh = stats.energyWh
  }

  function updateTrend() {
    root.trendGlyph = Model.computeTrend(root.samples, root.statsMinutes, Date.now() / 1000)
  }

  function setStatsMinutes(minutes) {
    root.statsMinutes = Number(minutes)
    root.recomputeStats()
    root.updateTrend()
  }

  function selectProfileByDelta(delta) {
    root.profileIndex = Model.selectProfileIndex(root.profileIndex, delta, root.profiles)
  }

  function activateSelectedProfile() {
    if (root.profileIndex < 0 || root.profileIndex >= root.profiles.length) return
    root.setProfile(root.profiles[root.profileIndex])
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", UPower.onBattery ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function toggleFastCharge() {
    if (fastChargeAction.running) return
    fastChargeAction.command = ["sudo", "-n", "/usr/local/bin/battery-fastcharge", "toggle"]
    fastChargeAction.running = true
  }

  function reapplyPowerGuard() {
    if (!powerGuardProc.running) {
      powerGuardProc.command = ["sudo", "-n", "systemctl", "restart", "battery-power-guard.service"]
      powerGuardProc.running = true
    }
    if (!sessionGuardProc.running) {
      sessionGuardProc.command = ["systemctl", "--user", "restart", "power-session-guard.service"]
      sessionGuardProc.running = true
    }
  }

  onPanelOpenChanged: {
    if (root.panelOpen) {
      root.backfill()
      root.refresh()
      root.recomputeStats()
      root.updateTrend()
    }
  }

  onStatsMinutesChanged: {
    root.recomputeStats()
    root.updateTrend()
  }

  // Sin `-l`: un shell de login carga el .bashrc entero (starship, zoxide,
  // decenas de procesos) en cada muestra.
  property Process sampleProc: Process {
    command: ["bash", root.pluginScript("eztvn-power-sample")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.appendSample(Model.parseSample(text))
    }
  }

  property Process profilesProc: Process {
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProfiles(text)
    }
  }

  property Process batteryProc: Process {
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyKeyValue(text, "battery")
    }
  }

  property Process systemProc: Process {
    command: ["omarchy-system-stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyKeyValue(text, "system")
    }
  }

  property Process extrasProc: Process {
    command: ["bash", root.pluginScript("eztvn-power-extras")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyKeyValue(text, "system")
    }
  }

  property Process tailProc: Process {
    command: ["bash", root.pluginScript("eztvn-power-history"), "24000"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseTail(text)
    }
  }

  property Process fastChargeProc: Process {
    command: ["sudo", "-n", "/usr/local/bin/battery-fastcharge", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text).trim()
        root.fastChargeState = (value === "fast" || value === "standard") ? value : ""
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) root.fastChargeState = ""
    }
  }

  property Process fastChargeAction: Process {
    onExited: function(exitCode, exitStatus) {
      if (!fastChargeProc.running) fastChargeProc.running = true
      root.refresh()
    }
  }

  property Process actionProc: Process {
    onExited: {
      root.reapplyPowerGuard()
      root.refresh()
    }
  }

  property Process powerGuardProc: Process {}
  property Process sessionGuardProc: Process {}

  property Timer sampleTimer: Timer {
    interval: root.samplingSeconds * 1000
    running: root.batteryPresent
    repeat: true
    triggeredOnStart: true
    onTriggered: sampleProc.running = true
  }

  property Timer detailTimer: Timer {
    interval: root.profileRefreshSec * 1000
    running: root.batteryPresent
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!profilesProc.running) profilesProc.running = true
      if (!batteryProc.running) batteryProc.running = true
    }
  }

  property Timer panelTimer: Timer {
    interval: root.panelRefreshSec * 1000
    running: root.panelOpen
    repeat: true
    onTriggered: {
      root.refresh()
      root.recomputeStats()
      root.updateTrend()
    }
  }

  Component.onCompleted: root.refresh()
}
