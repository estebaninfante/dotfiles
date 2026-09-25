import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../Pages.js" as Pages
import "../components"

// Media page: the active MPRIS player's art, metadata and transport. Talks to
// Quickshell's own Mpris service directly rather than the optional
// omarchy.media plugin, so it works whether or not that service is enabled.
Item {
  id: root

  property bool panelActive: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // Which player chip was picked. Empty means "follow whatever is playing".
  property string selectedKey: ""
  property int positionTick: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: pickPlayer()
  readonly property bool hasMedia: player !== null && (player.trackTitle || player.trackArtist)

  readonly property real position: {
    root.positionTick
    return root.player ? Number(root.player.position || 0) : 0
  }
  readonly property real length: root.player ? Number(root.player.length || 0) : 0
  readonly property real progress: (root.length > 0 && root.position > 0)
    ? Math.min(1, root.position / root.length) : 0

  readonly property string artUrl: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""

  function keyOf(p) {
    return p ? String(p.identity || p.desktopEntry || "player") : ""
  }

  function pickPlayer() {
    var list = root.players
    if (!list || list.length === 0) return null
    if (root.selectedKey !== "") {
      for (var i = 0; i < list.length; i++)
        if (keyOf(list[i]) === root.selectedKey) return list[i]
    }
    for (var j = 0; j < list.length; j++)
      if (list[j].isPlaying) return list[j]
    return list[0]
  }

  function togglePlay() {
    var p = root.player
    if (!p) return
    if (p.canTogglePlaying) p.togglePlaying()
    else if (p.isPlaying && p.canPause) p.pause()
    else if (!p.isPlaying && p.canPlay) p.play()
  }

  function next() {
    if (root.player && root.player.canGoNext) root.player.next()
  }

  function previous() {
    if (root.player && root.player.canGoPrevious) root.player.previous()
  }

  function refresh() {
    root.positionTick++
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.panelActive && root.player !== null && root.player.isPlaying
    onTriggered: root.positionTick++
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(14)

    // ---- Now playing -----------------------------------------------------
    Item {
      width: parent.width
      implicitHeight: Math.max(art.implicitHeight, meta.implicitHeight)

      BorderSurface {
        id: art
        width: Style.space(132)
        height: Style.space(132)
        anchors.left: parent.left
        anchors.top: parent.top
        radius: Style.cornerRadius
        color: Util.alpha(root.foreground, 0.06)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Text {
          anchors.centerIn: parent
          visible: artImage.status !== Image.Ready
          text: "󰎆"
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
        }

        Image {
          id: artImage
          anchors.fill: parent
          anchors.margins: Border.top(art.borderSpec)
          source: root.artUrl
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          sourceSize.width: 264
          sourceSize.height: 264
        }
      }

      Column {
        id: meta
        anchors.left: art.right
        anchors.right: parent.right
        anchors.leftMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.player ? String(root.player.identity || root.player.desktopEntry || "MPRIS") : ""
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.player && root.player.trackTitle ? root.player.trackTitle : (root.player ? "—" : "Sin reproducción")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: root.player && root.player.trackArtist ? root.player.trackArtist : ""
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: root.player && root.player.trackAlbum ? root.player.trackAlbum : ""
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }
    }

    // ---- Transport + progress -------------------------------------------
    Column {
      width: parent.width
      visible: root.player !== null
      spacing: Style.space(14)

      PanelSeparator { foreground: root.foreground }

      StatBar {
        width: parent.width
        foreground: root.foreground
        fontFamily: root.fontFamily
        label: "PROGRESO"
        value: Pages.formatClock(root.position) + (root.length > 0 ? " / " + Pages.formatClock(root.length) : "")
        fraction: root.progress
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(14)

        PanelActionButton {
          size: Style.space(42)
          fontSize: Style.font.display
          iconText: "󰒮"
          tooltipText: "Anterior"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          enabled: root.player !== null && root.player.canGoPrevious
          onClicked: root.previous()
        }

        PanelActionButton {
          size: Style.space(54)
          fontSize: Style.font.displayLarge
          iconText: root.player !== null && root.player.isPlaying ? "󰏤" : "󰐊"
          tooltipText: root.player !== null && root.player.isPlaying ? "Pausa" : "Reproducir"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          enabled: root.player !== null
          onClicked: root.togglePlay()
        }

        PanelActionButton {
          size: Style.space(42)
          fontSize: Style.font.display
          iconText: "󰒭"
          tooltipText: "Siguiente"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          enabled: root.player !== null && root.player.canGoNext
          onClicked: root.next()
        }
      }
    }

    // ---- Sources ---------------------------------------------------------
    Row {
      width: parent.width
      visible: root.players.length > 1
      spacing: Style.space(6)

      Repeater {
        model: root.players

        Button {
          required property var modelData
          readonly property string playerKey: root.keyOf(modelData)

          text: String(modelData.identity || modelData.desktopEntry || "Player")
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          selected: root.player !== null && root.keyOf(root.player) === playerKey
          onClicked: root.selectedKey = playerKey
        }
      }
    }
  }
}
