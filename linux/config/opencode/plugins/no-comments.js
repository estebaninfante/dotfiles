import { basename, extname } from "path"

const EDIT_TOOLS = new Set(["edit", "write", "patch", "multiedit", "apply_patch"])
const CONTENT_KEYS = ["newString", "new_string", "content", "text"]
const PATCH_KEYS = ["patch", "diff", "input"]
const ALLOW = process.env.OPENCODE_ALLOW_COMMENTS === "1"

const NONCODE = new Set([
  "md", "markdown", "txt", "rst", "json", "lock", "csv", "log", "tsv", "ipynb", "svgz",
])

const SLASH = new Set([
  "qml", "js", "mjs", "cjs", "ts", "tsx", "mts", "cts", "jsx", "c", "h", "cc", "cpp",
  "cxx", "hpp", "hh", "cs", "java", "kt", "kts", "scala", "go", "rs", "swift", "dart",
  "php", "groovy", "gradle", "proto", "zig", "v", "sol", "mm", "m", "glsl", "vert",
  "frag", "vs", "fs", "hlsl", "metal", "wgsl", "scss", "less", "sass", "styl",
  "jsonc", "json5",
])

const HASH = new Set([
  "py", "pyi", "sh", "bash", "zsh", "fish", "ksh", "yaml", "yml", "toml", "ini", "cfg",
  "conf", "properties", "env", "tf", "hcl", "nix", "r", "rb", "pl", "pm", "tcl", "awk",
  "nim", "jl", "ex", "exs", "cr", "cmake", "service", "desktop", "spec", "dockerignore",
  "gitignore",
])

const DASH = new Set(["sql", "lua", "hs", "elm", "ada", "vhdl"])

const SPECIAL_BASENAME = new Map([
  ["dockerfile", "hash"],
  ["makefile", "hash"],
  ["cmakelists.txt", "hash"],
])

const SLASH_ALLOW = [
  "//go:", "// +build", "//@ts-", "// @ts-", "//eslint", "// eslint", "// biome-",
  "// prettier-", "//#region", "//#endregion", "/// <reference", "// swiftlint:",
  "// nolint", "// run:", "//coverage:", "/*!", "// @no",
]

const HASH_ALLOW = [
  "#!", "#include", "#define", "#pragma", "#if", "#ifdef", "#ifndef", "#elif", "#else",
  "#endif", "#undef", "#error", "#warning", "#line", "#region", "#endregion", "# type",
  "#type:", "# noqa", "#noqa", "# fmt", "#fmt:", "# pyright", "#pyright:", "# mypy",
  "#mypy:", "#-*-", "#coding", "# vim:", "#vim:", "# ex:", "#ex:", "# shellcheck",
  "#shellcheck", "#sbatch", "#pbs", "#bsub", "#syntax=", "#check=", "#escape=",
  "# source", "#source",
]

function familyFor(file) {
  const base = basename(file).toLowerCase()
  const special = SPECIAL_BASENAME.get(base)
  if (special) return special
  const ext = extname(base).replace(/^\./, "")
  if (!ext || NONCODE.has(ext)) return null
  if (SLASH.has(ext)) return "slash"
  if (HASH.has(ext)) return "hash"
  if (DASH.has(ext)) return "dash"
  return null
}

function startsWithAny(text, list) {
  const lower = text.toLowerCase()
  return list.some((p) => lower.startsWith(p))
}

function indexOutsideString(line, marker) {
  let quote = null
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (quote) {
      if (ch === "\\") {
        i++
        continue
      }
      if (ch === quote) quote = null
      continue
    }
    if (ch === '"' || ch === "'" || ch === "`") {
      quote = ch
      continue
    }
    if (line.startsWith(marker, i)) return i
  }
  return -1
}

function isCommentLine(line, family) {
  const text = line.trim()
  if (!text) return false

  if (family === "slash") {
    if (startsWithAny(text, SLASH_ALLOW)) return false
    if (text.startsWith("/*") || text.startsWith("*/")) return true
    if (text.startsWith("//")) return true
  } else if (family === "hash") {
    if (startsWithAny(text, HASH_ALLOW)) return false
    if (text.startsWith("#")) return true
  } else if (family === "dash") {
    if (text.startsWith("--")) return true
  }
  return false
}

function isTrailingComment(line, family) {
  const markers = family === "slash" ? ["/*", "//"] : family === "hash" ? ["#"] : family === "dash" ? ["--"] : []
  for (const marker of markers) {
    const idx = indexOutsideString(line, marker)
    if (idx <= 0) continue
    const before = line.slice(0, idx)
    if (!before.trim()) continue
    const content = line.slice(idx).trim()
    if (family === "slash" && (line[idx - 1] === ":" || marker === "/*")) {
      if (marker === "/*") return true
      continue
    }
    if (family === "hash") {
      if (before.trimEnd().endsWith("$")) continue
      if (startsWithAny(content, HASH_ALLOW)) continue
      if (!/\s$/.test(before)) continue
    }
    if (family === "dash" && before.trimEnd().endsWith("-")) continue
    return true
  }
  return false
}

function offendingLines(text, family) {
  const out = []
  const lines = text.split("\n")
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (isCommentLine(line, family) || isTrailingComment(line, family)) {
      out.push({ n: i + 1, text: line.trim().slice(0, 120) })
    }
  }
  return out
}

function candidates(args) {
  args = args || {}
  const file = args.filePath || args.path || args.filename || ""
  if (Array.isArray(args.edits)) {
    return args.edits.map((e) => ({ file: e.filePath || e.path || file, text: e.newString || e.new_string || e.content || "" }))
  }
  const list = []
  for (const key of CONTENT_KEYS) {
    if (typeof args[key] === "string") list.push({ file, text: args[key] })
  }
  for (const key of PATCH_KEYS) {
    if (typeof args[key] === "string" && args[key].includes("\n")) {
      const added = args[key]
        .split("\n")
        .filter((l) => l.startsWith("+") && !l.startsWith("+++"))
        .map((l) => l.slice(1))
        .join("\n")
      if (added.trim()) list.push({ file, text: added })
    }
  }
  return list
}

export const NoComments = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (ALLOW) return
      if (!EDIT_TOOLS.has(input?.tool)) return
      for (const { file, text } of candidates(output?.args)) {
        if (!file || !text) continue
        const family = familyFor(file)
        if (!family) continue
        const hits = offendingLines(text, family)
        if (!hits.length) continue
        const preview = hits.slice(0, 5).map((h) => `  L${h.n}: ${h.text}`).join("\n")
        throw new Error(
          `[no-comments] Comentario(s) detectado(s) en ${file}. ` +
            `Los comentarios son un DEFECTO en esta codebase: el codigo debe explicarse solo ` +
            `(nombres claros, tipos fuertes, estructura). Si hace falta explicar el "por que", ` +
            `va en AGENTS.md, una skill, o el mensaje de commit, NUNCA en el codigo.\n${preview}\n` +
            `Rehace la edicion sin comentarios. (Override explicito del usuario: OPENCODE_ALLOW_COMMENTS=1)`,
        )
      }
    },
  }
}
