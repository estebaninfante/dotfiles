import { existsSync } from "fs"

const HOME = process.env.HOME || ""
const LINTER = `${HOME}/.local/bin/app-arch-lint`
const EDIT_TOOLS = new Set(["edit", "write", "patch", "multiedit", "apply_patch"])
const EXTENSIONS = new Set([
  ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".css", ".html",
  ".py", ".rs", ".go", ".vue", ".svelte",
])
const IGNORED = [
  "/node_modules/", "/.git/", "/dist/", "/.next/", "/build/",
  "/venv/", "/.venv/", "/__pycache__/", "/coverage/",
]

function editedPath(input) {
  const a = input?.args || {}
  return a.filePath || a.path || a.filename || ""
}

function watched(file) {
  if (typeof file !== "string" || !file) return false
  const dot = file.lastIndexOf(".")
  if (dot < 0) return false
  if (!EXTENSIONS.has(file.slice(dot).toLowerCase())) return false
  return !IGNORED.some((segment) => file.includes(segment))
}

export const AppArchLint = async () => {
  return {
    "tool.execute.after": async (input, output) => {
      try {
        if (!EDIT_TOOLS.has(input?.tool)) return
        const file = editedPath(input)
        if (!watched(file)) return
        if (!existsSync(LINTER)) return

        const res = Bun.spawnSync([LINTER, "--quiet", file])
        const text = (res.stdout ? res.stdout.toString() : "").trim()
        if (!text) return

        const header = "[app-arch] App Agent-Friendly v1 violation in this edit:"
        output.output = `${output.output || ""}\n\n${header}\n${text}`
        output.metadata = { ...(output.metadata || {}), appArchLint: true }
      } catch {
      }
    },
  }
}

export default AppArchLint
