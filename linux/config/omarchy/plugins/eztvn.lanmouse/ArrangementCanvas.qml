import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BorderSurface {
  id: canvas

  property var localDisplay: null
  property var peers: []
  property bool interactive: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  property string dragKey: ""
  property string dragZone: ""

  signal dropRequested(string zone)

  clip: true
  radius: Style.cornerRadius
  color: Style.normalFillFor(foreground)
  borderSpec: Border.controlSpec("normal", foreground, Color.accent)
  implicitHeight: Style.space(210)

  readonly property var fit: Model.fitLayout(localDisplay, peers, width, height,
    Style.space(14), 0.92, 200)

  function noteZone(key, zone) {
    if (zone === "") {
      if (dragKey === key) {
        dragKey = ""
        dragZone = ""
      }
      return
    }
    dragKey = key
    dragZone = zone
  }

  ArrangementTile {
    local: true
    display: canvas.fit ? canvas.fit.local : null
    fit: canvas.fit
    peerKey: canvas.fit ? canvas.fit.local.key : ""
    draggable: false
    foreground: canvas.foreground
    fontFamily: canvas.fontFamily
    onZonePreview: function(key, zone) { canvas.noteZone(key, zone) }
  }

  Repeater {
    model: canvas.fit ? canvas.fit.peers : []

    ArrangementTile {
      required property var modelData

      display: modelData
      fit: canvas.fit
      peerKey: modelData.key
      draggable: canvas.interactive
      basePosition: modelData.position
      foreground: canvas.foreground
      fontFamily: canvas.fontFamily
      onDropRequested: function(zone) { canvas.dropRequested(zone) }
      onZonePreview: function(key, zone) { canvas.noteZone(key, zone) }
    }
  }

  Rectangle {
    id: zoneHint
    readonly property var slot: canvas.dragZone !== ""
      ? Model.peerCandidateRect(canvas.fit, canvas.dragKey, canvas.dragZone)
      : null
    x: slot ? slot.x : 0
    y: slot ? slot.y : 0
    width: slot ? slot.width : 0
    height: slot ? slot.height : 0
    z: 1
    visible: opacity > 0.05
    opacity: slot ? 1 : 0
    radius: Style.cornerRadius
    color: Style.selectedAccentFill
    border.width: Math.max(1, Style.space(2))
    border.color: Color.accent

    Behavior on opacity {
      NumberAnimation { duration: 150 }
    }
  }
}
