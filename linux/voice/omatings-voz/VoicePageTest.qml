import QtQuick
import Quickshell

// Headless check for pages/VoicePage.qml: the page must read the real captured
// clips. The generic harness reports the pre-async height, so this waits for
// the listing process to finish.
//
//   tools/check.sh tools/tests/VoicePageTest.qml
Item {
  id: test
  width: 800

  property var sys: null
  property var app: null
  property var page: null

  function activated() {
    if (!sys) return
    var c = Qt.createComponent(Qt.resolvedUrl("../../pages/VoicePage.qml"))
    if (c.status !== Component.Ready) {
      console.log("OMATINGS_CHECK_FAIL " + c.errorString())
      return
    }
    page = c.createObject(test, { width: 760 })
    if (!page) {
      console.log("OMATINGS_CHECK_FAIL could not instantiate VoicePage")
      return
    }
    page.sys = sys
    page.activated()
    checkTimer.start()
  }

  Timer {
    id: checkTimer
    interval: 1800
    onTriggered: {
      var rows = test.page ? test.page.audios.length : -1
      var stamped = test.page && rows > 0 ? test.page.stamp(test.page.audios[0].base) : ""
      console.log("rows=" + rows + " first=" + stamped)
      if (rows < 1) {
        console.log("OMATINGS_CHECK_FAIL no clips read from ~/.local/state/asistente/audios")
        Qt.exit(1)
        return
      }
      if (stamped.indexOf(":") === -1) {
        console.log("OMATINGS_CHECK_FAIL timestamp not formatted: " + stamped)
        Qt.exit(1)
        return
      }
      console.log("OMATINGS_CHECK_DONE")
      Qt.exit(0)
    }
  }
}
