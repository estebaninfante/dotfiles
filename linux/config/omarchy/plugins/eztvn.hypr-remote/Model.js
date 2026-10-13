var widgetGlyph = "󰄜"

function asString(value) {
  if (value === undefined || value === null) return ""
  return String(value)
}

function asNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function plural(count, singular, many) {
  return count === 1 ? singular : many
}

function normalizeDevice(raw) {
  if (!isObject(raw)) return null
  var id = asString(raw.id)
  if (!id) return null
  return {
    id: id,
    name: asString(raw.name) || "teléfono",
    pairedAt: asNumber(pickStamp(raw, "pairedAt", "paired"), 0),
    seenAt: asNumber(pickStamp(raw, "seenAt", "seen"), 0),
    connected: raw.connected === true
  }
}

function pickStamp(raw, normalizedKey, apiKey) {
  if (raw[normalizedKey] !== undefined) return raw[normalizedKey]
  return raw[apiKey]
}

function looksLikeStatus(parsed) {
  if (parsed.running === false || parsed.running === true) return true
  return parsed.pairingUrl !== undefined
    || parsed.devices !== undefined
    || parsed.version !== undefined
    || parsed.https !== undefined
    || parsed.uptimeSec !== undefined
}

function parseStatus(raw) {
  var parsed = null
  try {
    parsed = JSON.parse(asString(raw).trim())
  } catch (e) {
    return null
  }
  if (!isObject(parsed) || !looksLikeStatus(parsed)) return null

  var devices = []
  if (Array.isArray(parsed.devices)) {
    for (var i = 0; i < parsed.devices.length; i++) {
      var device = normalizeDevice(parsed.devices[i])
      if (device) devices.push(device)
    }
  }

  var connected = 0
  for (var j = 0; j < devices.length; j++) if (devices[j].connected) connected++

  return {
    running: parsed.running !== false,
    unit: asString(parsed.unit),
    version: asString(parsed.version),
    commit: asString(parsed.commit),
    pairingUrl: asString(parsed.pairingUrl),
    qrPath: asString(parsed.qrPath),
    httpPort: asNumber(parsed.httpPort, 0),
    https: isObject(parsed.https)
      ? { address: asString(parsed.https.address), port: asNumber(parsed.https.port, 0) }
      : null,
    clients: asNumber(parsed.clients, 0),
    uptimeSec: asNumber(parsed.uptimeSec, -1),
    devices: devices,
    paired: devices.length,
    connected: connected
  }
}

function kind(status) {
  if (!status || !status.running) return "down"
  return status.connected > 0 ? "active" : "idle"
}

function barText(status) {
  var mark = widgetGlyph
  if (!status || !status.running) return mark
  if (status.paired === 0) return mark
  return mark + " " + status.connected + "/" + status.paired
}

function countsText(status) {
  if (!status) return "—"
  return status.connected + " " + plural(status.connected, "conectado", "conectados")
    + " · " + status.paired + " " + plural(status.paired, "emparejado", "emparejados")
}

function summaryText(status) {
  if (!status) return "hypr-remote sin datos"
  if (!status.running) {
    return status.unit === "active" ? "hypr-remote sin API de control" : "hypr-remote detenido"
  }
  return "hypr-remote · " + countsText(status)
}

function stateLabel(status) {
  if (!status) return "Sin datos"
  if (status.running) return "Corriendo"
  if (status.unit === "active") return "Sin API de control"
  return "Detenido"
}

function unitActive(status) {
  if (!status) return false
  return status.running || status.unit === "active"
}

function unitState(status) {
  if (!status) return "—"
  if (status.running) return "active"
  if (status.unit) return status.unit
  return "unknown"
}

function uptimeText(seconds) {
  var total = Math.floor(asNumber(seconds, -1))
  if (total < 0) return "—"
  if (total < 60) return total + " s"
  var minutes = Math.floor(total / 60)
  if (minutes < 60) return minutes + " min"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + " h " + (minutes % 60) + " min"
  return Math.floor(hours / 24) + " d " + (hours % 24) + " h"
}

function ageText(deltaMs) {
  var seconds = Math.floor(Math.max(0, asNumber(deltaMs, 0)) / 1000)
  if (seconds < 60) return "ahora mismo"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return "hace " + minutes + " min"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return "hace " + hours + " h"
  return "hace " + Math.floor(hours / 24) + " d"
}

function relativeText(epochMs, nowMs) {
  var stamp = asNumber(epochMs, 0)
  var now = asNumber(nowMs, 0)
  if (stamp <= 0 || now <= 0) return "—"
  return ageText(now - stamp)
}

function httpsText(status) {
  if (!status || !status.running) return "—"
  if (!status.https || !status.https.address) return "desactivado"
  return status.https.address + (status.https.port > 0 ? ":" + status.https.port : "")
}

function versionText(status) {
  if (!status || !status.running) return "—"
  var version = status.version || "—"
  return status.commit ? version + " (" + status.commit + ")" : version
}

function addressText(status) {
  if (!status || !status.running) return "—"
  return status.pairingUrl || "—"
}

function deviceRows(devices, nowMs) {
  var list = (Array.isArray(devices) ? devices : [])
    .map(normalizeDevice)
    .filter(function(device) { return device !== null })
  list.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    return b.seenAt - a.seenAt
  })
  var rows = []
  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    rows.push({
      id: device.id,
      name: device.name,
      connected: device.connected,
      pairedText: relativeText(device.pairedAt, nowMs),
      seenText: device.connected ? "conectado ahora" : relativeText(device.seenAt, nowMs)
    })
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    asString: asString,
    asNumber: asNumber,
    isObject: isObject,
    normalizeDevice: normalizeDevice,
    parseStatus: parseStatus,
    kind: kind,
    widgetGlyph: widgetGlyph,
    barText: barText,
    summaryText: summaryText,
    stateLabel: stateLabel,
    unitActive: unitActive,
    unitState: unitState,
    countsText: countsText,
    uptimeText: uptimeText,
    ageText: ageText,
    relativeText: relativeText,
    httpsText: httpsText,
    versionText: versionText,
    addressText: addressText,
    deviceRows: deviceRows
  }
}
