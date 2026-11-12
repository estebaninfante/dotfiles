/**
 * dsh-local-path-links — host half.
 *
 * Resuelve una ruta escrita en el chat (`~/…`, relativa, absoluta) contra la
 * sesión que el usuario está mirando y decide qué hacer:
 *  - archivo  → devuelve la dirección `dsh-resource://` para que el cliente la
 *               abra en el panel lateral (preview de texto, imagen, PDF, …).
 *  - carpeta  → la abre en el gestor de archivos del escritorio (xdg-open).
 *  - no existe → lo informa para que el cliente avise, sin abrir nada.
 *
 * No escribe nada en la sesión ni en el workspace: solo stat + abrir.
 */

import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { stat } from "node:fs/promises";
import { isAbsolute, resolve as resolvePath } from "node:path";

const ROUTE = "/path-links/open";
const MAX_BODY_BYTES = 16 * 1024;
const MAX_PATH_CHARS = 4096;
const OPEN_TIMEOUT_MS = 5_000;
const FILE_ADDRESS_PREFIX = "dsh-resource://file/";

/** Cuerpo JSON chico del request. */
function readJsonBody(req) {
	return new Promise((resolve, reject) => {
		const chunks = [];
		let size = 0;
		req.on("data", (chunk) => {
			size += chunk.length;
			if (size > MAX_BODY_BYTES) {
				reject(new Error("body too large"));
				req.destroy();
				return;
			}
			chunks.push(chunk);
		});
		req.on("end", () => {
			try {
				resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
			} catch (error) {
				reject(new Error("invalid JSON body", { cause: error }));
			}
		});
		req.on("error", reject);
	});
}

function sendJson(res, status, value) {
	const body = JSON.stringify(value);
	res.writeHead(status, {
		"content-type": "application/json; charset=utf-8",
		"content-length": String(Buffer.byteLength(body)),
		"cache-control": "no-store"
	});
	res.end(body);
}

/** Codifica un path segmento a segmento, dejando `:` literal (discos Windows). */
function encodePath(path) {
	return path.split("/").map((segment) => encodeURIComponent(segment).replace(/%3A/gi, ":")).join("/");
}

/**
 * `dsh-resource://file/session/<id>/<path>` con la misma regla que el chat: si
 * el archivo vive dentro del workspace de la sesión, se direcciona relativo.
 */
function fileAddress(sessionId, absolutePath, cwd) {
	const normalized = absolutePath.replace(/\\/g, "/");
	const root = typeof cwd === "string" ? cwd.replace(/\\/g, "/").replace(/\/+$/, "") : "";
	let relative = normalized;
	if (root !== "" && normalized === root) relative = "";
	else if (root !== "" && normalized.startsWith(`${root}/`)) relative = normalized.slice(root.length + 1);
	return `${FILE_ADDRESS_PREFIX}session/${encodeURIComponent(sessionId)}/${encodePath(relative)}`;
}

/** Expande `~` y resuelve relativas contra el cwd de la sesión. */
function expandPath(raw, cwd) {
	const trimmed = raw.trim().replace(/^['"`]+|['"`]+$/g, "");
	if (trimmed.length === 0 || trimmed.length > MAX_PATH_CHARS) return void 0;
	if (/[\u0000-\u001f\u007f]/.test(trimmed)) return void 0;
	const withHome = trimmed === "~" ? homedir() : trimmed.startsWith("~/") ? `${homedir()}${trimmed.slice(1)}` : trimmed;
	const base = typeof cwd === "string" && isAbsolute(cwd) ? cwd : homedir();
	return resolvePath(base, withHome);
}

/** Abre una carpeta en el gestor del escritorio; no bloquea la respuesta más que el timeout. */
function openInFileManager(path) {
	return new Promise((resolve) => {
		execFile("xdg-open", [path], { timeout: OPEN_TIMEOUT_MS }, (error) => {
			resolve(error === null ? { opened: true } : { opened: false, reason: error.message });
		});
	});
}

export const inject = ["webServer", "sessions"];

/**
 * @param ctx - host context carrying webServer and sessions.
 */
export function apply(ctx) {
	const handler = async (req, res) => {
		if (req.method !== "POST") {
			sendJson(res, 405, { error: "method-not-allowed" });
			return;
		}
		if (req.headers["x-dsh-path-links"] !== "1") {
			sendJson(res, 403, { error: "forbidden" });
			return;
		}
		let payload;
		try {
			payload = await readJsonBody(req);
		} catch (error) {
			sendJson(res, 400, { error: "bad-request", message: error instanceof Error ? error.message : String(error) });
			return;
		}
		const sessionId = typeof payload?.sessionId === "string" ? payload.sessionId : "";
		const raw = typeof payload?.path === "string" ? payload.path : "";
		const session = sessionId.length > 0 ? ctx.sessions?.get?.(sessionId) : void 0;
		const absolute = expandPath(raw, session?.header?.cwd);
		if (absolute === void 0) {
			sendJson(res, 400, { error: "bad-path" });
			return;
		}
		let info;
		try {
			info = await stat(absolute);
		} catch (error) {
			const missing = error !== null && typeof error === "object" && error.code === "ENOENT";
			sendJson(res, 200, { kind: missing ? "missing" : "error", absolute });
			return;
		}
		if (info.isDirectory()) {
			const opened = await openInFileManager(absolute);
			sendJson(res, 200, { kind: "dir", absolute, ...opened });
			return;
		}
		if (!info.isFile()) {
			sendJson(res, 200, { kind: "error", absolute });
			return;
		}
		const address = sessionId.length === 0 ? `${FILE_ADDRESS_PREFIX}absolute/${encodePath(absolute)}` : fileAddress(sessionId, absolute, session?.header?.cwd);
		sendJson(res, 200, { kind: "file", absolute, address, size: info.size });
	};

	ctx.effect(() => ctx.webServer.register({
		kind: "exact",
		path: ROUTE,
		handler
	}), "path-links: route");
}
