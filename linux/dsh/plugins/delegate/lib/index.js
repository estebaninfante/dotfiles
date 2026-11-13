/**
 * dsh-local-delegate — host half.
 *
 * Registra la herramienta `delegate_claude`: el agente la llama como cualquier
 * otra tool y Claude Code corre ahí mismo, dentro del turno. La llamada y su
 * salida se dibujan en la conversación con el renderer de tools del harness.
 *
 * Sin archivos: el brief va por stdin (`claude -p …`). Sin panel aparte.
 */
import { execFile } from "node:child_process";
import { homedir } from "node:os";

const BIN = `${homedir()}/.local/bin/claude`;
const MAX_BUFFER = 8 << 20;
const DEFAULT_TIMEOUT_S = 900;

function runClaude(input, cwd, timeoutS) {
  return new Promise((resolve) => {
    const child = execFile(
      BIN,
      ["-p", "--permission-mode", "bypassPermissions"],
        { cwd, timeout: timeoutS * 1000, maxBuffer: MAX_BUFFER, env: process.env },
      (error, stdout, stderr) => {
        if (error) {
          resolve({
            ok: false,
            code: error.code ?? -1,
            killed: Boolean(error.killed),
            output: `${String(stdout || "").slice(-6000)}${stderr ? `\n[stderr]\n${String(stderr).slice(-3000)}` : ""}`.trim()
          });
          return;
        }
        resolve({ ok: true, code: 0, killed: false, output: String(stdout || "").trim() });
      }
    );
    child.stdin?.end(input, "utf8");
  });
}

const TOOL = {
  name: "delegate_claude",
  description:
    "Run Claude Code (CLI `claude -p`) as a sub-process of this turn to solve a task that DeepSeek Harness could not solve. The brief goes in `task` and is piped to Claude on stdin; there are no files. Returns Claude's final report. Use it when the same symptom survived 2-3 serious attempts, when each fix breaks something else, or when the user says to delegate to Claude. Claude must not restart the harness nor publish to git: say so inside the task.",
  parameters: {
    type: "object",
    additionalProperties: false,
    required: ["task"],
    properties: {
      task: {
        type: "string",
        description:
          "The full brief: exact symptom with evidence, environment traps, the variants already tried and what each produced, what must not break, and how to verify."
      },
      cwd: {
        type: "string",
        description: "Working directory for Claude. Defaults to the user's home."
      },
      timeout_seconds: {
        type: "integer",
        description: `Hard limit for the whole run. Defaults to ${DEFAULT_TIMEOUT_S}.`
      }
    }
  },
  output: {
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        ok: { type: "boolean" },
        code: { type: "integer" },
        killed: { type: "boolean" },
        output: { type: "string" }
      }
    },
    render(args, value) {
      const result = value ?? {};
      const head = result.ok ? "Claude Code terminó" : `Claude Code falló (exit ${result.code ?? "?"})`;
      return [{ type: "text", text: `${head}\n\n${result.output ?? ""}`.trim() }];
    }
  },
  async execute(args) {
    const task = typeof args?.task === "string" ? args.task : "";
    if (task.trim().length < 40) throw new Error("delegate_claude: el brief es demasiado corto para delegar");
    const cwd = typeof args?.cwd === "string" && args.cwd.trim() ? args.cwd.trim() : homedir();
    const timeoutS = Number.isInteger(args?.timeout_seconds) ? args.timeout_seconds : DEFAULT_TIMEOUT_S;
    return runClaude(task, cwd, Math.min(Math.max(timeoutS, 30), 3600));
  }
};

export const inject = ["tools"];
export const name = "local-delegate";

export function apply(ctx) {
  ctx.tools.register(TOOL);
  ctx.logger?.info?.("delegate: herramienta delegate_claude registrada");
}
