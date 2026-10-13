import net from "node:net";

const SOURCE = "opencode:herdr-pane-state";
const AGENT = "opencode";
const TIMEOUT_MS = 500;
const WORKING = "working";
const IDLE = "idle";
const BLOCKED = "blocked";

let seq = Date.now() * 1000;
let paneClosed = false;
let chain = Promise.resolve();

function target() {
  if (process.env.HERDR_ENV !== "1") return null;
  const socketPath = process.env.HERDR_SOCKET_PATH;
  const paneId = process.env.HERDR_PANE_ID;
  if (!socketPath || !paneId || paneClosed) return null;
  return { socketPath, paneId };
}

function nextSeq() {
  seq += 1;
  return seq;
}

function request(method, params) {
  const address = target();
  if (!address) return Promise.resolve(null);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };
    try {
      const socket = net.createConnection(address.socketPath);
      let buffer = "";
      socket.setTimeout(TIMEOUT_MS);
      socket.on("connect", () => {
        const payload = {
          id: `${SOURCE}:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`,
          method,
          params: { pane_id: address.paneId, source: SOURCE, agent: AGENT, seq: nextSeq(), ...params },
        };
        socket.write(`${JSON.stringify(payload)}\n`);
      });
      socket.on("data", (chunk) => {
        buffer += chunk.toString();
        if (!buffer.includes("\n")) return;
        const line = buffer.split("\n")[0];
        socket.end();
        try {
          const message = JSON.parse(line);
          if (message && message.error && message.error.code === "pane_not_found") paneClosed = true;
          finish(message);
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

function report(state) {
  chain = chain.then(() => request("pane.report_agent", { state })).catch(() => null);
  return chain;
}

function stateForEvent(type) {
  if (typeof type !== "string") return null;
  if (type === "session.idle") return IDLE;
  if (type === "session.error" || type === "permission.asked" || type === "question.asked") return BLOCKED;
  if (type.startsWith("permission.") || type.startsWith("question.")) return WORKING;
  if (type.startsWith("session.") || type.startsWith("message.") || type.startsWith("tool.")) return WORKING;
  return null;
}

export const herdrPaneState = async () => {
  if (!target()) return {};
  await report(IDLE);
  return {
    "chat.message": async () => {
      await report(WORKING);
    },
    "tool.execute.before": async () => {
      await report(WORKING);
    },
    event: async (input) => {
      const state = stateForEvent(input && input.event ? input.event.type : null);
      if (state) await report(state);
    },
  };
};

export default herdrPaneState;
