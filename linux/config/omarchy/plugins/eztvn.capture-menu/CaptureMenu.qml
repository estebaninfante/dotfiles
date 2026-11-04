import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// PrintScreen: congela la pantalla al instante (el PNG lo toma capture-menu
// antes de abrir esto) y entra directo en la selección de región: arrastrás el
// recuadro y queda copiado, sin pasar por ninguna barra. Un clic sin arrastre
// abre la barra (región, ventana, pantalla, grabar). La imagen congelada y el
// recuadro viven en esta capa: no entran en el archivo porque la captura se
// recorta del PNG original.
Item {
  id: root

  property bool opened: false
  property string selectionFile: ""
  property string doneFile: ""
  property string imagePath: ""
  property string mode: "menu" // "menu" | "region"
  property int selectedIndex: 0

  property real dragX0: 0
  property real dragY0: 0
  property real dragX1: 0
  property real dragY1: 0
  property bool dragging: false

  readonly property real selX: Math.min(dragX0, dragX1)
  readonly property real selY: Math.min(dragY0, dragY1)
  readonly property real selW: Math.abs(dragX1 - dragX0)
  readonly property real selH: Math.abs(dragY1 - dragY0)

  readonly property var rows: [
    { key: "record", icon: "󰻂", label: "Grabar" },
    { key: "region", icon: "󰹑", label: "Región" },
    { key: "window", icon: "󰖲", label: "Ventana" },
    { key: "full",   icon: "󰹹", label: "Pantalla" }
  ]

  function open(payloadJson) {
    var p = ({})
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { p = ({}) }
    root.selectionFile = String(p.selectionFile || "")
    root.doneFile = String(p.doneFile || "")
    root.imagePath = String(p.imagePath || "")
    // Print (imagen) abre directo en selección de región: arrastrás y listo,
    // sin pasar por la barra. Un clic sin arrastre abre la barra; Shift+Print
    // (grabar) abre la barra directamente.
    root.mode = String(p.defaultAction || "image") === "record" ? "menu" : "region"
    root.selectedIndex = root.mode === "menu" ? 0 : 1
    root.dragging = false
    root.opened = true
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function finish(key) {
    var selection = root.selectionFile
    var done = root.doneFile
    root.selectionFile = ""
    root.doneFile = ""
    if (done !== "") {
      if (key === null || key === undefined)
        resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(done)]
      else
        resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(key) + " > " + Util.shellQuote(selection) + "; : > " + Util.shellQuote(done)]
      resultProc.running = true
    } else {
      root.opened = false
    }
  }

  function move(delta) {
    if (root.rows.length === 0) return
    root.selectedIndex = (root.selectedIndex + delta + root.rows.length) % root.rows.length
  }

  function activate(index) {
    if (index < 0 || index >= root.rows.length) return
    if (root.rows[index].key === "region") root.chooseRegion()
    else root.finish(root.rows[index].key)
  }

  function chooseRegion() {
    root.mode = "region"
    root.dragging = false
    keyCatcher.forceActiveFocus()
  }

  // Coordenada de pantalla (lógica) → píxeles del PNG congelado.
  function imageCoord(value, horizontal) {
    var natural = horizontal ? frozen.implicitWidth : frozen.implicitHeight
    var total = horizontal ? panel.width : panel.height
    if (natural > 0 && total > 0) return Math.round(value * natural / total)
    return Math.round(value * Screen.devicePixelRatio)
  }

  function completeRegion() {
    var x = root.imageCoord(root.selX, true)
    var y = root.imageCoord(root.selY, false)
    var w = root.imageCoord(root.selW, true)
    var h = root.imageCoord(root.selH, false)
    if (w < 4 || h < 4) {
      root.mode = "menu"
      return
    }
    root.finish("region:" + x + "," + y + "," + w + "," + h)
  }

  Process {
    id: resultProc
    onExited: root.opened = false
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "capture-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // La pantalla congelada, tal como estaba antes de abrir el overlay.
    Image {
      id: frozen
      anchors.fill: parent
      source: root.imagePath
      fillMode: Image.Stretch
      asynchronous: false
      cache: false
      smooth: true
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.18)
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.opened

      Keys.onEscapePressed: root.finish(null)
      Keys.onLeftPressed: if (root.mode === "menu") root.move(-1)
      Keys.onRightPressed: if (root.mode === "menu") root.move(1)
      Keys.onReturnPressed: if (root.mode === "menu") root.activate(root.selectedIndex)
      Keys.onEnterPressed: if (root.mode === "menu") root.activate(root.selectedIndex)
      Keys.onPressed: function(event) {
        if (root.mode === "menu" && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
          root.activate(event.key - Qt.Key_1)
          event.accepted = true
        }
      }

      // Clic fuera de la barra: cancela, como el menú de Windows.
      MouseArea {
        anchors.fill: parent
        visible: root.mode === "menu"
        onClicked: root.finish(null)
      }

      // Selección de región sobre la imagen congelada.
      MouseArea {
        anchors.fill: parent
        visible: root.mode === "region"
        cursorShape: Qt.CrossCursor

        onPressed: function(mouse) {
          root.dragX0 = mouse.x
          root.dragY0 = mouse.y
          root.dragX1 = mouse.x
          root.dragY1 = mouse.y
          root.dragging = true
        }
        onPositionChanged: function(mouse) {
          if (!root.dragging) return
          root.dragX1 = mouse.x
          root.dragY1 = mouse.y
        }
        onReleased: function(mouse) {
          if (!root.dragging) return
          root.dragX1 = mouse.x
          root.dragY1 = mouse.y
          root.dragging = false
          root.completeRegion()
        }
      }

      Rectangle {
        visible: root.mode === "region" && root.dragging && root.selW > 0 && root.selH > 0
        x: root.selX
        y: root.selY
        width: root.selW
        height: root.selH
        color: "transparent"
        border.width: Math.max(1, Style.space(1))
        border.color: Color.menu.selectedText
      }

      Rectangle {
        id: card
        visible: root.mode === "menu"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.bar.sizeHorizontal + Style.space(12)
        width: rowLayout.implicitWidth + Style.space(10) * 2
        height: rowLayout.implicitHeight + Style.space(8) * 2
        radius: Style.cornerRadius
        color: Color.menu.background
        border.width: Math.max(1, Style.space(1))
        border.color: Color.menu.border

        RowLayout {
          id: rowLayout
          anchors.centerIn: parent
          spacing: Style.space(4)

          Repeater {
            model: root.rows

            delegate: Rectangle {
              id: button
              required property var modelData
              required property int index

              readonly property bool active: index === root.selectedIndex

              width: Style.space(86)
              height: Style.space(56)
              radius: Math.max(0, Style.cornerRadius - Style.space(4))
              color: button.active ? Color.menu.selectedBackground : "transparent"

              ColumnLayout {
                anchors.centerIn: parent
                spacing: Style.space(2)

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: button.modelData.icon
                  color: button.active ? Color.menu.selectedText : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.iconLarge
                }

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: button.modelData.label
                  color: button.active ? Color.menu.selectedText : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: button.active
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.selectedIndex = button.index
                onClicked: root.activate(button.index)
              }
            }
          }
        }
      }

      // Pista durante la selección de región.
      Rectangle {
        visible: root.mode === "region"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.bar.sizeHorizontal + Style.space(12)
        width: hint.implicitWidth + Style.space(20)
        height: hint.implicitHeight + Style.space(10)
        radius: Style.cornerRadius
        color: Color.menu.background
        border.width: Math.max(1, Style.space(1))
        border.color: Color.menu.border

        Text {
          id: hint
          anchors.centerIn: parent
          text: "Arrastrá para elegir la región · Esc cancela · clic abre el menú"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
