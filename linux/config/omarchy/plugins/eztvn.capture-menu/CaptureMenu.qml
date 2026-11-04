import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Barra flotante de PrintScreen: un solo overlay arriba al centro, sin scrim
// ni blur, para elegir entre capturar imagen o grabar pantalla. La lógica
// (qué acción correr y esperar a que el overlay desaparezca) vive en
// ~/dotfiles/linux/bin/capture-menu; este plugin sólo devuelve la tecla.
Item {
  id: root

  property bool opened: false
  property string selectionFile: ""
  property string doneFile: ""
  property bool recording: false
  property int selectedIndex: 0

  readonly property var rows: recording
    ? [
        { key: "stop",   icon: "󰓛", label: "Detener" },
        { key: "region", icon: "󰹑", label: "Región" },
        { key: "window", icon: "󰖲", label: "Ventana" },
        { key: "full",   icon: "󰹹", label: "Pantalla" }
      ]
    : [
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
    root.recording = p.recording === true
    root.selectedIndex = 0
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
    root.finish(root.rows[index].key)
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
    // Sólo la barra recibe clics; el resto de la pantalla pasa de largo.
    mask: Region { item: card }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.opened

      Keys.onEscapePressed: root.finish(null)
      Keys.onLeftPressed: root.move(-1)
      Keys.onRightPressed: root.move(1)
      Keys.onReturnPressed: root.activate(root.selectedIndex)
      Keys.onEnterPressed: root.activate(root.selectedIndex)
      Keys.onPressed: function(event) {
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
          root.activate(event.key - Qt.Key_1)
          event.accepted = true
        }
      }

      Rectangle {
        id: card
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
    }
  }
}
