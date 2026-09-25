import { existsSync } from "fs"

const HOME = process.env.HOME || ""
const VERIFY = `${HOME}/.config/opencode/skills/verification/scripts/verify.py`
const QML_PREFIXES = [`${HOME}/.config/omarchy/`, `${HOME}/.config/quickshell/`]
const EDIT_TOOLS = new Set(["edit", "write", "patch", "multiedit", "apply_patch"])

function editedPath(input) {
  const a = input?.args || {}
  return a.filePath || a.path || a.filename || ""
}

function handledByQmlLint(file) {
  return file.endsWith(".qml") && QML_PREFIXES.some((prefix) => file.startsWith(prefix))
}

export const VerifyHook = async () => {
  return {
    "tool.execute.after": async (input, output) => {
      try {
        if (!EDIT_TOOLS.has(input?.tool)) return
        const file = editedPath(input)
        if (!file || !existsSync(file)) return
        if (handledByQmlLint(file)) return
        if (!existsSync(VERIFY)) return

        const res = Bun.spawnSync(["python3", VERIFY, "auto", "--quiet", file])
        const text = (res.stdout ? res.stdout.toString() : "").trim()
        if (!text) return

        output.output = `${output.output || ""}\n\n[verify] ${text}`
        output.metadata = { ...(output.metadata || {}), verify: true }
      } catch {
      }
    },
  }
}

export default VerifyHook
