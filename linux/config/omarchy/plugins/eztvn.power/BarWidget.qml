import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "eztvn.power"

  readonly property bool panelOpen: panelLoader.item ? panelLoader.item.opened === true : false

  readonly property string barText: {
    if (!monitor.batteryPresent) return monitor.profileGlyph
    if (root.vertical) return monitor.batteryGlyph
    return monitor.batteryGlyph + " " + monitor.percentText + " " + monitor.wattsText
  }

  readonly property string tooltipText: {
    if (!monitor.batteryPresent) return "Power profile: " + (monitor.activeProfile || "—")
    return monitor.percentText + " · " + monitor.wattsText + " · " + monitor.modeText
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("monitor" in target) target.monitor = monitor
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  readonly property real openPanelIndicatorWidth: button.labelWidth

  PowerMonitor {
    id: monitor
    settings: root.settings
    panelOpen: root.panelOpen
  }

  IpcHandler {
    target: "eztvn.power"

    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.broadcast("togglePanel") }
    function refresh(): void { monitor.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltipText

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.togglePanel()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
