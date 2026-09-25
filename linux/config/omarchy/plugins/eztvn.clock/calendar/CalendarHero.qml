import QtQuick
import qs.Commons
import qs.Ui

// The top of the calendar page: today's date, the year-progress rail, and the
// optional memento-mori rail. Kept apart from CalendarPage so the page file
// stays a state machine and this stays a drawing.
//
// Double-tapping the year rail reveals a small birth-year / life-expectancy
// editor; double-tapping the life rail puts it away again. The editor owns its
// transient state and hands raw text to the page, which parses and persists it.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property date today: new Date()
  property bool viewingCurrentMonth: true
  property real yearDone: 0
  property int yearDonePercent: 0
  property int birthYear: 0
  property int lifeExpectancy: 90
  property real lifeDone: 0
  property int lifeDonePercent: 0
  // Width the rails align to — the month grid's own width, pushed in by the
  // page so the hero and the grid read as one column.
  property real railWidth: Style.space(420)

  signal goToToday()
  signal lifeCommitted(string bornText, string expectancyText)
  signal lifeCleared()
  signal editingFinished()

  property bool editingLife: false

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy || "")
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    root.editingFinished()
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.lifeCommitted(bornField.text, expectancyField.text)
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    // ---- Hero: today, centered. Once the view has stepped back it is also
    //      the way home — clicking the date you are looking for beats hunting
    //      for a reset button.
    Item {
      id: heroItem
      width: parent.width
      height: heroRow.height

      Row {
        id: heroRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(22)

        Text {
          // Baseline-aligned, not center-aligned: "July 26" carries a
          // descender, so centering the two boxes leaves the icon sitting
          // visibly low against the digits.
          anchors.baseline: heroDate.baseline
          text: "󰃭"
          color: heroMouse.containsMouse
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : root.foreground
          font.family: root.fontFamily
          // Decorative, and deliberately outside the Style.font.* scale.
          font.pixelSize: 48
        }

        Text {
          id: heroDate
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: Qt.formatDate(root.today, "MMMM d")
          color: heroMouse.containsMouse
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : root.foreground
          font.family: root.fontFamily
          font.pixelSize: 52
          font.bold: true
        }
      }

      MouseArea {
        id: heroMouse
        x: heroRow.x
        y: heroRow.y
        width: heroRow.width
        height: heroRow.height
        enabled: !root.viewingCurrentMonth
        hoverEnabled: enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.goToToday()

        PanelToolTip {
          visible: heroMouse.containsMouse
          text: "Back to today"
          fontFamily: root.fontFamily
        }
      }
    }

    // ---- Year progress, doubling as the rule under the hero: a plain
    //      hairline said nothing, and whole days done over days in the year
    //      says the same thing louder.
    Item {
      id: yearItem
      width: parent.width
      height: yearBlock.y + yearBlock.height

      Item {
        id: yearBlock
        y: Style.space(6)
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.railWidth
        height: Math.max(yearLabel.implicitHeight, Style.space(10))

        TapHandler {
          enabled: !root.editingLife
          onDoubleTapped: root.startEditingLife()
        }

        Row {
          visible: root.editingLife
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "BORN"
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          TextField {
            id: bornField
            width: Style.space(70)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "year"
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDigitsOnly
            Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.space(6)
            text: "LIVE TO"
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          TextField {
            id: expectancyField
            width: Style.space(60)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "90"
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDigitsOnly
            Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
          }
        }

        Text {
          id: yearLabel
          textFormat: Text.PlainText
          visible: !root.editingLife
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.today.getFullYear()
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Text {
          id: yearPercent
          textFormat: Text.PlainText
          visible: !root.editingLife
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.yearDonePercent + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ProgressRail {
          visible: !root.editingLife
          anchors.left: yearLabel.right
          anchors.right: yearPercent.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.foreground
          progress: root.yearDone
        }
      }
    }

    // ---- Memento mori. Only here once someone has gone looking and given a
    //      birth year; the same rail as the year above it, measured against a
    //      nominal lifetime.
    Item {
      id: lifeItem
      visible: root.birthYear > 0
      width: parent.width
      height: visible ? lifeBlock.height : 0

      Item {
        id: lifeBlock
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.railWidth
        height: Math.max(lifeLabel.implicitHeight, Style.space(10))

        Text {
          id: lifeLabel
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "LIFE"
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Text {
          id: lifePercent
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.lifeDonePercent + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ProgressRail {
          anchors.left: lifeLabel.right
          anchors.right: lifePercent.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.foreground
          progress: root.lifeDone
        }

        TapHandler {
          onDoubleTapped: root.lifeCleared()
        }

        MouseArea {
          id: lifeMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton

          PanelToolTip {
            visible: lifeMouse.containsMouse
            text: "Memento Mori"
            fontFamily: root.fontFamily
          }
        }
      }
    }
  }
}
