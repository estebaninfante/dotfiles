import QtQuick
import qs.Commons

// Capa de selección sobre la captura congelada: oscurece todo menos el
// recuadro elegido (cuatro velos, sin máscaras), y dibuja borde, esquinas,
// guías y la medida en píxeles. La captura real se recorta del PNG original,
// no de lo que se ve aquí.
Item {
  id: root

  property bool regionMode: false
  property bool dragging: false
  property real selX: 0
  property real selY: 0
  property real selW: 0
  property real selH: 0
  property real pointerX: -1
  property real pointerY: -1

  readonly property bool hasSelection: regionMode && selW >= 1 && selH >= 1
  readonly property bool showCrosshair: regionMode && !dragging &&
      pointerX >= 0 && pointerY >= 0 && pointerX <= width && pointerY <= height
  readonly property color scrimColor: Util.alpha(Color.background, 0.55)
  readonly property color accentColor: Color.accent

  function clampWidth(value) {
    return Math.max(0, value)
  }

  // Sin selección (o en modo barra) el velo es una sola capa a pantalla completa.
  Rectangle {
    anchors.fill: parent
    visible: !root.hasSelection
    color: root.scrimColor
  }

  Rectangle {
    visible: root.hasSelection
    x: 0
    y: 0
    width: parent.width
    height: root.selY
    color: root.scrimColor
  }

  Rectangle {
    visible: root.hasSelection
    x: 0
    y: root.selY + root.selH
    width: parent.width
    height: root.clampWidth(parent.height - root.selY - root.selH)
    color: root.scrimColor
  }

  Rectangle {
    visible: root.hasSelection
    x: 0
    y: root.selY
    width: root.selX
    height: root.selH
    color: root.scrimColor
  }

  Rectangle {
    visible: root.hasSelection
    x: root.selX + root.selW
    y: root.selY
    width: root.clampWidth(parent.width - root.selX - root.selW)
    height: root.selH
    color: root.scrimColor
  }

  // Halo suave + borde nítido: se lee bien sobre fondos claros y oscuros.
  Rectangle {
    visible: root.hasSelection
    x: root.selX
    y: root.selY
    width: root.selW
    height: root.selH
    radius: Style.space(2)
    color: "transparent"
    border.width: Style.space(4)
    border.color: Util.alpha(root.accentColor, 0.18)
  }

  Rectangle {
    visible: root.hasSelection
    x: root.selX
    y: root.selY
    width: root.selW
    height: root.selH
    radius: Style.space(2)
    color: "transparent"
    border.width: Math.max(1, Style.space(1))
    border.color: Util.alpha(root.accentColor, 0.95)
  }

  Repeater {
    model: 4

    delegate: Rectangle {
      required property int index
      readonly property bool onRight: index % 2 === 1
      readonly property bool onBottom: index >= 2
      visible: root.hasSelection && root.selW > Style.space(12) && root.selH > Style.space(12)
      x: (onRight ? root.selX + root.selW : root.selX) - width / 2
      y: (onBottom ? root.selY + root.selH : root.selY) - height / 2
      width: Style.space(7)
      height: width
      radius: Style.space(2)
      color: root.accentColor
      border.width: Math.max(1, Style.space(1))
      border.color: Util.alpha(Color.background, 0.55)
    }
  }

  // Guías de puntero mientras se elige el recuadro.
  Rectangle {
    visible: root.showCrosshair
    x: Math.round(root.pointerX)
    y: 0
    width: Math.max(1, Style.space(1))
    height: parent.height
    color: Util.alpha(root.accentColor, 0.35)
  }

  Rectangle {
    visible: root.showCrosshair
    x: 0
    y: Math.round(root.pointerY)
    width: parent.width
    height: Math.max(1, Style.space(1))
    color: Util.alpha(root.accentColor, 0.35)
  }

  Rectangle {
    visible: root.hasSelection
    width: sizeLabel.implicitWidth + Style.space(12)
    height: sizeLabel.implicitHeight + Style.space(4)
    x: Util.clamp(root.selX + root.selW - width, Style.space(8), root.width - width - Style.space(8))
    y: (root.selY + root.selH + Style.space(8) + height < root.height)
       ? root.selY + root.selH + Style.space(8)
       : Math.max(Style.space(8), root.selY - height - Style.space(8))
    radius: Style.space(4)
    color: Util.alpha(Color.background, 0.88)
    border.width: Math.max(1, Style.space(1))
    border.color: Util.alpha(root.accentColor, 0.5)

    Text {
      id: sizeLabel
      anchors.centerIn: parent
      text: Math.round(root.selW) + " × " + Math.round(root.selH)
      color: Color.foreground
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
