import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The month grid: week numbers down a gutter on the left, then seven day
// columns. Always six rows, so the panel is exactly as tall in February as it
// is in August. A read-out, not a picker — today is the only marked day.
//
// The week-number heading doubles as the week-start toggle, which is why it
// carries a tooltip naming the day it will switch to.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int viewYear: 1970
  property int viewMonth: 0
  property int weekStart: 1
  property string todayKey: ""

  signal moveMonth(int delta)
  signal toggleWeekStart()

  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention, and it stays overridable in shell.json.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property int toggledStart: Model.toggledWeekStart(weekStart)
  readonly property string nextWeekStartLabel: labelLocale.dayName(toggledStart, Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  // Width of the grid itself, so a wrapping header can line up with it.
  readonly property real contentWidth: gridColumn.width

  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  implicitHeight: gridColumn.y + gridColumn.height

  WheelHandler {
    onWheel: function(event) {
      // Horizontal wheels and touchpad side-scrolls report y === 0; without
      // this they would every one read as "next month".
      if (event.angleDelta.y === 0) return
      root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
    }
  }

  Column {
    id: gridColumn
    // The hero's meter above is a solid rule; the grid needs room to read as
    // its own block rather than hanging off it.
    y: Style.space(14)
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(3)

    Row {
      id: headerRow
      spacing: root.cellSpacing

      Rectangle {
        width: root.weekColumnWidth
        height: Style.space(16)
        radius: Style.cornerRadius
        color: weekStartMouse.containsMouse
          ? Style.hoverFillFor(root.foreground, Color.accent)
          : "transparent"

        Text {
          anchors.centerIn: parent
          text: "W"
          color: weekStartMouse.containsMouse
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : Qt.darker(root.foreground, 1.9)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
          font.bold: true
        }

        MouseArea {
          id: weekStartMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleWeekStart()
        }

        PanelToolTip {
          visible: weekStartMouse.containsMouse
          text: "Start weeks on " + root.nextWeekStartLabel
          fontFamily: root.fontFamily
        }
      }

      Item {
        width: root.gutterWidth
        height: Style.space(16)
      }

      Repeater {
        model: root.weekdays

        Text {
          textFormat: Text.PlainText
          required property var modelData
          width: root.cellWidth
          height: Style.space(16)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: root.weekdayLabel(modelData)
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
          font.bold: true
        }
      }
    }

    Repeater {
      model: root.weeks

      Row {
        required property var modelData
        spacing: root.cellSpacing

        Text {
          textFormat: Text.PlainText
          width: root.weekColumnWidth
          height: root.cellHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData.week
          color: Qt.darker(root.foreground, 1.9)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item {
          width: root.gutterWidth
          height: root.cellHeight
        }

        Repeater {
          model: modelData.days

          Rectangle {
            required property var modelData

            width: root.cellWidth
            height: root.cellHeight
            radius: Style.cornerRadius
            // Today is outlined, not filled: a lit-up block shouts over a
            // grid this quiet.
            color: "transparent"
            border.width: modelData.today ? Style.spacing.hairline : 0
            border.color: Style.normalBorderFor(root.foreground, Color.accent)

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: modelData.day
              color: modelData.inMonth
                ? (modelData.weekend ? Qt.darker(root.foreground, 1.45) : root.foreground)
                : Qt.darker(root.foreground, 2.2)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: modelData.today
            }
          }
        }
      }
    }
  }

  // Hairline down the week-number gutter, drawn only beside the day rows so it
  // does not cut through the header band.
  Rectangle {
    x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
    y: gridColumn.y + headerRow.height + gridColumn.spacing
    width: Style.spacing.hairline
    height: gridColumn.height - headerRow.height - gridColumn.spacing
    color: root.foreground
    opacity: 0.1
  }
}
