pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var panel: null
  property bool qrReloading: false
  readonly property var status: panel ? panel.status : null
  readonly property color foreground: panel ? panel.barForeground : Color.foreground
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property bool showQr: !!(status && status.running && status.qrPath)
  readonly property int qrSize: Style.space(176)

  width: parent ? parent.width : 100
  spacing: Style.space(8)

  function reloadQr() {
    root.qrReloading = true
    Qt.callLater(function() { root.qrReloading = false })
  }

  PanelSectionHeader {
    text: "EMPAREJAR"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  BorderSurface {
    width: parent.width
    height: root.qrSize + Style.space(20)
    color: "#ffffff"
    borderSpec: Border.flat(root.foreground, Style.normalBorderWidth)
    radius: Style.cornerRadius

    Loader {
      id: qrLoader
      anchors.centerIn: parent
      active: root.showQr && !root.qrReloading
      sourceComponent: qrImage
    }

    Text {
      anchors.centerIn: parent
      visible: !root.showQr
      text: "QR no disponible"
      color: "#101315"
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Component {
      id: qrImage
      Image {
        width: root.qrSize
        height: root.qrSize
        source: root.status ? Util.fileUrl(root.status.qrPath) : ""
        cache: false
        asynchronous: true
        fillMode: Image.PreserveAspectFit
      }
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.WrapAnywhere
    text: root.status && root.status.running ? root.status.pairingUrl : "—"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    Button {
      text: "Copiar"
      enabled: root.status && root.status.running && root.status.pairingUrl !== ""
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      onClicked: if (root.panel) root.panel.copyText(root.status.pairingUrl)
    }

    Button {
      text: "Regenerar código"
      enabled: root.showQr && !(root.panel && root.panel.busy)
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      onClicked: if (root.panel) root.panel.requestConfirm("rotate", "¿Regenerar el código de emparejar? El QR y la URL actuales dejan de funcionar al instante.", "")
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Escanea el QR con el teléfono o abre la URL desde la red local."
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Connections {
    target: root.panel ? root.panel.monitor : null
    function onActionFinished(action) {
      if (action === "rotate") root.reloadQr()
    }
  }
}
