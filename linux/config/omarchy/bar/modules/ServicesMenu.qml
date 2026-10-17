import QtQuick
import qs.Commons
import qs.Ui

// Shell del menú de servicios. Mantiene una estética Omarchy (PanelHero,
// PanelSeparator, PanelSectionHeader, Button, Toggle) y enruta entre la lista
// de servicios y la vista de detalle de cada uno dentro de la misma ventana.
Item {
  id: menu

  property var module

  readonly property bool open: module ? module.menuOpen : false
  readonly property bool inDetail: module ? module.inDetail : false
  readonly property color fg: module ? module.fg : Color.foreground
  readonly property color dim: module ? module.dim : Color.muted
  readonly property color unknown: module ? module.unknownColor : Color.muted
  readonly property color globalColor: module ? module.globalColor : Color.muted
  readonly property string fontFamily: module ? module.fontFamily : Style.font.family

  implicitWidth: Style.space(400)
  implicitHeight: layout.implicitHeight
  anchors.fill: parent

  opacity: 0
  y: -Style.space(5)
  states: [
    State {
      name: "shown"
      when: menu.open
      PropertyChanges { target: menu; opacity: 1; y: 0 }
    }
  ]
  transitions: Transition {
    NumberAnimation { properties: "opacity,y"; duration: 230; easing.type: Easing.OutCubic }
  }

  Column {
    id: layout
    width: menu.width
    spacing: Style.space(11)

    Loader {
      id: pageLoader
      width: layout.width
      height: item ? item.implicitHeight : 0
      sourceComponent: menu.inDetail ? detailPage : listPage

      onLoaded: menu.wirePage(item)
    }
  }

  Component {
    id: listPage

    ServicesList {
      module: menu.module
      onOpenRequested: function(svc) { if (menu.module) menu.module.openDetail(svc) }
    }
  }

  Component {
    id: detailPage

    ServiceDetail {
      module: menu.module
    }
  }

  // --- Confirmación modal compartida -------------------------------------
  // La usan los submenús específicos (hypr-remote) para acciones destructivas.

  property string pendingAction: ""
  property string pendingSecondMessage: ""

  function wirePage(page) {
    if (!page) return
    if (page.confirmRequested) page.confirmRequested.connect(function(action, message, second) {
      menu.requestConfirm(action, message, second)
    })
  }

  function requestConfirm(action, message, second) {
    menu.pendingAction = String(action || "")
    menu.pendingSecondMessage = String(second || "")
    confirmDialog.message = String(message || "")
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }

  function resolveConfirm() {
    if (menu.pendingSecondMessage.length > 0) {
      confirmDialog.message = menu.pendingSecondMessage
      confirmDialog.selectedIndex = 1
      menu.pendingSecondMessage = ""
      return
    }

    var action = menu.pendingAction
    menu.pendingAction = ""
    confirmDialog.opened = false

    var page = pageLoader.item
    if (page && page.handleConfirmed) page.handleConfirmed(action)
  }

  ConfirmDialog {
    id: confirmDialog
    anchors.fill: parent
    background: Color.popups.background
    foreground: menu.fg
    scrim: Util.alpha(Color.popups.background, 0.72)
    fontFamily: menu.fontFamily

    onCanceled: {
      opened = false
      menu.pendingAction = ""
      menu.pendingSecondMessage = ""
    }
    onConfirmed: menu.resolveConfirm()
  }
}
