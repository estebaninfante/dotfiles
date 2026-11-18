import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Core"
import "voice"

// Voice — hear exactly what the always-listening assistant sent to Whisper.
//
// The assistant (Proyectos/asistente, src/asistente/oido.py) saves every
// phrase it transcribes as a 16 kHz mono WAV plus a .txt with what Whisper
// understood, in ~/.local/state/asistente/audios. This page is the tape
// deck: pick a clip, hear the captured audio, read its transcript.
//
// Read-only: nothing here writes system state, so `activated()` is safe.
ColumnLayout {
  id: page

  property var sys: null
  property var app: null

  property var audios: []
  property bool loading: false
  property string loadError: ""
  property string playing: ""
  property int limit: 60

  readonly property string audioDir: (sys ? sys.home : Quickshell.env("HOME")) + "/.local/state/asistente/audios"
  readonly property color foreground: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent

  spacing: Style.spacing.huge

  Process {
    id: player
    running: false
    onExited: if (page.playing !== "") page.playing = ""
  }

  function stop() {
    player.running = false
    page.playing = ""
  }

  function play(path) {
    if (page.playing === path) {
      page.stop()
      return
    }
    player.running = false
    page.playing = path
    player.command = ["pw-play", path]
    player.running = true
  }

  // "20261118-135220-444062-sistema" -> "13:52 · 18/11"
  function stamp(base) {
    var m = String(base).match(/^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-(.*)$/)
    if (!m) return base
    return m[4] + ":" + m[5] + " · " + m[3] + "/" + m[2]
  }

  function load() {
    if (!sys) return
    page.loading = true
    page.loadError = ""
    // One process emits one TSV row per clip: path, duration, transcript.
    // Duration comes from the WAV size (mono s16 at 16 kHz = 32000 B/s,
    // 44-byte header), so no per-file ffprobe run is needed.
    var script = [
      'dir="$1"; [ -d "$dir" ] || exit 0',
      'ls -1t "$dir"/*.wav 2>/dev/null | head -n "$2" | while IFS= read -r f; do',
      '  b="${f%.wav}"',
      '  t=$(tr "\\n\\t" "  " < "$b.txt" 2>/dev/null)',
      '  s=$(stat -c%s "$f" 2>/dev/null) || s=0',
      '  d=$(awk -v s="$s" \'BEGIN{ if (s < 45) s = 44; printf "%.1f", (s - 44) / 32000 }\')',
      '  printf "%s\\t%s\\t%s\\n" "$f" "$d" "$t"',
      'done'
    ].join("\n")
    sys.sh(script, [page.audioDir, String(page.limit)], function(r) {
      page.loading = false
      if (r.code !== 0) {
        page.loadError = String(r.stderr || "").trim()
        page.audios = []
        return
      }
      var rows = []
      var lines = String(r.stdout || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (!line) continue
        var parts = line.split("\t")
        if (parts.length < 2) continue
        var file = parts[0]
        var base = file.substring(file.lastIndexOf("/") + 1, file.length - 4)
        rows.push({ file: file, base: base, seconds: parts[1], text: parts.length > 2 ? parts[2] : "" })
      }
      page.audios = rows
    })
  }

  function activated() {
    if (!sys) return
    page.load()
  }

  SettingsSection {
    title: "Captured audio"
    description: page.audios.length > 0
      ? "The last " + page.audios.length + " phrases the always-listening assistant sent to Whisper. Pick one to hear the audio it actually got, and read what it understood."
      : "Every phrase the always-listening assistant sends to Whisper is saved here, with its transcript. Nothing captured yet."

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md

      Text {
        Layout.fillWidth: true
        text: page.loading ? "Loading…"
          : page.loadError !== "" ? "Could not read the audio folder: " + page.loadError
          : page.playing !== "" ? "Playing now"
          : page.audios.length + " clips"
        textFormat: Text.PlainText
        color: page.loadError !== "" ? page.urgent : Util.alpha(page.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Button {
        text: "Refresh"
        iconText: String.fromCodePoint(0xF0450)
        onClicked: page.load()
      }

      Button {
        text: "Open folder"
        iconText: String.fromCodePoint(0xF024B)
        onClicked: if (page.sys) page.sys.detached(["xdg-open", page.audioDir])
      }
    }

    // A plain Column, not a ColumnLayout: the rows are created by a Repeater
    // and a ColumnLayout in this shell does not count them in its
    // implicitHeight (measured 0 with 60 delegates on Omarchy 4.0.4).
    Column {
      id: rowsColumn
      Layout.fillWidth: true
      spacing: Style.spacing.xxs

      Repeater {
        model: page.audios

        CaptureRow {
          width: rowsColumn.width
          stamp: page.stamp(modelData.base)
          seconds: modelData.seconds
          transcript: modelData.text
          playing: page.playing === modelData.file
          onClicked: page.play(modelData.file)
        }
      }
    }

    Text {
      text: page.audios.length === 0
        ? "Nothing captured yet. The always-listening assistant saves a clip each time it transcribes a phrase."
        : "Saved in ~/.local/state/asistente/audios. Use headphones: through the speakers the always-listening assistant hears the clip too. The dictation shortcut (hold the key) keeps its audio only while it transcribes, so it does not show up here."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: Util.alpha(page.foreground, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      Layout.fillWidth: true
    }
  }
}
