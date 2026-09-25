import QtQuick
import qs.Commons
import qs.Ui
import "../system"
import "../components"

// System page: live CPU, memory, swap, disk, temperature and uptime. Reads
// only from SystemProbe; this file is the drawing and the formatting rules.
Item {
  id: root

  property bool panelActive: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var info: probe.data
  readonly property real cpu: Number(info.cpu || 0)
  readonly property real memUsed: Number(info.memUsedKb || 0)
  readonly property real memTotal: Number(info.memTotalKb || 1)
  readonly property real swapUsed: Number(info.swapUsedKb || 0)
  readonly property real swapTotal: Number(info.swapTotalKb || 0)
  readonly property real diskUsed: Number(info.diskUsedKb || 0)
  readonly property real diskTotal: Number(info.diskTotalKb || 1)
  readonly property real tempC: (info.tempC === null || info.tempC === undefined) ? -1 : Number(info.tempC)

  SystemProbe {
    id: probe
    active: root.panelActive
  }

  function refresh() {
    probe.refresh()
  }

  function fmtKb(kb) {
    var gb = (Number(kb) || 0) / 1048576
    if (gb >= 100) return gb.toFixed(0) + " GB"
    if (gb >= 10) return gb.toFixed(1) + " GB"
    return gb.toFixed(2) + " GB"
  }

  function pct(part, total) {
    return total > 0 ? part / total : 0
  }

  function pctText(part, total) {
    return Math.round(pct(part, total) * 100) + "%"
  }

  function fmtUptime(sec) {
    var s = Math.max(0, Math.floor(Number(sec) || 0))
    var days = Math.floor(s / 86400); s -= days * 86400
    var hours = Math.floor(s / 3600); s -= hours * 3600
    var minutes = Math.floor(s / 60)
    if (days > 0) return days + "d " + hours + "h " + minutes + "m"
    if (hours > 0) return hours + "h " + minutes + "m"
    return minutes + "m"
  }

  function loadText() {
    var load = info.load
    if (!load || load.length === undefined || load.length === 0) return ""
    var parts = []
    for (var i = 0; i < load.length; i++) parts.push(Number(load[i]).toFixed(2))
    return parts.join("  ")
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(14)

    // ---- Hero: hostname over uptime/temperature, CPU as the trailing figure.
    Item {
      width: parent.width
      implicitHeight: Math.max(heroLabels.implicitHeight, heroCpu.implicitHeight)

      Column {
        id: heroLabels
        anchors.left: parent.left
        anchors.right: heroCpu.left
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.info.host || "—"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "uptime " + root.fmtUptime(root.info.uptimeSec)
            + (root.tempC >= 0 ? "  ·  " + Math.round(root.tempC) + " °C" : "")
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          elide: Text.ElideRight
        }
      }

      Text {
        id: heroCpu
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.cpu) + "%"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.displayLarge
        font.bold: true
      }
    }

    PanelSeparator { foreground: root.foreground }

    StatBar {
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      label: "CPU"
      value: Math.round(root.cpu) + "%" + (root.loadText() !== "" ? "  ·  " + root.loadText() : "")
      fraction: root.cpu / 100
    }

    StatBar {
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      label: "MEMORIA"
      value: root.fmtKb(root.memUsed) + " / " + root.fmtKb(root.memTotal)
        + "  (" + root.pctText(root.memUsed, root.memTotal) + "%)"
      fraction: root.pct(root.memUsed, root.memTotal)
    }

    StatBar {
      width: parent.width
      visible: root.swapTotal > 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      label: "SWAP"
      value: root.fmtKb(root.swapUsed) + " / " + root.fmtKb(root.swapTotal)
        + "  (" + root.pctText(root.swapUsed, root.swapTotal) + "%)"
      fraction: root.pct(root.swapUsed, root.swapTotal)
    }

    StatBar {
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      label: "DISCO /"
      value: root.fmtKb(root.diskUsed) + " / " + root.fmtKb(root.diskTotal)
        + "  (" + root.pctText(root.diskUsed, root.diskTotal) + "%)"
      fraction: root.pct(root.diskUsed, root.diskTotal)
    }

    StatBar {
      width: parent.width
      visible: root.tempC >= 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      label: "TEMPERATURA"
      value: Math.round(root.tempC) + " °C"
      fraction: root.tempC / 100
    }
  }
}
