import { Plugin } from "@opencode/plugin"
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"

const HOME = homedir()
const LINTER = `${HOME}/.local/bin/omarchy-qml-lint`
const WATCHED_PREFIXES = [`${HOME}/.config/omarchy/`, `${HOME}/.config/quickshell/`]
const EDIT_TOOLS = new Set(["edit", "write", "patch", "multiedit", "apply_patch"])

function toolPath(input) {
  const value = input?.filePath ?? input?.path ?? input?.filename
  return typeof value === "string" ? value : undefined
}

function appendContent(result, text) {
  if (typeof result.content === "string") result.content = `${result.content}${text}`
  else if (Array.isArray(result.content)) result.content = [...result.content, { type: "text", text }]
  else result.content = text
}

export default Plugin.define({
  id: "eztvn.qml-ux-lint",
  async setup(ctx) {
    if (!existsSync(LINTER)) return
    await ctx.tool.hook("execute.after", (event) => {
      try {
        if (event.status !== "completed") return
        if (!EDIT_TOOLS.has(event.tool)) return
        const file = toolPath(event.input)
        if (!file || !file.endsWith(".qml")) return
        if (!WATCHED_PREFIXES.some((prefix) => file.startsWith(prefix))) return
        const proc = spawnSync("python3", [LINTER, "--quiet", file], { encoding: "utf8" })
        const out = (proc.stdout ?? "").trim()
        if (!out) return
        appendContent(event.result, `\n\n[ux-lint] quickshell/omarchy QML check flagged this edit:\n${out}`)
        event.result.metadata = { ...(event.result.metadata ?? {}), uxLint: true }
      } catch {}
    })
  },
})
