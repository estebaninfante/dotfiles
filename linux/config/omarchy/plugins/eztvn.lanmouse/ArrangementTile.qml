import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BorderSurface {
  id: tile

  property var display: null
  property var fit: null
  property string peerKey: ""
  property bool local: false
  property bool draggable: false
  property string basePosition: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  property bool dragStarted: false
  property real stagedX: 0
  property real stagedY: 0
  property string stagedZone: ""

  signal dropRequested(string zone)
  signal zonePreview(string key, string zone)

  readonly property real targetX: display ? display.x : 0
  readonly property real targetY: display ? display.y : 0
  readonly property bool dragging: dragHandler.active
  readonly property string activeZone: dragStarted ? stagedZone : ""

  x: dragHandler.active ? stagedX : targetX
  y: dragHandler.active ? stagedY : targetY
  width: display ? Math.max(1, display.width) : 1
  height: display ? Math.max(1, display.height) : 1
  visible: !!display
  z: dragging ? 3 : (local ? 1 : 2)
  clip: true
  radius: Style.cornerRadius
  color: local ? Style.normalFillFor(foreground) : Style.selectedFillFor(foreground, Color.accent)
  borderSpec: Border.controlSpec(
    dragging || !local ? "selected" : "normal", foreground, Color.accent)
  opacity: dragging ? 0.94 : 1

  Behavior on opacity {
    NumberAnimation { duration: 140 }
  }

  onActiveZoneChanged: zonePreview(peerKey, activeZone)

  Column {
    anchors.centerIn: parent
    width: Math.max(1, parent.width - Style.space(10))
    spacing: Style.space(1)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: tile.display ? tile.display.label : ""
      color: tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: tile.display ? tile.display.sublabel : ""
      color: Qt.darker(tile.foreground, 1.35)
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  HoverHandler {
    cursorShape: dragHandler.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
  }

  DragHandler {
    id: dragHandler
    enabled: tile.draggable
    target: null
    cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

    onActiveChanged: {
      if (active) {
        tile.dragStarted = true
        tile.stagedX = tile.targetX
        tile.stagedY = tile.targetY
        tile.stagedZone = Model.zoneForPoint(tile.fit, tile.targetX + tile.width / 2,
          tile.targetY + tile.height / 2, tile.basePosition)
      } else if (tile.dragStarted) {
        var zone = tile.stagedZone
        tile.dragStarted = false
        tile.dropRequested(zone)
      }
    }

    onActiveTranslationChanged: {
      if (!active || !tile.dragStarted) return
      tile.stagedX = tile.targetX + activeTranslation.x
      tile.stagedY = tile.targetY + activeTranslation.y
      tile.stagedZone = Model.zoneForPoint(tile.fit, tile.stagedX + tile.width / 2,
        tile.stagedY + tile.height / 2, tile.basePosition)
    }
  }
}
