.pragma library

// Trazos de la capa de anotación: color de tema → hex y serialización a
// píxeles del PNG congelado (el script los rasteriza con ImageMagick).

function colorHex(c) {
  function part(v) {
    var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
    return s.length < 2 ? "0" + s : s
  }
  return "#" + part(c.r) + part(c.g) + part(c.b)
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
