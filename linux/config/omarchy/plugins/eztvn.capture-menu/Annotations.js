.pragma library

// Trazos de la capa de anotación: color de tema → hex, conversión HSV para el
// selector de color y serialización a píxeles del PNG congelado (el script los
// rasteriza con ImageMagick).

function part(v) {
  var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
  return s.length < 2 ? "0" + s : s
}

function colorHex(c) {
  return "#" + part(c.r) + part(c.g) + part(c.b)
}

// HSV (h 0..360, s 0..1, v 0..1) → "#rrggbb".
function hsvToHex(h, s, v) {
  var hh = (((h % 360) + 360) % 360) / 60
  var c = v * s
  var x = c * (1 - Math.abs(hh % 2 - 1))
  var m = v - c
  var r = 0, g = 0, b = 0
  if (hh < 1) { r = c; g = x }
  else if (hh < 2) { r = x; g = c }
  else if (hh < 3) { g = c; b = x }
  else if (hh < 4) { g = x; b = c }
  else if (hh < 5) { r = x; b = c }
  else { r = c; b = x }
  return "#" + part(r + m) + part(g + m) + part(b + m)
}

// "#rrggbb" → { h: 0..360, s: 0..1, v: 0..1 }; null si no es un hex válido.
function hexToHsv(hex) {
  var m = /^#?([0-9a-f]{6})$/i.exec(String(hex || ""))
  if (!m) return null
  var n = parseInt(m[1], 16)
  var r = ((n >> 16) & 255) / 255
  var g = ((n >> 8) & 255) / 255
  var b = (n & 255) / 255
  var max = Math.max(r, g, b)
  var d = max - Math.min(r, g, b)
  var h = 0
  if (d > 0) {
    if (max === r) h = ((g - b) / d) % 6
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
    if (h < 0) h += 360
  }
  return { h: h, s: max === 0 ? 0 : d / max, v: max }
}

function serialize(strokes, scale) {
  if (!strokes || strokes.length === 0) return ""
  var out = []
  for (var i = 0; i < strokes.length; i++) {
    var src = strokes[i]
    var pts = []
    for (var j = 0; j < src.points.length; j++) {
      pts.push({
        x: Math.round(src.points[j].x * scale),
        y: Math.round(src.points[j].y * scale)
      })
    }
    out.push({
      tool: src.tool,
      color: src.color,
      width: Math.max(1, Math.round(src.width * scale)),
      points: pts
    })
  }
  return JSON.stringify({ strokes: out })
}
