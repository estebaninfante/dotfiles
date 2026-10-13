import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var samples: []
  property int minutes: 10
  property int revision: 0
  property bool active: false
  property color foreground: Color.foreground
  property real hoverX: -1

  readonly property color drainColor: Color.accent
  readonly property color chargeColor: {
    var hue = Color.accent.hslHue
    if (hue < 0) hue = 0.08
    return Qt.hsla(
      (hue + 0.12) % 1,
      Math.max(0.5, Color.accent.hslSaturation),
      Math.min(0.72, Math.max(0.45, Color.accent.hslLightness)),
      1
    )
  }

  implicitHeight: Style.space(112)

  function currentSamples() {
    if (!root.active) return []
    return Model.windowSamples(root.samples, root.minutes, Date.now() / 1000)
  }

  function draw(ctx) {
    var width = canvas.width
    var height = canvas.height
    if (!root.active || width <= 0 || height <= 0) return

    ctx.clearRect(0, 0, width, height)

    var padLeft = Style.space(4)
    var padRight = Style.space(4)
    var padTop = Style.space(16)
    var padBottom = Style.space(4)
    var plotWidth = width - padLeft - padRight
    var plotHeight = height - padTop - padBottom

    ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
    ctx.lineWidth = 1
    for (var grid = 0; grid <= 3; grid++) {
      var gridY = padTop + plotHeight * grid / 3
      ctx.beginPath()
      ctx.moveTo(padLeft, gridY)
      ctx.lineTo(padLeft + plotWidth, gridY)
      ctx.stroke()
    }

    var list = root.currentSamples()
    if (list.length < 2) return

    var maxWatts = 0
    for (var i = 0; i < list.length; i++) {
      if (list[i].w > maxWatts) maxWatts = list[i].w
      if (list[i].c > maxWatts) maxWatts = list[i].c
    }
    var span = maxWatts > 0 ? maxWatts : 1
    var first = list[0].t
    var timeSpan = (list[list.length - 1].t - first) > 0 ? (list[list.length - 1].t - first) : 1

    function xAt(sample) { return padLeft + (sample.t - first) / timeSpan * plotWidth }
    function yAtValue(value) { return padTop + plotHeight - Math.min(1, value / span) * plotHeight }

    function drawArea(key, color) {
      var active = false
      var lastX = 0
      ctx.beginPath()
      for (var j = 0; j < list.length; j++) {
        var value = key === "charge" ? list[j].c : list[j].w
        var gap = j > 0 ? list[j].t - list[j - 1].t : 0
        if (value <= 0.05 || gap > 60) {
          if (active) {
            ctx.lineTo(lastX, padTop + plotHeight)
            ctx.closePath()
            active = false
          }
          continue
        }
        var x = xAt(list[j])
        var y = yAtValue(value)
        if (!active) {
          ctx.moveTo(x, padTop + plotHeight)
          ctx.lineTo(x, y)
          active = true
        } else {
          ctx.lineTo(x, y)
        }
        lastX = x
      }
      if (active) {
        ctx.lineTo(lastX, padTop + plotHeight)
        ctx.closePath()
      }
      ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.14)
      ctx.fill()
    }

    function drawLine(key, color) {
      var active = false
      ctx.beginPath()
      for (var j = 0; j < list.length; j++) {
        var value = key === "charge" ? list[j].c : list[j].w
        var gap = j > 0 ? list[j].t - list[j - 1].t : 0
        if (value <= 0.05 || gap > 60) {
          active = false
          continue
        }
        var x = xAt(list[j])
        var y = yAtValue(value)
        if (!active) {
          ctx.moveTo(x, y)
          active = true
        } else {
          ctx.lineTo(x, y)
        }
      }
      ctx.strokeStyle = color
      ctx.lineWidth = 2
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.stroke()
    }

    drawArea("discharge", root.drainColor)
    drawArea("charge", root.chargeColor)
    drawLine("discharge", root.drainColor)
    drawLine("charge", root.chargeColor)

    var last = list[list.length - 1]
    if (last.w > 0.05) {
      ctx.beginPath()
      ctx.arc(xAt(last), yAtValue(last.w), 3.5, 0, Math.PI * 2)
      ctx.fillStyle = root.drainColor
      ctx.fill()
    }
    if (last.c > 0.05) {
      ctx.beginPath()
      ctx.arc(xAt(last), yAtValue(last.c), 3.5, 0, Math.PI * 2)
      ctx.fillStyle = root.chargeColor
      ctx.fill()
    }

    ctx.fillStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
    ctx.font = Style.font.family + " " + Style.font.caption + "px"
    ctx.textBaseline = "top"
    ctx.textAlign = "left"
    ctx.fillText(maxWatts.toFixed(1) + " W", padLeft, 0)
    ctx.textBaseline = "alphabetic"
    ctx.textAlign = "right"
    ctx.fillText(Model.minutesLabel(root.minutes), padLeft + plotWidth, padTop + plotHeight)

    if (root.hoverX >= padLeft && root.hoverX <= padLeft + plotWidth) {
      var ratio = (root.hoverX - padLeft) / plotWidth
      var hoverTime = first + ratio * timeSpan
      var hovered = list[0]
      var best = Math.abs(list[0].t - hoverTime)
      for (i = 1; i < list.length; i++) {
        var distance = Math.abs(list[i].t - hoverTime)
        if (distance < best) { best = distance; hovered = list[i] }
      }
      var hx = xAt(hovered)
      var hoveringCharge = hovered.c > 0.05
      var hoveredWatts = hoveringCharge ? hovered.c : hovered.w
      var hy = yAtValue(hoveredWatts)
      var hoverColor = hoveringCharge ? root.chargeColor : root.drainColor

      ctx.beginPath()
      ctx.moveTo(hx, padTop)
      ctx.lineTo(hx, padTop + plotHeight)
      ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.40)
      ctx.lineWidth = 1
      ctx.stroke()

      ctx.beginPath()
      ctx.arc(hx, hy, 3, 0, Math.PI * 2)
      ctx.fillStyle = hoverColor
      ctx.fill()

      ctx.font = Style.font.family + " " + Style.font.bodySmall + "px"
      var chipText = (hoveringCharge ? "CHARGE " : "DRAIN ") + Model.formatWatts(hoveredWatts)
      var chipWidth = ctx.measureText(chipText).width + Style.space(12)
      var chipHeight = Style.space(16)
      var chipX = Math.max(padLeft, Math.min(hx - chipWidth / 2, padLeft + plotWidth - chipWidth))
      var background = Color.background
      ctx.fillStyle = Qt.rgba(background.r, background.g, background.b, 0.88)
      ctx.fillRect(chipX, padTop, chipWidth, chipHeight)
      ctx.fillStyle = hoverColor
      ctx.textBaseline = "middle"
      ctx.textAlign = "center"
      ctx.fillText(chipText, chipX + chipWidth / 2, padTop + chipHeight / 2)
    }
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    onPaint: root.draw(getContext("2d"))
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Connections {
      target: root
      function onRevisionChanged() { if (root.active) canvas.requestPaint() }
      function onMinutesChanged() { if (root.active) canvas.requestPaint() }
      function onActiveChanged() { canvas.requestPaint() }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.CrossCursor
      onPositionChanged: function(mouse) {
        root.hoverX = mouse.x
        canvas.requestPaint()
      }
      onExited: {
        root.hoverX = -1
        canvas.requestPaint()
      }
    }
  }
}
