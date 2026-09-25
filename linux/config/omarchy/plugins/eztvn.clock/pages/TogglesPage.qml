import QtQuick
import qs.Commons
import qs.Ui
import "../toggles"
import "../components"

// Toggles page: the quick switches you want one keypress away — radios, audio,
// screen, and notification silencing. State comes from TogglesProbe; actions
// are fire-and-refresh, with a short local override so the switch moves on the
// click instead of after the probe round-trip.
Item {
  id: root

  property bool panelActive: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // Local overrides for switches that have been clicked but not yet re-probed.
  property var optimistic: ({})

  readonly property var info: probe.data

  readonly property bool wifi: flag("wifi", false)
  readonly property bool bluetooth: flag("bluetooth", false)
  readonly property bool airplane: flag("airplane", false)
  readonly property bool muted: flag("muted", false)
  readonly property bool nightlight: flag("nightlight", false)
  readonly property bool dnd: flag("dnd", false)
  readonly property int volume: Math.max(0, Math.min(100, Math.round(Number(info.volume || 0))))
  readonly property int brightness: info.brightness === undefined ? -1 : Number(info.brightness)

  TogglesProbe {
    id: probe
    active: root.panelActive
  }

  Connections {
    target: probe
    function onDataChanged() { root.reconcile() }
  }

  function refresh() {
    probe.refresh()
  }

  function rawFlag(name) {
    var value = probe.data ? probe.data[name] : undefined
    return value === true || value === "true"
  }

  function flag(name, fallback) {
    if (root.optimistic[name] !== undefined) return root.optimistic[name]
    var value = probe.data ? probe.data[name] : undefined
    return value === undefined ? fallback : (value === true || value === "true")
  }

  function toggleFlag(name, action) {
    var next = !flag(name, false)
    var merged = {}
    for (var key in root.optimistic) merged[key] = root.optimistic[key]
    merged[name] = next
    root.optimistic = merged
    probe.run(action)
  }

  // Drop an override once the probe agrees with it, so the display settles on
  // the real state and a failed action visibly snaps back.
  function reconcile() {
    var remaining = {}
    var dropped = false
    for (var key in root.optimistic) {
      if (rawFlag(key) === root.optimistic[key]) dropped = true
      else remaining[key] = root.optimistic[key]
    }
    if (dropped) root.optimistic = remaining
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "CONEXIONES"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Toggle {
      width: parent.width
      label: "Wi-Fi"
      description: root.wifi ? "Activado" : "Desactivado"
      checked: root.wifi
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.toggleFlag("wifi", ["wifi"])
    }

    Toggle {
      width: parent.width
      label: "Bluetooth"
      description: root.bluetooth ? "Activado" : "Desactivado"
      checked: root.bluetooth
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.toggleFlag("bluetooth", ["bluetooth"])
    }

    Toggle {
      width: parent.width
      label: "Modo avión"
      description: "Baja Wi-Fi y Bluetooth a la vez"
      checked: root.airplane
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.toggleFlag("airplane", ["airplane"])
    }

    PanelSeparator { foreground: root.foreground }

    PanelSectionHeader {
      text: "AUDIO"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Toggle {
      width: parent.width
      label: "Silencio"
      description: root.muted ? "Salida silenciada" : "Salida activa"
      checked: root.muted
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.toggleFlag("muted", ["mute"])
    }

    StatBar {
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      label: "VOLUMEN"
      value: root.volume + "%"
      fraction: root.volume / 100
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      readonly property real cellWidth: (width - spacing) / 2

      Button {
        width: parent.cellWidth
        text: "Bajar"
        iconText: "󰍴"
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        onClicked: probe.run(["volume", "down"])
      }

      Button {
        width: parent.cellWidth
        text: "Subir"
        iconText: "󰍶"
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        onClicked: probe.run(["volume", "up"])
      }
    }

    PanelSeparator { foreground: root.foreground }

    PanelSectionHeader {
      text: "PANTALLA"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Toggle {
      width: parent.width
      label: "Luz nocturna"
      description: root.nightlight ? "Temperatura cálida" : "Temperatura normal"
      checked: root.nightlight
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.toggleFlag("nightlight", ["nightlight"])
    }

    StatBar {
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      label: "BRILLO"
      value: root.brightness >= 0 ? root.brightness + "%" : "—"
      fraction: root.brightness >= 0 ? root.brightness / 100 : 0
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      readonly property real cellWidth: (width - spacing) / 2

      Button {
        width: parent.cellWidth
        text: "Bajar"
        iconText: "󰃞"
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        onClicked: probe.run(["brightness", "down"])
      }

      Button {
        width: parent.cellWidth
        text: "Subir"
        iconText: "󰃠"
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        onClicked: probe.run(["brightness", "up"])
      }
    }

    PanelSeparator { foreground: root.foreground }

    PanelSectionHeader {
      text: "NOTIFICACIONES"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Toggle {
      width: parent.width
      label: "No molestar"
      description: root.dnd ? "Silenciadas" : "Visibles"
      checked: root.dnd
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.toggleFlag("dnd", ["dnd"])
    }
  }
}