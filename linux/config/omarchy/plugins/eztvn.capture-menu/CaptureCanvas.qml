import QtQuick

// Trazo libre y formas sobre la captura congelada. Es sólo pintura: la imagen
// final se compone en el script a partir de estos trazos, no de esta capa.
Canvas {
  id: root

  property var strokes: []
  property var activeStroke: null
  property int revision: 0
  property bool enabled: true

  visible: enabled

  onStrokesChanged: requestPaint()
  onActiveStrokeChanged: requestPaint()
  onRevisionChanged: requestPaint()

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
