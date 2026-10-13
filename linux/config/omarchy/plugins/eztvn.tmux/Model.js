var widgetGlyph = ""

var sessionFormat = "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}\t#{session_activity}"

function asString(value) {
  if (value === undefined || value === null) return ""
  return String(value)
}

function asNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function plural(count, one, many) {
  return Math.round(asNumber(count, 0)) === 1 ? one : many
}

function shellQuote(value) {
  return "'" + asString(value).replace(/'/g, "'\\''") + "'"
}

function parseSessions(raw) {
  var lines = asString(raw).split("\n")
  var sessions = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\r$/, "")
    if (line.length === 0) continue
    var parts = line.split("\t")
    if (parts.length < 5) continue
    var name = parts.slice(0, parts.length - 4).join("\t")
    if (name.length === 0) continue
    var tail = parts.slice(parts.length - 4)
    sessions.push({
      name: name,
      windows: Math.max(0, Math.round(asNumber(tail[0], 0))),
      attached: asNumber(tail[1], 0) > 0,
      created: asNumber(tail[2], 0),
      activity: asNumber(tail[3], 0)
    })
  }
  return sessions
}

function sameSessions(left, right) {
  var a = Array.isArray(left) ? left : []
  var b = Array.isArray(right) ? right : []
  return JSON.stringify(a) === JSON.stringify(b)
}

function ageText(deltaSec) {
  var seconds = Math.floor(Math.max(0, asNumber(deltaSec, 0)))
  if (seconds < 60) return "1 min"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + " min"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + " h"
  return Math.floor(hours / 24) + " d"
}

function windowText(count) {
  var n = Math.max(0, Math.round(asNumber(count, 0)))
  return plural(n, "1 ventana", n + " ventanas")
}

function sessionText(count) {
  var n = Math.max(0, Math.round(asNumber(count, 0)))
  return plural(n, "1 sesión", n + " sesiones")
}

function rowMeta(session, nowSec) {
  if (!session) return ""
  var base = windowText(session.windows)
  if (session.attached) return base + " · en uso"
  var now = asNumber(nowSec, 0)
  var activity = asNumber(session.activity, 0)
  if (now <= 0 || activity <= 0) return base + " · sin actividad"
  return base + " · inactiva " + ageText(now - activity)
}

function barText(count) {
  var n = Math.max(0, Math.round(asNumber(count, 0)))
  return n > 0 ? widgetGlyph + " " + n : widgetGlyph
}

function tooltipText(count) {
  var n = Math.max(0, Math.round(asNumber(count, 0)))
  return n > 0 ? "tmux · " + sessionText(n) : "tmux · sin sesiones"
}

function attachCommand(name) {
  var target = asString(name)
  if (target.length === 0) return ""
  return "omarchy launch terminal tmux attach -t " + shellQuote(target)
}

function killSessionArgv(name) {
  var target = asString(name)
  if (target.length === 0) return []
  return ["tmux", "kill-session", "-t", target]
}

function killServerArgv() {
  return ["tmux", "kill-server"]
}

function sessionByName(sessions, name) {
  var list = Array.isArray(sessions) ? sessions : []
  var wanted = asString(name)
  for (var i = 0; i < list.length; i++) {
    if (list[i] && asString(list[i].name) === wanted) return list[i]
  }
  return null
}

function attachedNames(sessions) {
  var list = Array.isArray(sessions) ? sessions : []
  var names = []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].attached) names.push(asString(list[i].name))
  }
  return names
}

function killConfirmMessage(session) {
  if (!session) return ""
  var name = asString(session.name)
  var windows = Math.max(0, Math.round(asNumber(session.windows, 0)))
  var body = windows === 0
    ? "No tiene ventanas abiertas."
    : plural(windows, "Se cierra su ventana.", "Se cierran sus " + windows + " ventanas.")
  var state = session.attached ? " Está ADJUNTADA: alguien trabaja ahí dentro." : ""
  return "¿Eliminar la sesión «" + name + "»?" + state + " " + body
}

function killConfirmSecond(session) {
  if (!session || !session.attached) return ""
  var name = asString(session.name)
  return "«" + name + "» está en uso. Última confirmación: se pierde el trabajo de quien está dentro."
}

function killAllConfirmMessage(sessions) {
  var list = Array.isArray(sessions) ? sessions : []
  if (list.length === 0) return ""
  var names = attachedNames(list)
  var head = "¿Eliminar " + sessionText(list.length) + " de esta máquina?"
  if (names.length === 0) return head + " Ninguna está adjuntada."
  return head + " Adjuntas (en uso): " + names.join(", ") + "."
}

function killAllConfirmSecond(sessions) {
  var list = Array.isArray(sessions) ? sessions : []
  if (list.length === 0) return ""
  var names = attachedNames(list)
  var head = "Última confirmación: se cierra el server de tmux y no queda ninguna sesión viva"
  if (names.length === 0) return head + "."
  return head + ". Las adjuntas (" + names.join(", ") + ") pierden su trabajo."
}

if (typeof module !== "undefined") {
  module.exports = {
    widgetGlyph: widgetGlyph,
    sessionFormat: sessionFormat,
    asString: asString,
    asNumber: asNumber,
    plural: plural,
    shellQuote: shellQuote,
    parseSessions: parseSessions,
    sameSessions: sameSessions,
    ageText: ageText,
    windowText: windowText,
    sessionText: sessionText,
    rowMeta: rowMeta,
    barText: barText,
    tooltipText: tooltipText,
    attachCommand: attachCommand,
    killSessionArgv: killSessionArgv,
    killServerArgv: killServerArgv,
    sessionByName: sessionByName,
    attachedNames: attachedNames,
    killConfirmMessage: killConfirmMessage,
    killConfirmSecond: killConfirmSecond,
    killAllConfirmMessage: killAllConfirmMessage,
    killAllConfirmSecond: killAllConfirmSecond
  }
}
