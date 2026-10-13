import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var monitor: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool cursorActive: false

  readonly property var mon: monitor || ({})
  readonly property bool batteryPresent: root.mon.batteryPresent === true

  signal cursorActivated()

  width: parent.width
  spacing: Style.space(14)

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSeparator { foreground: root.foreground }

    PanelSectionHeader {
      text: "POWER PROFILE"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      width: parent.width
      visible: (root.mon.profiles || []).length === 0
      textFormat: Text.PlainText
      text: "—"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Row {
      id: profileRow
      width: parent.width
      spacing: Style.space(6)

      readonly property real cellWidth: (root.mon.profiles || []).length > 0
        ? (width - spacing * ((root.mon.profiles || []).length - 1)) / (root.mon.profiles || []).length
        : 0

      Repeater {
        model: root.mon.profiles || []

        Button {
          required property var modelData
          required property int index
          width: profileRow.cellWidth
          iconText: Model.profileIcon(String(modelData))
          iconSize: Style.font.title
          text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          active: root.mon.activeProfile === modelData
          hasCursor: root.cursorActive && Number(root.mon.profileIndex || 0) === index
          onClicked: if (root.monitor) root.monitor.setProfile(modelData)
          onHovered: function(h) {
            if (h) {
              root.cursorActivated()
              if (root.monitor) root.monitor.setProfileIndex(index)
            }
          }
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSeparator { foreground: root.foreground }

    PanelSectionHeader {
      text: "PERFORMANCE"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Row {
      width: parent.width
      spacing: Style.space(20)

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.spacing.labelGap
        InfoPair { label: "CPU"; value: String(root.mon.cpuText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
        InfoPair { label: "Memory"; value: String(root.mon.memoryText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
        InfoPair { label: "Uptime"; value: String(root.mon.uptimeText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
      }

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.spacing.labelGap
        InfoPair { label: "CPU temp"; value: String(root.mon.cpuTempText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
        InfoPair { label: "GPU temp"; value: String(root.mon.gpuTempText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
      }
    }
  }

  Column {
    visible: root.batteryPresent
    width: parent.width
    spacing: Style.space(10)

    PanelSeparator { foreground: root.foreground }

    PanelSectionHeader {
      text: "BATTERY"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Row {
      width: parent.width
      spacing: Style.space(20)

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.spacing.labelGap
        InfoPair { label: "State"; value: String(root.mon.stateText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
        InfoPair {
          label: root.mon.discharging === true ? "Time left" : "Time to full"
          value: String(root.mon.timeText || "—")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
        InfoPair {
          label: "Charge limit"
          value: String(root.mon.thresholdText || "—")
          foreground: root.foreground
          fontFamily: root.fontFamily
          visible: root.mon.thresholdText !== "—"
        }
      }

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.spacing.labelGap
        InfoPair { label: "Capacity"; value: String(root.mon.sizeText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
        InfoPair { label: "Charge cycles"; value: String(root.mon.cyclesText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
        InfoPair { label: "Health"; value: String(root.mon.healthText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
      }
    }
  }

  Column {
    visible: root.batteryPresent
    width: parent.width
    spacing: Style.space(10)

    PanelSeparator { foreground: root.foreground }

    PanelSectionHeader {
      text: "CHARGE"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Button {
      width: parent.width
      iconText: root.mon.fastChargeState === "fast" ? "󰂄" : "󰢜"
      iconSize: Style.font.title
      text: root.mon.fastChargeState === "" ? "Fast charge —"
        : (root.mon.fastChargeState === "fast" ? "Fast charge ON" : "Fast charge OFF")
      fontSize: Style.font.bodySmall
      foreground: root.foreground
      fontFamily: root.fontFamily
      horizontalPadding: Style.spacing.controlPaddingX
      verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
      bordered: true
      active: root.mon.fastChargeState === "standard"
      enabled: root.mon.fastChargeState !== ""
      onClicked: if (root.monitor) root.monitor.toggleFastCharge()
    }
  }
}
