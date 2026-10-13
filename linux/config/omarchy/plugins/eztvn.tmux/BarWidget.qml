import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "eztvn.tmux"

  readonly property real hPad: Style.spaceReal(8.75)
  readonly property int refreshMs: Math.max(1000, Math.round(Number(setting("refreshIntervalSec", 5)) * 1000))
  readonly property int sessionCount: monitor.count
  readonly property string barLabel: Model.barText(monitor.count)
  readonly property string tooltipText: Model.tooltipText(monitor.count)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool panelOpen: root.opened
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function refresh() { monitor.refresh() }

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

  implicitWidth: root.vertical ? root.barSize : button.labelWidth + hPad * 2
  implicitHeight: root.vertical ? button.implicitHeight : root.barSize

  TmuxSessions {
    id: monitor
    refreshMs: root.refreshMs
    panelOpen: root.panelOpen
  }

  IpcHandler {
    target: "eztvn.tmux"

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
    text: root.barLabel
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltipText
    dimmed: monitor.loaded && monitor.empty

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
