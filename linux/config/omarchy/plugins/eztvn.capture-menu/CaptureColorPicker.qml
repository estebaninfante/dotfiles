import QtQuick
import qs.Commons
import "Annotations.js" as Annotations

// Selector de color del trazo: cuadrado de saturación/valor y barra de tono.
// Se abre sobre la barra inferior; cada cambio emite el color elegido.
Item {
  id: root

  property string color: "#ffffff"
  property bool opened: false

  property real hue: 200
  property real sat: 1
  property real val: 1
  property bool dragging: false

  signal picked(string color)

  implicitWidth: card.width
  implicitHeight: card.height

  visible: root.opened

  // Sincroniza desde el color actual, salvo mientras el usuario arrastra.
  function syncFromColor() {
    var c = Annotations.hexToHsv(root.color)
    if (!c) return
    root.hue = c.h
    root.sat = c.s
    root.val = c.v
  }

  function publish() {
    root.picked(Annotations.hsvToHex(root.hue, root.sat, root.val))
  }

  function setSv(x, y) {
    root.sat = Math.max(0, Math.min(1, x / sv.width))
    root.val = 1 - Math.max(0, Math.min(1, y / sv.height))
    root.publish()
  }

  function setHue(x) {
    root.hue = Math.max(0, Math.min(1, x / hueBar.width)) * 360
    root.publish()
  }

  onColorChanged: if (!root.dragging) root.syncFromColor()
  onOpenedChanged: if (root.opened) root.syncFromColor()
  Component.onCompleted: root.syncFromColor()

  Rectangle {
    id: card
    width: sv.width + Style.space(16)
    height: sv.height + hueBar.height + Style.space(24)
    radius: Math.max(Style.space(8), Style.cornerRadius)
    color: Color.menu.background
    border.width: Math.max(1, Style.space(1))
    border.color: Util.alpha(Color.menu.border, 0.5)

    // Saturación (eje X) y valor (eje Y) para el tono elegido.
    Canvas {
      id: sv
      width: Style.space(196)
      height: Style.space(96)
      x: Style.space(8)
      y: Style.space(8)

      property real currentHue: root.hue
      onCurrentHueChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = Annotations.hsvToHex(root.hue, 1, 1)
        ctx.fillRect(0, 0, width, height)
        var white = ctx.createLinearGradient(0, 0, width, 0)
        white.addColorStop(0, "rgba(255,255,255,1)")
        white.addColorStop(1, "rgba(255,255,255,0)")
        ctx.fillStyle = white
        ctx.fillRect(0, 0, width, height)
        var black = ctx.createLinearGradient(0, 0, 0, height)
        black.addColorStop(0, "rgba(0,0,0,0)")
        black.addColorStop(1, "rgba(0,0,0,1)")
        ctx.fillStyle = black
        ctx.fillRect(0, 0, width, height)
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        onPressed: function(mouse) {
          root.dragging = true
          root.setSv(mouse.x, mouse.y)
        }
        onPositionChanged: function(mouse) {
          if (pressed) root.setSv(mouse.x, mouse.y)
        }
        onReleased: root.dragging = false
      }
    }

    // Tono: de rojo a rojo pasando por todo el círculo cromático.
    Canvas {
      id: hueBar
      width: sv.width
      height: Style.space(14)
      x: sv.x
      y: sv.y + sv.height + Style.space(8)

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var g = ctx.createLinearGradient(0, 0, width, 0)
        g.addColorStop(0, "#ff0000")
        g.addColorStop(1 / 6, "#ffff00")
        g.addColorStop(2 / 6, "#00ff00")
        g.addColorStop(3 / 6, "#00ffff")
        g.addColorStop(4 / 6, "#0000ff")
        g.addColorStop(5 / 6, "#ff00ff")
        g.addColorStop(1, "#ff0000")
        ctx.fillStyle = g
        ctx.fillRect(0, 0, width, height)
      }

      Rectangle {
        width: Math.max(Style.space(3), Style.space(1))
        height: parent.height + Style.space(4)
        y: -Style.space(2)
        x: Math.max(0, Math.min(parent.width - width,
                                root.hue / 360 * parent.width - width / 2))
        color: Color.menu.text
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        onPressed: function(mouse) {
          root.dragging = true
          root.setHue(mouse.x)
        }
        onPositionChanged: function(mouse) {
          if (pressed) root.setHue(mouse.x)
        }
        onReleased: root.dragging = false
      }
    }
  }
}
