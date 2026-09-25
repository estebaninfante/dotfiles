import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Icono de barra que muestra el estado del interruptor maestro de animaciones
// de Hyprland (animations:enabled) y abre un panel para alternarlo.
//
// El toggle aplica en caliente con `hyprctl eval` y ademas persiste en
// ~/.local/state/omarchy/animations-enabled ("1"/"0"), que hyprland.lua lee al
// arrancar o recargar. Asi el estado sobrevive a reinicios de Hyprland.
Panel {
  id: root
  moduleName: "eztvn.animations"
  ipcTarget: "eztvn.animations"

  property bool animEnabled: true
  property bool busy: false
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/animations-enabled"

  function refresh() {
    if (!probe.running) probe.running = true
  }

  function setEnabled(value) {
    if (writeProc.running) return
    animEnabled = value
    busy = true
    writeProc.command = ["sh", "-c",
      "mkdir -p \"$HOME/.local/state/omarchy\" && " +
      "printf '%s\\n' '" + (value ? "1" : "0") + "' > \"$HOME/.local/state/omarchy/animations-enabled\" && " +
      "hyprctl eval 'hl.config({ animations = { enabled = " + (value ? "true" : "false") + " } })'"]
    writeProc.running = true
  }

  function toggleEnabled() { setEnabled(!animEnabled) }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: probe
    command: ["hyprctl", "-j", "getoption", "animations:enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed.bool === "boolean") root.animEnabled = parsed.bool
        } catch (e) {}
        root.busy = false
      }
    }
  }

  Process {
    id: writeProc
    onExited: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.animEnabled ? "\uf0e7" : "\uf00d"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Animaciones: " + (root.animEnabled ? "activadas" : "desactivadas")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleEnabled()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.toggleEnabled()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Animaciones"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          Column {
            width: parent.width - toggle.implicitWidth - parent.spacing
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.animEnabled ? "Activadas" : "Desactivadas"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Interruptor maestro del escritorio (animations:enabled)."
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          ToggleSwitch {
            id: toggle
            checked: root.animEnabled
            busy: root.busy
            foreground: root.bar.foreground
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.toggleEnabled()
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "El estado se guarda y se aplica al instante; sobrevive a recargas y reinicios de Hyprland."
          color: Qt.darker(root.bar.foreground, 1.6)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
