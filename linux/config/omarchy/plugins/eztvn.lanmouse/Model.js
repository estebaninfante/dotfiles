var POSITION_ORDER = ["left", "right", "top", "bottom"]

var POSITION_GLYPH = {
  left: "\u2190",
  right: "\u2192",
  top: "\u2191",
  bottom: "\u2193"
}

var POSITION_LABEL = {
  left: "Izquierda",
  right: "Derecha",
  top: "Arriba",
  bottom: "Abajo"
}

var CLIENT_LINE = /^id\s+(\d+):\s+(.*?)\s+\(([A-Za-z]+)\)\s+active:\s+(true|false)(?:,\s+ips:\s*\{(.*)\})?$/
var CONFIG_ASSIGN = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$/

var PEER_LOGICAL_WIDTH = 1920
var PEER_LOGICAL_HEIGHT = 1080
var PEER_SUBLABEL = "\u22481920\u00d71080 aprox."
var ZONE_EPSILON = 0.01

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function isKnownPosition(position) {
  return POSITION_ORDER.indexOf(String(position || "")) >= 0
}

function normalizedPosition(position) {
  return isKnownPosition(position) ? String(position) : "right"
}

function positionGlyph(position) {
  return POSITION_GLYPH[String(position || "")] || "\u21c4"
}

function positionLabel(position) {
  var key = String(position || "")
  return POSITION_LABEL[key] || key
}

function splitEndpoint(raw) {
  var endpoint = String(raw || "")
  var match = /^(.*):(\d+)$/.exec(endpoint)
  if (!match) return { host: endpoint, port: "" }
  return { host: match[1], port: match[2] }
}

function parseClientLine(line) {
  var match = CLIENT_LINE.exec(String(line || "").trim())
  if (!match) return null
  var endpoint = splitEndpoint(match[2])
  var ips = []
  if (match[5]) {
    ips = String(match[5]).split(",").map(function(part) { return part.trim() })
      .filter(function(part) { return part !== "" })
  }
  return {
    id: String(match[1]),
    host: endpoint.host,
    port: endpoint.port,
    position: String(match[3]),
    active: match[4] === "true",
    ips: ips,
    source: "daemon"
  }
}

function parseList(raw) {
  var text = String(raw || "")
  var clients = []
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() === "") continue
    var client = parseClientLine(lines[i])
    if (client) clients.push(client)
  }
  return {
    ok: clients.length > 0,
    clients: clients,
    error: clients.length > 0 ? "" : "No se pudo leer el estado de lan-mouse"
  }
}

function unquote(value) {
  var text = String(value || "").trim()
  if (text.length >= 2 && text.charAt(0) === text.charAt(text.length - 1)
      && (text.charAt(0) === "\"" || text.charAt(0) === "'")) {
    return text.substring(1, text.length - 1)
  }
  return text
}

function parseConfigClients(raw) {
  var lines = String(raw || "").split("\n")
  var clients = []
  var current = null
  var index = 0
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    if (line.charAt(0) === "[") {
      if (current) clients.push(current)
      current = null
      if (line === "[[clients]]") {
        current = {
          id: String(index++),
          host: "",
          port: "",
          position: "",
          active: false,
          ips: [],
          source: "config"
        }
      }
      continue
    }
    if (!current) continue
    var match = CONFIG_ASSIGN.exec(line)
    if (!match) continue
    if (match[1] === "hostname") current.host = unquote(match[2])
    else if (match[1] === "position") {
      var position = unquote(match[2])
      if (isKnownPosition(position)) current.position = position
    } else if (match[1] === "ips") current.ips = parseTomlArray(match[2])
  }
  if (current) clients.push(current)
  return clients.filter(function(client) { return client.host !== "" })
}

function parseTomlArray(raw) {
  var text = String(raw || "").trim()
  if (text.charAt(0) !== "[" || text.charAt(text.length - 1) !== "]") return []
  return text.substring(1, text.length - 1).split(",")
    .map(function(part) { return unquote(part) })
    .filter(function(part) { return part !== "" })
}

function parseLocalIps(raw) {
  var result = []
  var blocks
  try {
    blocks = JSON.parse(String(raw || "[]"))
  } catch (error) {
    return result
  }
  if (!Array.isArray(blocks)) return result
  for (var i = 0; i < blocks.length; i++) {
    var info = blocks[i] && Array.isArray(blocks[i].addr_info) ? blocks[i].addr_info : []
    for (var j = 0; j < info.length; j++) {
      if (!info[j] || info[j].family !== "inet" || info[j].scope !== "global") continue
      var local = String(info[j].local || "")
      if (local !== "") result.push(local)
    }
  }
  return result
}

function firstLocalIp(raw) {
  var addresses = parseLocalIps(raw)
  return addresses.length > 0 ? addresses[0] : ""
}

function setPositionArgs(clientId, position) {
  return ["lan-mouse", "cli", "set-position", String(clientId), String(position)]
}

function setActiveArgs(clientId, active) {
  return ["lan-mouse", "cli", active ? "activate" : "deactivate", String(clientId)]
}

function saveConfigArgs() {
  return ["lan-mouse", "cli", "save-config"]
}

function parseMonitors(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    return Array.isArray(parsed) ? parsed : []
  } catch (error) {
    return []
  }
}

function enabledMonitors(monitors) {
  var list = Array.isArray(monitors) ? monitors : []
  return list.filter(function(monitor) {
    return monitor && monitor.disabled !== true
      && finiteNumber(monitor.width, 0) > 0 && finiteNumber(monitor.height, 0) > 0
  })
}

function logicalSize(monitor) {
  var width = finiteNumber(monitor && monitor.width, 0)
  var height = finiteNumber(monitor && monitor.height, 0)
  var scale = finiteNumber(monitor && monitor.scale, 1)
  if (!(scale > 0)) scale = 1
  var rotated = Math.round(finiteNumber(monitor && monitor.transform, 0)) % 2 === 1
  return {
    width: (rotated ? height : width) / scale,
    height: (rotated ? width : height) / scale
  }
}

function monitorLabel(monitor) {
  var model = String(monitor && monitor.model || "").trim()
  var make = String(monitor && monitor.make || "").trim()
  var description = String(monitor && monitor.description || "").trim()
  var name = String(monitor && monitor.name || "").trim()
  if (model) return model
  if (make) return make
  if (description) return description
  return name
}

function monitorModeLabel(monitor) {
  var width = Math.round(finiteNumber(monitor && monitor.width, 0))
  var height = Math.round(finiteNumber(monitor && monitor.height, 0))
  if (width <= 0 || height <= 0) return ""
  return width + "\u00d7" + height
}

function localDisplay(monitors) {
  var list = enabledMonitors(monitors)
  if (list.length === 0) return null
  var chosen = list[0]
  for (var i = 0; i < list.length; i++) {
    if (list[i].focused === true) {
      chosen = list[i]
      break
    }
  }
  var size = logicalSize(chosen)
  if (!(size.width > 0) || !(size.height > 0)) return null
  var connector = String(chosen.name || "")
  var mode = monitorModeLabel(chosen)
  return {
    key: connector !== "" ? connector : "local",
    label: monitorLabel(chosen),
    sublabel: mode !== "" ? connector + " \u00b7 " + mode : connector,
    logicalWidth: size.width,
    logicalHeight: size.height
  }
}

function peerDisplay(host) {
  var name = String(host || "").trim()
  return {
    key: name !== "" ? name : "peer",
    label: name !== "" ? name : "lan-mouse",
    sublabel: PEER_SUBLABEL,
    logicalWidth: PEER_LOGICAL_WIDTH,
    logicalHeight: PEER_LOGICAL_HEIGHT,
    estimated: true
  }
}

function placeVertical(members, gap, center, placeX, out) {
  var total = 0
  for (var i = 0; i < members.length; i++) {
    total += members[i].logicalHeight
    if (i > 0) total += gap
  }
  var cursor = center - total / 2
  for (var j = 0; j < members.length; j++) {
    var peer = members[j]
    out[peer.key] = {
      x: placeX(peer),
      y: cursor,
      width: peer.logicalWidth,
      height: peer.logicalHeight
    }
    cursor += peer.logicalHeight + gap
  }
}

function placeHorizontal(members, gap, center, placeY, out) {
  var total = 0
  for (var i = 0; i < members.length; i++) {
    total += members[i].logicalWidth
    if (i > 0) total += gap
  }
  var cursor = center - total / 2
  for (var j = 0; j < members.length; j++) {
    var peer = members[j]
    out[peer.key] = {
      x: cursor,
      y: placeY(peer),
      width: peer.logicalWidth,
      height: peer.logicalHeight
    }
    cursor += peer.logicalWidth + gap
  }
}

function logicalRects(local, peers, gap) {
  var localRect = { x: 0, y: 0, width: local.logicalWidth, height: local.logicalHeight }
  var groups = { left: [], right: [], top: [], bottom: [] }
  var list = Array.isArray(peers) ? peers : []
  for (var i = 0; i < list.length; i++) {
    var peer = list[i]
    if (!peer || !(peer.logicalWidth > 0) || !(peer.logicalHeight > 0)) continue
    groups[normalizedPosition(peer.position)].push(peer)
  }
  var rects = {}
  placeVertical(groups.left, gap, localRect.height / 2,
    function(peer) { return -gap - peer.logicalWidth }, rects)
  placeVertical(groups.right, gap, localRect.height / 2,
    function(peer) { return localRect.width + gap }, rects)
  placeHorizontal(groups.top, gap, localRect.width / 2,
    function(peer) { return -gap - peer.logicalHeight }, rects)
  placeHorizontal(groups.bottom, gap, localRect.width / 2,
    function(peer) { return localRect.height + gap }, rects)
  return { local: localRect, peers: rects }
}

function fitLayout(local, peers, canvasWidth, canvasHeight, padding, utilization, gap) {
  if (!local || !(local.logicalWidth > 0) || !(local.logicalHeight > 0)) return null
  var width = finiteNumber(canvasWidth, 0)
  var height = finiteNumber(canvasHeight, 0)
  if (width <= 0 || height <= 0) return null

  var inset = Math.max(0, finiteNumber(padding, 0))
  var fill = Math.max(0.1, Math.min(1, finiteNumber(utilization, 0.92)))
  var step = Math.max(0, finiteNumber(gap, 0))
  var rects = logicalRects(local, peers, step)

  var minX = rects.local.x
  var minY = rects.local.y
  var maxX = rects.local.x + rects.local.width
  var maxY = rects.local.y + rects.local.height
  var keys = Object.keys(rects.peers)
  for (var i = 0; i < keys.length; i++) {
    var rect = rects.peers[keys[i]]
    minX = Math.min(minX, rect.x)
    minY = Math.min(minY, rect.y)
    maxX = Math.max(maxX, rect.x + rect.width)
    maxY = Math.max(maxY, rect.y + rect.height)
  }

  var boundsWidth = Math.max(1, maxX - minX)
  var boundsHeight = Math.max(1, maxY - minY)
  var usableWidth = Math.max(1, width - inset * 2)
  var usableHeight = Math.max(1, height - inset * 2)
  var scale = Math.min(usableWidth / boundsWidth, usableHeight / boundsHeight) * fill
  var originX = inset + (usableWidth - boundsWidth * scale) / 2 - minX * scale
  var originY = inset + (usableHeight - boundsHeight * scale) / 2 - minY * scale

  var peerItems = []
  var peerLogical = []
  var list = Array.isArray(peers) ? peers : []
  for (var j = 0; j < list.length; j++) {
    var peer = list[j]
    if (!peer || !(peer.logicalWidth > 0) || !(peer.logicalHeight > 0)) continue
    var peerRect = rects.peers[peer.key]
    if (!peerRect) continue
    peerLogical.push({
      key: peer.key,
      position: normalizedPosition(peer.position),
      logicalWidth: peer.logicalWidth,
      logicalHeight: peer.logicalHeight
    })
    peerItems.push({
      key: peer.key,
      label: String(peer.label || peer.key),
      sublabel: String(peer.sublabel || ""),
      estimated: peer.estimated === true,
      position: normalizedPosition(peer.position),
      x: originX + peerRect.x * scale,
      y: originY + peerRect.y * scale,
      width: peerRect.width * scale,
      height: peerRect.height * scale
    })
  }

  return {
    scale: scale,
    originX: originX,
    originY: originY,
    gap: step,
    padding: inset,
    utilization: fill,
    localLogical: { width: local.logicalWidth, height: local.logicalHeight },
    peerLogical: peerLogical,
    local: {
      key: local.key,
      label: String(local.label || local.key),
      sublabel: String(local.sublabel || ""),
      x: originX + rects.local.x * scale,
      y: originY + rects.local.y * scale,
      width: rects.local.width * scale,
      height: rects.local.height * scale
    },
    peers: peerItems
  }
}

function peerCandidateRect(fit, key, position) {
  if (!fit || !fit.localLogical || !fit.peerLogical) return null
  var wanted = String(key || "")
  var updated = []
  for (var i = 0; i < fit.peerLogical.length; i++) {
    var spec = fit.peerLogical[i]
    updated.push({
      key: spec.key,
      position: spec.key === wanted ? normalizedPosition(position) : spec.position,
      logicalWidth: spec.logicalWidth,
      logicalHeight: spec.logicalHeight
    })
  }
  var rects = logicalRects({
    key: "local",
    logicalWidth: fit.localLogical.width,
    logicalHeight: fit.localLogical.height
  }, updated, fit.gap)
  var rect = rects.peers[wanted]
  if (!rect) return null
  return {
    x: fit.originX + rect.x * fit.scale,
    y: fit.originY + rect.y * fit.scale,
    width: rect.width * fit.scale,
    height: rect.height * fit.scale
  }
}

function zoneForPoint(fit, x, y, fallback) {
  if (!fit || !fit.local || !(fit.local.width > 0) || !(fit.local.height > 0)) {
    return normalizedPosition(fallback)
  }
  var centerX = fit.local.x + fit.local.width / 2
  var centerY = fit.local.y + fit.local.height / 2
  var halfWidth = Math.max(1, fit.local.width / 2)
  var halfHeight = Math.max(1, fit.local.height / 2)
  var offsetX = (finiteNumber(x, centerX) - centerX) / halfWidth
  var offsetY = (finiteNumber(y, centerY) - centerY) / halfHeight
  var candidates = [
    { zone: "left", reach: -offsetX },
    { zone: "right", reach: offsetX },
    { zone: "top", reach: -offsetY },
    { zone: "bottom", reach: offsetY }
  ]
  var best = null
  for (var i = 0; i < candidates.length; i++) {
    if (candidates[i].reach <= ZONE_EPSILON) continue
    if (!best || candidates[i].reach > best.reach) best = candidates[i]
  }
  return best ? best.zone : normalizedPosition(fallback)
}

function topologyDisplays(monitors) {
  var out = []
  var list = Array.isArray(monitors) ? monitors : []
  for (var i = 0; i < list.length; i++) {
    var monitor = list[i]
    if (!monitor || !monitor.name) continue
    var record = {
      name: String(monitor.name),
      enabled: monitor.disabled !== true,
      focused: monitor.focused === true,
      x: Math.round(finiteNumber(monitor.x, 0)),
      y: Math.round(finiteNumber(monitor.y, 0)),
      width: Math.round(finiteNumber(monitor.width, 0)),
      height: Math.round(finiteNumber(monitor.height, 0)),
      refreshRate: finiteNumber(monitor.refreshRate, 60),
      scale: finiteNumber(monitor.scale, 1),
      transform: Math.round(finiteNumber(monitor.transform, 0))
    }
    var mirror = String(monitor.mirrorOf || "")
    if (mirror && mirror !== "none") record.mirrorOf = mirror
    out.push(record)
  }
  return out
}

function originFor(monitors, proposed) {
  var byName = {}
  var list = Array.isArray(monitors) ? monitors : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].name) byName[String(list[i].name)] = list[i]
  }
  var chosen = null
  for (var j = 0; j < proposed.length; j++) {
    var candidate = byName[String(proposed[j].name)]
    if (candidate && candidate.focused === true) {
      chosen = candidate
      break
    }
  }
  if (!chosen && proposed.length > 0) chosen = byName[String(proposed[0].name)] || null
  if (!chosen) return { screen: "", workspace: 0 }
  var active = chosen.activeWorkspace
  return {
    screen: String(chosen.name),
    workspace: Math.max(0, Math.round(finiteNumber(active ? active.id : 0, 0)))
  }
}

function arrangeRow(payload, topology) {
  var cursor = 0
  return payload.map(function(record) {
    if (!record || record.enabled === false) return record
    var placed = Object.assign({}, record, { x: Math.round(cursor), y: 0 })
    cursor += topology.logicalSize(record.width, record.height, record.scale, record.transform).width
    return placed
  })
}

function placementKey(payload) {
  var records = Array.isArray(payload) ? payload : []
  var placements = records.map(function(record) {
    return {
      name: String(record && record.name || ""),
      enabled: record && record.enabled !== false,
      x: Number(record && record.x) || 0,
      y: Number(record && record.y) || 0
    }
  })
  placements.sort(function(a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0) })
  return JSON.stringify(placements)
}

function planLocalExtend(monitors, topology) {
  var displays = topologyDisplays(monitors)
  if (displays.length === 0) {
    return {
      valid: false,
      reason: "No hay monitores que disponer",
      changed: false,
      proposed: [],
      previous: [],
      anchor: "",
      originScreen: "",
      originWorkspace: 0
    }
  }
  var previous = topology.buildTopologyPayload(displays, {})
  if (displays.length === 1) {
    var onlyOrigin = originFor(monitors, previous)
    return {
      valid: true,
      reason: "",
      changed: false,
      proposed: previous,
      previous: previous,
      anchor: topology.validAnchor(previous, ""),
      originScreen: onlyOrigin.screen,
      originWorkspace: onlyOrigin.workspace
    }
  }
  var ordered = displays.slice().sort(function(a, b) {
    if (a.x !== b.x) return a.x - b.x
    return a.y - b.y
  })
  var proposed = arrangeRow(topology.buildTopologyPayload(ordered, {}), topology)
  var validation = topology.validateTopologyPayload(proposed)
  var origin = originFor(monitors, proposed)
  return {
    valid: validation.valid && proposed.length > 0,
    reason: validation.reason,
    changed: placementKey(proposed) !== placementKey(previous),
    proposed: proposed,
    previous: previous,
    anchor: topology.validAnchor(proposed, ""),
    originScreen: origin.screen,
    originWorkspace: origin.workspace
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    POSITION_ORDER: POSITION_ORDER,
    finiteNumber: finiteNumber,
    isKnownPosition: isKnownPosition,
    normalizedPosition: normalizedPosition,
    positionGlyph: positionGlyph,
    positionLabel: positionLabel,
    parseClientLine: parseClientLine,
    parseList: parseList,
    parseConfigClients: parseConfigClients,
    parseTomlArray: parseTomlArray,
    parseLocalIps: parseLocalIps,
    firstLocalIp: firstLocalIp,
    setPositionArgs: setPositionArgs,
    setActiveArgs: setActiveArgs,
    saveConfigArgs: saveConfigArgs,
    parseMonitors: parseMonitors,
    enabledMonitors: enabledMonitors,
    logicalSize: logicalSize,
    monitorLabel: monitorLabel,
    monitorModeLabel: monitorModeLabel,
    localDisplay: localDisplay,
    peerDisplay: peerDisplay,
    logicalRects: logicalRects,
    fitLayout: fitLayout,
    peerCandidateRect: peerCandidateRect,
    zoneForPoint: zoneForPoint,
    topologyDisplays: topologyDisplays,
    originFor: originFor,
    arrangeRow: arrangeRow,
    placementKey: placementKey,
    planLocalExtend: planLocalExtend
  }
}
