---
description: Lint quickshell/omarchy QML for UX/layout issues (margins, hover, animations)
agent: build
---

Run the local QML UX linter and act on the results.

1. Run: `omarchy-qml-lint --all`
2. For every `ERROR` (`bar-padding`, `bar-fill`), fix the file:
   - `bar-padding`: add `readonly property real hPad: Style.spaceReal(8.75)` and include
     `hPad * 2` in `implicitWidth` (bar widgets own their horizontal padding).
   - `bar-fill`: keep content height <= `barSize - 7`; widget `implicitHeight` stays `root.barSize`.
3. Do not chase `INFO`/`WARN` unless the user asked.
4. If a bar widget was changed, verify visually: `omarchy restart shell`, then `grim` +
   screenshot (hot reload does not repaint plugin visuals).

Optional scope: $ARGUMENTS
