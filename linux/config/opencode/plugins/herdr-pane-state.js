import net from "node:net";
import fs from "node:fs";
import { Plugin } from "@opencode/plugin";

const DEBUG_PATH = "/tmp/herdr-plugin-debug.log";

const debug = (tag, value) => {
  try {
    fs.appendFileSync(DEBUG_PATH, `${new Date().toISOString()} ${tag} ${JSON.stringify(value) ?? ""}\n`);
  } catch {}
};

const SOURCE = "opencode:herdr-pane-state";
const AGENT = "opencode";
const TIMEOUT_MS = 500;
const PANE_CACHE_MS = 2000;

function targetSocket() {
  if (process.env.HERDR_ENV !== "1") return null;
  return process.env.HERDR_SOCKET_PATH || null;
}

function request(socketPath, method, params) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    try {
      const socket = net.createConnection(socketPath);
      let buffer = "";
      socket.setTimeout(TIMEOUT_MS);
      socket.on("connect", () => {
        const payload = {
          id: `${SOURCE}:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`,
          method,
          params,
        };
        socket.write(`${JSON.stringify(payload)}\n`);
      });
      socket.on("data", (chunk) => {
        buffer += chunk.toString();
        if (!buffer.includes("\n")) return;
        const line = buffer.split("\n")[0];
        socket.end();
        try {
          finish(JSON.parse(line));
        } catch {
          finish(null);
        }
      });
      socket.on("timeout", () => {
        socket.destroy();
        finish(null);
      });
      socket.on("error", () => {
        socket.destroy();
        finish(null);
      });
      socket.on("close", () => finish(null));
    } catch {
      finish(null);
    }
  });
}

function stateFor(type) {
  if (typeof type !== "string") return null;
  if (type === "session.idle") return "idle";
  if (type === "session.error" || type === "permission.asked" || type === "form.created") return "blocked";
  if (type.startsWith("permission.") || type.startsWith("form.") || type.startsWith("question.")) return "working";
  if (type.startsWith("session.") || type.startsWith("message.") || type.startsWith("tool.")) return "working";
  return null;
}

function sessionDirectory(session) {
  if (!session || typeof session !== "object") return undefined;
  const value = session.directory ?? session.worktree;
  return typeof value === "string" && value ? value : undefined;
}

function eventSessionID(event) {
  if (!event || typeof event !== "object") return undefined;
  const properties = event.properties ?? event.data ?? event;
  const value = properties.sessionID ?? properties.session?.id ?? event.sessionID;
  return typeof value === "string" && value ? value : undefined;
}

export default Plugin.define({
  id: "herdr.pane-state",
  async setup(ctx) {
    const socketPath = targetSocket();
    if (!socketPath) return;

    let paneCache = { at: 0, panes: [] };
    let lastState = new Map();
    let seq = Date.now() * 1000;
    let chain = Promise.resolve();

    const panesFor = async (directory) => {
      const now = Date.now();
      if (now - paneCache.at > PANE_CACHE_MS) {
        const response = await request(socketPath, "pane.list", {});
        const panes = response?.result?.panes;
        paneCache = { at: now, panes: Array.isArray(panes) ? panes : [] };
      }
      return paneCache.panes.filter((pane) => pane?.cwd === directory).map((pane) => pane.pane_id);
    };

    const report = (paneID, state) => {
      if (lastState.get(paneID) === state) return;
      lastState.set(paneID, state);
      seq += 1;
      chain = chain.then(async () => {
        const response = await request(socketPath, "pane.report_agent", {
          pane_id: paneID,
          source: SOURCE,
          agent: AGENT,
          state,
          seq,
        });
        if (response?.error?.code === "pane_not_found") lastState.delete(paneID);
      }).catch(() => {});
    };

    const controller = new AbortController();
    debug("setup", { socketPath });
    void (async () => {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        const state = stateFor(event?.type);
        debug("event", { type: event?.type, state, data: event?.data });
        if (!state) continue;
        const sessionID = eventSessionID(event);
        if (!sessionID) continue;
        const session = await ctx.session.get({ sessionID }).catch((error) => {
          debug("session-error", { sessionID, error: String(error) });
          return null;
        });
        const directory = sessionDirectory(session);
        debug("session", { sessionID, directory, found: !!session });
        if (!directory) continue;
        const panes = await panesFor(directory);
        debug("panes", { directory, panes });
        for (const paneID of panes) report(paneID, state);
      }
    })().catch((error) => debug("loop-error", { error: String(error) }));

    return () => controller.abort();
  },
});
