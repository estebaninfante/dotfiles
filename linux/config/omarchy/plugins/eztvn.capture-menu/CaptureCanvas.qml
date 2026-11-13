import QtQuick
import "Annotations.js" as Annotations

// Trazo libre y formas sobre la captura congelada, y dueño del estado de la
// anotación. Es sólo pintura: la imagen final se compone en el script a partir
// de los trazos serializados, no de esta capa.
Canvas {
  id: root

  property string tool: "pencil"
  property string color: "#ffffff"
  property int strokeWidth: 4
  property var strokes: []
  property var activeStroke: null
  property int revision: 0
  property bool layerVisible: true

  readonly property bool drawing: activeStroke !== null

  visible: layerVisible
  onStrokesChanged: requestPaint()
  onActiveStrokeChanged: requestPaint()
  onRevisionChanged: requestPaint()

  function begin(x, y) {
    root.activeStroke = {
      tool: root.tool,
      color: root.color,
      width: root.strokeWidth,
      points: [{ x: x, y: y }]
    }
    root.revision++
  }

  function extend(x, y) {
    if (!root.activeStroke) return
    var st = root.activeStroke
    if (st.tool === "pencil") {
      var pts = st.points
      var last = pts[pts.length - 1]
      var dx = x - last.x
      var dy = y - last.y
      if (dx * dx + dy * dy < 1.5) return
      pts.push({ x: x, y: y })
      st.points = pts
    } else {
      st.points = [st.points[0], { x: x, y: y }]
    }
    root.revision++
  }

  function end() {
    var st = root.activeStroke
    root.activeStroke = null
    root.revision++
    if (!st) return
    var pts = st.points
    var dx = pts[pts.length - 1].x - pts[0].x
    var dy = pts[pts.length - 1].y - pts[0].y
    if (pts.length > 1 && (dx * dx + dy * dy) > 4)
      root.strokes = root.strokes.concat([st])
  }

  function undo() {
    if (root.strokes.length === 0) return
    root.strokes = root.strokes.slice(0, root.strokes.length - 1)
    root.revision++
  }

  function clear() {
    root.strokes = []
    root.activeStroke = null
    root.revision++
  }

  function serialized(scale) {
    return Annotations.serialize(root.strokes, scale)
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    for (var i = 0; i < root.strokes.length; i++)
      paintStroke(ctx, root.strokes[i])
    if (root.activeStroke)
      paintStroke(ctx, root.activeStroke)
  }

  function paintStroke(ctx, stroke) {
    if (!stroke || !stroke.points || stroke.points.length < 1) return
    var pts = stroke.points
    ctx.strokeStyle = stroke.color
    ctx.lineWidth = stroke.width

    if (stroke.tool === "pencil") {
      if (pts.length === 1) {
        ctx.fillStyle = stroke.color
        ctx.beginPath()
        ctx.arc(pts[0].x, pts[0].y, Math.max(0.5, stroke.width / 2), 0, Math.PI * 2)
        ctx.fill()
        return
      }
      ctx.beginPath()
      ctx.moveTo(pts[0].x, pts[0].y)
      for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
      ctx.stroke()
      return
    }

    if (pts.length < 2) return
    var a = pts[0]
    var b = pts[pts.length - 1]

    if (stroke.tool === "line") {
      ctx.beginPath()
      ctx.moveTo(a.x, a.y)
      ctx.lineTo(b.x, b.y)
      ctx.stroke()
      return
    }

    if (stroke.tool === "rect") {
      ctx.strokeRect(Math.min(a.x, b.x), Math.min(a.y, b.y),
                     Math.abs(b.x - a.x), Math.abs(b.y - a.y))
      return
    }

    if (stroke.tool === "arrow") {
      var dx = b.x - a.x
      var dy = b.y - a.y
      var len = Math.sqrt(dx * dx + dy * dy) || 1
      var ux = dx / len
      var uy = dy / len
      var head = Math.min(14, Math.max(8, stroke.width * 3))
      var bx = b.x - ux * head
      var by = b.y - uy * head
      var px = -uy * head * 0.45
      var py = ux * head * 0.45
      ctx.beginPath()
      ctx.moveTo(a.x, a.y)
      ctx.lineTo(b.x, b.y)
      ctx.moveTo(bx + px, by + py)
      ctx.lineTo(b.x, b.y)
      ctx.lineTo(bx - px, by - py)
      ctx.stroke()
    }
  }
}
