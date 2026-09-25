import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../calendar"

// Calendar page: the stock clock's popup content, now one page of the
// dashboard. Owns the calendar state (today, view month, week start, memento
// mori) and composes the hero, the month grid, and the month stepping row.
//
// The grid is a read-out rather than a picker: today is the only marked day,
// and the only thing that moves is which month is on screen — chevrons, the
// scroll wheel, and the arrow keys all step it.
Item {
  id: root

  property bool panelActive: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var settings: ({})

  signal settingsRequested(var values)
  signal editingFinished()

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is a
  // read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)

  // While the birth-year editor is up the panel's key catcher must stand down
  // so Tab/Enter/Escape reach the fields.
  readonly property bool blocked: hero.editingLife

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  function toggleWeekStart() {
    var next = Model.toggledWeekStart(root.weekStart)
    root.settingsRequested({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function commitLife(bornText, expectancyText) {
    var born = Model.parseBirthYear(bornText, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyText)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      root.settingsRequested({ birthYear: born, lifeExpectancy: span })
  }

  function clearLife() {
    if (root.birthYear > 0) root.settingsRequested({ birthYear: 0 })
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    CalendarHero {
      id: hero
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      today: root.today
      viewingCurrentMonth: root.viewingCurrentMonth
      yearDone: root.yearDone
      yearDonePercent: root.yearDonePercent
      birthYear: root.birthYear
      lifeExpectancy: root.lifeExpectancy
      lifeDone: root.lifeDone
      lifeDonePercent: root.lifeDonePercent
      railWidth: grid.contentWidth
      onGoToToday: root.goToToday()
      onLifeCommitted: function(bornText, expectancyText) { root.commitLife(bornText, expectancyText) }
      onLifeCleared: root.clearLife()
      onEditingFinished: root.editingFinished()
    }

    MonthGrid {
      id: grid
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      viewYear: root.viewYear
      viewMonth: root.viewMonth
      weekStart: root.weekStart
      todayKey: root.todayKey
      onMoveMonth: function(delta) { root.moveMonth(delta) }
      onToggleWeekStart: root.toggleWeekStart()
    }

    // ---- Month stepping, spanning the grid it drives. The chevrons sit on
    //      the grid's outer bounds, the same edges the year rail above uses,
    //      so the row reads as the panel's other full-width rail instead of a
    //      cluster floating in space. The label is centered and fixed-width,
    //      so it holds still from "MAY" to "SEPTEMBER".
    Item {
      width: parent.width
      height: monthNav.height

      Item {
        id: monthNav
        anchors.horizontalCenter: parent.horizontalCenter
        width: grid.contentWidth
        height: monthLabel.implicitHeight + Style.space(10)

        Text {
          id: monthLabel
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          // Fixed width so the chevrons hold still between a "MAY 2026" and a
          // "SEPTEMBER 2026".
          width: Style.space(130)
          horizontalAlignment: Text.AlignHCenter
          text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.letterSpacing: 1
        }

        PanelActionButton {
          // Pulled out by the button's own padding so the glyph, not its hit
          // box, lines up with the "2026" on the year rail.
          anchors.left: parent.left
          anchors.leftMargin: -Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅁"
          tooltipText: "Previous month"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.moveMonth(-1)
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.rightMargin: -Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅂"
          tooltipText: "Next month"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.moveMonth(1)
        }
      }
    }
  }
}
