function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.percentage
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

function stateLabel(state) {
  var s = String(state || "")
  if (s === "holding") return "Holding"
  if (s === "charging") return "Charging"
  if (s === "discharging") return "Discharging"
  if (s === "fully-charged") return "Fully charged"
  if (s === "pending-charge") return "Pending charge"
  return s || "—"
}

function timeLabel(state, time) {
  if (String(state || "") === "holding") return "—"
  return String(time || "—")
}

function runtimeEstimate(batteryInfo, averageWatts, discharging) {
  if (!discharging || Number(averageWatts) <= 0.05) return "—"
  var info = batteryInfo || {}
  var size = parseFloat(String(info.size || ""))
  var percent = parseFloat(String(info.percentage || "").replace("%", ""))
  if (!isFinite(size) || !isFinite(percent)) return "—"
  return humanDuration(size * (percent / 100) / Number(averageWatts))
}

function humanDuration(hours) {
  if (!isFinite(hours) || hours < 0) return "—"
  var totalMin = Math.round(hours * 60)
  var h = Math.floor(totalMin / 60)
  var m = totalMin % 60
  return h > 0 ? h + "h " + m + "m" : m + "m"
}

function minutesLabel(minutes) {
  var n = Number(minutes)
  if (!isFinite(n) || n <= 0) return "0m"
  return n >= 60 ? Math.round(n / 60) + "h" : n + "m"
}

function formatWatts(watts) {
  var n = Number(watts)
  if (!isFinite(n)) return "0.0W"
  return n.toFixed(1) + "W"
}

function wattReadout(dischargeWatts, chargeWatts) {
  var d = Number(dischargeWatts) || 0
  var c = Number(chargeWatts) || 0
  if (d > 0.05) return formatWatts(d)
  if (c > 0.05) return "+" + formatWatts(c)
  return "--.-W"
}

function parseSample(text) {
  var parts = String(text || "").trim().split(/\s+/)
  if (parts.length < 2) return null
  var t = Number(parts[0])
  var w = Number(parts[1])
  var c = parts.length >= 3 ? Number(parts[2]) : 0
  if (!isFinite(t) || !isFinite(w) || !isFinite(c)) return null
  return { t: t, w: w, c: c }
}

function parseHistory(raw, cap) {
  var limit = isFinite(cap) && cap > 0 ? cap : 24000
  var lines = String(raw || "").split("\n")
  var list = []
  for (var i = 0; i < lines.length; i++) {
    var sample = parseSample(lines[i])
    if (!sample) continue
    if (sample.w <= 0.05 && sample.c <= 0.05) continue
    list.push(sample)
    if (list.length > limit) list.shift()
  }
  return list
}

function windowSamples(samples, minutes, nowSeconds) {
  var list = Array.isArray(samples) ? samples : []
  var cutoff = Math.floor(Number(nowSeconds)) - Number(minutes) * 60
  var out = []
  for (var i = list.length - 1; i >= 0; i--) {
    if (list[i].t < cutoff) break
    out.push(list[i])
  }
  out.reverse()
  return out
}

function dischargeSamples(samples, minutes, nowSeconds) {
  var source = windowSamples(samples, minutes, nowSeconds)
  var out = []
  for (var i = 0; i < source.length; i++) {
    if (source[i].w > 0.05) out.push(source[i])
  }
  return out
}

function computeStats(samples, minutes, nowSeconds) {
  var list = dischargeSamples(samples, minutes, nowSeconds)
  if (list.length === 0) return { average: 0, peak: 0, energyWh: 0 }

  var sum = 0
  var peak = 0
  var energy = 0
  for (var i = 0; i < list.length; i++) {
    sum += list[i].w
    if (list[i].w > peak) peak = list[i].w
    if (i > 0) {
      var dt = list[i].t - list[i - 1].t
      if (dt > 0 && dt <= 60) energy += list[i].w * dt / 3600
    }
  }
  return { average: sum / list.length, peak: peak, energyWh: energy }
}

function computeTrend(samples, minutes, nowSeconds) {
  var list = dischargeSamples(samples, minutes, nowSeconds)
  if (list.length < 2) return "→"
  var now = list[list.length - 1].w
  var ref = list[0].w
  if (now > ref + 0.05) return "↑"
  if (now < ref - 0.05) return "↓"
  return "→"
}

function uptimeText(seconds) {
  var s = Number(seconds)
  if (!isFinite(s) || s < 0) return "—"
  return humanDuration(s / 3600)
}

function temperatureText(celsius) {
  var c = Number(celsius)
  if (!isFinite(c) || c <= 0) return "—"
  return Math.round(c) + "°C"
}

function percentageText(value) {
  var n = parseFloat(String(value === undefined || value === null ? "" : value).replace("%", ""))
  if (!isFinite(n)) return "—"
  return Math.round(n) + "%"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    stateLabel: stateLabel,
    timeLabel: timeLabel,
    runtimeEstimate: runtimeEstimate,
    humanDuration: humanDuration,
    minutesLabel: minutesLabel,
    formatWatts: formatWatts,
    wattReadout: wattReadout,
    parseSample: parseSample,
    parseHistory: parseHistory,
    windowSamples: windowSamples,
    dischargeSamples: dischargeSamples,
    computeStats: computeStats,
    computeTrend: computeTrend,
    uptimeText: uptimeText,
    temperatureText: temperatureText,
    percentageText: percentageText
  }
}
