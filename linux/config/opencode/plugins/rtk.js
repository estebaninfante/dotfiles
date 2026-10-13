import { Plugin } from "@opencode/plugin"
import { spawnSync } from "node:child_process"

function rtkAvailable() {
  const proc = spawnSync("sh", ["-lc", "command -v rtk"], { encoding: "utf8" })
  return proc.status === 0 && String(proc.stdout ?? "").trim().length > 0
}

export default Plugin.define({
  id: "eztvn.rtk",
  async setup(ctx) {
    if (!rtkAvailable()) {
      console.warn("[rtk] rtk binary not found in PATH — plugin disabled")
      return
    }
    await ctx.tool.hook("execute.before", (event) => {
      const tool = String(event.tool ?? "").toLowerCase()
      if (tool !== "bash" && tool !== "shell") return
      const args = event.input
      if (!args || typeof args !== "object") return
      const command = args.command
      if (typeof command !== "string" || !command) return
      try {
        const proc = spawnSync("rtk", ["rewrite", command], { encoding: "utf8" })
        const rewritten = String(proc.stdout ?? "").trim()
        if (rewritten && rewritten !== command) args.command = rewritten
      } catch {}
    })
  },
})
