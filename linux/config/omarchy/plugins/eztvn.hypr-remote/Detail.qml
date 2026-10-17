import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Contenido del submenú de hypr-remote para empotrarlo dentro del menú de
// servicios (mismo popup). Reusa las secciones del plugin y expone la misma
// interfaz que su Panel para que las secciones funcionen sin cambios.
Item {
  id: detail

  property color foreground: Color.foreground
  property color urgentColor: Color.urgent
  property string fontFamily: Style.font.family

  readonly property color barForeground: foreground
  readonly property var status: remoteMonitor.status
  readonly property bool busy: remoteMonitor.busy
  readonly property var deviceRows: status && status.devices
    ? Model.deviceRows(status.devices, Date.now())
    : []

  signal confirmRequested(string action, string message, string second)

  implicitHeight: body.implicitHeight
  width: parent ? parent.width : implicitWidth

  property string pendingAction: ""
  property string pendingSecondMessage: ""

  function control(action, arg) {
    remoteMonitor.control(action, arg)
  }

  function copyText(value) {
    if (!value) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  function requestConfirm(action, message, secondMessage) {
    detail.pendingAction = String(action || "")
    detail.pendingSecondMessage = String(secondMessage || "")
    detail.confirmRequested(String(action || ""), String(message || ""), String(secondMessage || ""))
  }

  function handleConfirmed(action) {
    if (action === "rotate") remoteMonitor.control("rotate")
    else if (action === "unpairAll") remoteMonitor.control("unpair-all")
    detail.pendingAction = ""
    detail.pendingSecondMessage = ""
  }

  RemoteMonitor {
    id: remoteMonitor
    refreshMs: 2000
  }

  Column {
    id: body
    width: detail.width
    spacing: Style.space(12)

    PairSection {
      width: parent.width
      panel: detail
    }

    PanelSeparator {
      width: parent.width
      foreground: detail.foreground
    }

    DevicesSection {
      width: parent.width
      panel: detail
    }
  }
}
