// qml-ux-lint — opencode plugin.
//
// Runs the local quickshell/omarchy QML UX linter after any edit to a QML file
// living under ~/.config/omarchy/ or ~/.config/quickshell/, and appends the
// findings to the tool result so the model (and the user) see them immediately.
//
// This exists because a bar widget regression (content filling the full bar,
// no horizontal padding) shipped silently. The rule is now mechanical.
//
// Linter: ~/.local/bin/omarchy-qml-lint (see that script for the rule set).
// Fail-soft: any error here must never break the host session.

import { existsSync } from "fs"

const HOME = process.env.HOME || ""
const LINTER = `${HOME}/.local/bin/omarchy-qml-lint`
const WATCHED_PREFIXES = [`${HOME}/.config/omarchy/`, `${HOME}/.config/quickshell/`]
const EDIT_TOOLS = new Set(["edit", "write", "patch", "multiedit", "apply_patch"])

function editedPath(input) {
  const a = input?.args || {}
  return a.filePath || a.path || a.filename || ""
}

function isWatchedQml(p) {
  return typeof p === "string" && p.endsWith(".qml") && WATCHED_PREFIXES.some((pre) => p.startsWith(pre))
}

export const QmlUxLint = async () => {
  return {
    "tool.execute.after": async (input, output) => {
      try {
        if (!EDIT_TOOLS.has(input?.tool)) return
        const file = editedPath(input)
        if (!isWatchedQml(file)) return
        if (!existsSync(LINTER)) return

        const res = Bun.spawnSync(["python3", LINTER, "--quiet", file])
        const text = (res.stdout ? res.stdout.toString() : "").trim()
        if (!text) return

        const header = "[ux-lint] quickshell/omarchy QML check flagged this edit:"
        output.output = `${output.output || ""}\n\n${header}\n${text}`
        output.metadata = { ...(output.metadata || {}), uxLint: true }
      } catch {
        // fail-soft: linting must never break a tool call
      }
    },
  }
}

export default QmlUxLint
