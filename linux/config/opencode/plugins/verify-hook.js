import { Plugin } from "@opencode/plugin"
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"

const HOME = homedir()
const VERIFY = `${HOME}/.config/opencode/skills/verification/scripts/verify.py`
const EDIT_TOOLS = new Set(["edit", "write", "patch", "multiedit", "apply_patch"])
const QML_PREFIXES = [`${HOME}/.config/omarchy/`, `${HOME}/.config/quickshell/`]

function toolPath(input) {
  if (!input || typeof input !== "object") return undefined
  const value = input.filePath ?? input.path ?? input.filename
  return typeof value === "string" ? value : undefined
}

function appendContent(result, text) {
  if (typeof result.content === "string") result.content = `${result.content}${text}`
  else if (Array.isArray(result.content)) result.content = [...result.content, { type: "text", text }]
  else result.content = text
}

export default Plugin.define({
  id: "eztvn.verify-hook",
  async setup(ctx) {
    if (!existsSync(VERIFY)) return
    await ctx.tool.hook("execute.after", (event) => {
      try {
        if (event.status !== "completed") return
        if (!EDIT_TOOLS.has(event.tool)) return
        const file = toolPath(event.input)
        if (!file) return
        if (file.endsWith(".qml") && QML_PREFIXES.some((prefix) => file.startsWith(prefix))) return
        const proc = spawnSync("python3", [VERIFY, "--quiet", "auto", file], { encoding: "utf8" })
        const out = (proc.stdout ?? "").trim()
        if (!out) return
        appendContent(event.result, `\n\n[verify] ${out}`)
        event.result.metadata = { ...(event.result.metadata ?? {}), verify: true }
      } catch {}
    })
  },
})
