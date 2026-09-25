import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Pages.js" as Pages

// The clock's dashboard popup: a shared header over one of several pages
// (calendar, system, media, notifications, toggles) plus an index page.
//
// The panel owns page state, keyboard routing, and persistence; each page is
// a self-contained component loaded on demand under `pages/`. The calendar is
// the page the stock clock shipped, split into CalendarHero + MonthGrid so no
// component outgrows the file-size budget.
//
// BarWidget.qml owns the bar label and hands this panel the button to anchor
// against.
Panel {
  id: root
  moduleName: "eztvn.clock"
  ipcTarget: "eztvn.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- pages ------------------------------------------------------------
  property string activePage: Pages.DEFAULT_PAGE
  readonly property var pageMeta: Pages.pageById(activePage)
  readonly property int pageIndex: Pages.navIndex(activePage)
  readonly property int pageCount: Pages.navCount()

  function goToPage(id) {
    var next = Pages.normalize(id)
    if (next === activePage) return
    activePage = next
    scheduleStateSave()
  }

  function cyclePage(delta) {
    goToPage(Pages.stepPage(activePage, delta))
  }

  function openMenuPage() {
    goToPage("menu")
  }

  // ---- page persistence -------------------------------------------------
  //
  // A dedicated state file rather than a shell.json setting: pages change on
  // every arrow press and click, and rewriting the shell config that often
  // would hot-reload the whole bar. Writes are debounced, and the last page is
  // also flushed on close so it survives even a quick open/close.
  readonly property string statePath: Quickshell.env("HOME") + "/.config/omarchy/clock-dashboard.json"
  property bool stateLoaded: false

  function scheduleStateSave() {
    stateSaveTimer.restart()
  }

  function flushState() {
    if (!stateLoaded) return
    stateFile.setText(JSON.stringify({ version: 1, page: activePage }, null, 2) + "\n")
  }

  function loadState(raw) {
    if (stateLoaded) return
    var page = Pages.DEFAULT_PAGE
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed.page === "string") page = Pages.normalize(parsed.page)
    } catch (e) {
      page = Pages.DEFAULT_PAGE
    }
    activePage = page
    stateLoaded = true
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  Timer {
    id: stateSaveTimer
    interval: 400
    repeat: false
    onTriggered: root.flushState()
  }

  // ---- shell.json settings ----------------------------------------------
  //
  // Rare, explicit user choices (week start, memento mori) still live in the
  // widget's shell.json entry, so they survive updates and stay visible in the
  // layout — the same contract the stock clock had for these keys.
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- lifecycle --------------------------------------------------------
  function open() {
    if (!stateLoaded) stateFile.reload()
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
    flushState()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (pageLoader.item && typeof pageLoader.item.refresh === "function")
      pageLoader.item.refresh()
  }

  function toggleWeekStart() {
    if (activePage === "calendar" && pageLoader.item && pageLoader.item.toggleWeekStart)
      pageLoader.item.toggleWeekStart()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- page context -----------------------------------------------------
  //
  // Pages are plain components with no knowledge of the panel; the panel
  // pushes the few things they need (active flag, colours, settings) and
  // wires their navigation signals. Re-run whenever any of it changes.
  function syncPageContext() {
    var item = pageLoader.item
    if (!item) return
    item.panelActive = root.opened
    if ("foreground" in item) item.foreground = root.contentForeground
    if ("fontFamily" in item) item.fontFamily = root.contentFontFamily
    if ("settings" in item) item.settings = root.settings
    if ("activePage" in item) item.activePage = root.activePage
  }

  function attachPage() {
    var item = pageLoader.item
    if (!item) return
    if (item.pageRequested) item.pageRequested.connect(function(id) { root.goToPage(id) })
    if (item.settingsRequested) item.settingsRequested.connect(function(values) { root.persistSettings(values) })
    // An inline editor (the calendar's birth-year fields) takes focus away from
    // the key catcher; hand it back when the editor closes.
    if (item.editingFinished) item.editingFinished.connect(function() { keyCatcher.forceActiveFocus() })
    syncPageContext()
  }

  onOpenedChanged: syncPageContext()
  onActivePageChanged: syncPageContext()
  onSettingsChanged: syncPageContext()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(800))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // A page with an inline editor (calendar) stands the catcher down so
      // Tab/Enter/Escape reach its TextFields.
      blocked: pageLoader.item ? (pageLoader.item.blocked === true) : false
      onMoveRequested: function(dx, dy) {
        if (root.activePage === "calendar" && pageLoader.item) {
          if (dx !== 0) pageLoader.item.moveMonth(dx)
          if (dy !== 0) pageLoader.item.moveYear(dy)
        } else if (dx !== 0) {
          root.cyclePage(dx)
        }
      }
      onActivateRequested: {
        if (root.activePage === "calendar" && pageLoader.item && pageLoader.item.goToToday)
          pageLoader.item.goToToday()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.cyclePage(-1)
        else if (t === "]") root.cyclePage(1)
        else if (/^[1-6]$/.test(t)) {
          var pages = Pages.navPages()
          var index = parseInt(t, 10) - 1
          if (index >= 0 && index < pages.length) root.goToPage(pages[index].id)
        } else if (root.activePage === "calendar" && pageLoader.item) {
          if (t === "{") pageLoader.item.moveYear(-1)
          else if (t === "}") pageLoader.item.moveYear(1)
          else if (t === "t" || t === "T") pageLoader.item.goToToday()
          else if (t === "w" || t === "W") pageLoader.item.toggleWeekStart()
        }
      }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PageHeader {
          width: parent.width
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          title: root.pageMeta ? root.pageMeta.title : ""
          pageIndex: root.pageIndex
          pageCount: root.pageCount
          onPrevRequested: root.cyclePage(-1)
          onNextRequested: root.cyclePage(1)
          onMenuRequested: root.openMenuPage()
        }

        Loader {
          id: pageLoader
          width: parent.width
          height: item ? item.implicitHeight : 0
          source: Qt.resolvedUrl("pages/" + Pages.file(root.activePage))
          onLoaded: root.attachPage()
        }
      }
    }
  }
}
