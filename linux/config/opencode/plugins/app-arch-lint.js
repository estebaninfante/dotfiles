import { Plugin } from "@opencode/plugin"
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import { extname } from "node:path"
import { homedir } from "node:os"

const HOME = homedir()
const LINTER = `${HOME}/.local/bin/app-arch-lint`
const EDIT_TOOLS = new Set(["edit", "write", "patch", "multiedit", "apply_patch"])
const EXTENSIONS = new Set([
  ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".css", ".html", ".py", ".rs", ".go",
  ".vue", ".svelte",
])
const IGNORED = [
  "/node_modules/", "/.git/", "/dist/", "/.next/", "/build/", "/venv/", "/.venv/",
  "/__pycache__/", "/coverage/",
]

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
  id: "eztvn.app-arch-lint",
  async setup(ctx) {
    if (!existsSync(LINTER)) return
    await ctx.tool.hook("execute.after", (event) => {
      try {
        if (event.status !== "completed") return
        if (!EDIT_TOOLS.has(event.tool)) return
        const file = toolPath(event.input)
        if (!file) return
        if (!EXTENSIONS.has(extname(file))) return
        if (IGNORED.some((segment) => file.includes(segment))) return
        const proc = spawnSync(LINTER, ["--quiet", file], { encoding: "utf8" })
        const out = (proc.stdout ?? "").trim()
        if (!out) return
        appendContent(event.result, `\n\n[app-arch] App Agent-Friendly v1 violation in this edit:\n${out}`)
        event.result.metadata = { ...(event.result.metadata ?? {}), appArchLint: true }
      } catch {}
    })
  },
})
