/**
 * dsh-local-tasks — host half.
 *
 * Tareas por carpeta (proyecto) y evidencia de cada conversación tomada del log
 * real de la sesión (`ctx.sessionQuery`), no de lo que el agente dice.
 *
 * Rutas (loopback, servidas por el webServer del perfil):
 *   GET  /tasks/list?workspace=/abs/path   tareas de esa carpeta
 *   POST /tasks/create                     { workspace, title, goal }
 *   POST /tasks/update                     { id, state?, title?, goal?, sessionId? }
 *   POST /tasks/delete                     { id }
 *   GET  /tasks/evidence?session=<id>      evidencia verificable de la sesión
 *   POST /tasks/open                       { path }  abre la carpeta en el gestor
 *
 * Los POST exigen `x-dsh-tasks: 1`: un sitio externo no puede mandarlo sin
 * preflight. Las GET son de solo lectura.
 */
import { spawn } from "node:child_process";
import { statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute } from "node:path";
import { summarizeEvidence } from "./evidence.js";
import { createTask, deleteTask, listTasks, updateTask } from "./store.js";

const MAX_BODY = 64 * 1024;
const SESSION_ID = /^[A-Za-z0-9:._-]{8,160}$/;

export const inject = ["webServer", "sessionQuery"];

function sendJson(res, status, payload) {
	res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
	res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
	return new Promise((resolve, reject) => {
		let size = 0;
		const chunks = [];
		req.on("data", (chunk) => {
			size += chunk.length;
			if (size > MAX_BODY) {
				reject(new Error("body-too-large"));
				req.destroy();
				return;
			}
			chunks.push(chunk);
		});
		req.on("end", () => {
			try {
				resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
			} catch (error) {
				reject(error);
			}
		});
		req.on("error", reject);
	});
}

function fail(res, error, status = 500) {
	sendJson(res, status, { error: "tasks-failed", message: error instanceof Error ? error.message : String(error) });
}

function absoluteWorkspace(value) {
	const path = typeof value === "string" ? value.trim() : "";
	return path && isAbsolute(path) ? path : "";
}

function routes(ctx) {
	return [
		{
			path: "/tasks/list",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const workspace = absoluteWorkspace(url.searchParams.get("workspace"));
				const tasks = await listTasks(workspace);
				sendJson(res, 200, { workspace: workspace || null, tasks });
			},
		},
		{
			path: "/tasks/create",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req);
				const workspace = absoluteWorkspace(body?.workspace);
				if (!workspace) return sendJson(res, 400, { error: "missing-workspace" });
				if (typeof body?.title !== "string" || !body.title.trim()) return sendJson(res, 400, { error: "missing-title" });
				const task = await createTask({ workspace, title: body.title, goal: body.goal });
				sendJson(res, 200, { task });
			},
		},
		{
			path: "/tasks/update",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req);
				const id = typeof body?.id === "string" ? body.id.trim() : "";
				if (!id) return sendJson(res, 400, { error: "missing-id" });
				const patch = {
					state: body?.state,
					title: body?.title,
					goal: body?.goal,
					sessionId: body?.sessionId,
				};
				sendJson(res, 200, { task: await updateTask(id, patch) });
			},
		},
		{
			path: "/tasks/delete",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req);
				const id = typeof body?.id === "string" ? body.id.trim() : "";
				if (!id) return sendJson(res, 400, { error: "missing-id" });
				sendJson(res, 200, await deleteTask(id));
			},
		},
		{
			path: "/tasks/evidence",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const sessionId = (url.searchParams.get("session") ?? "").trim();
				if (!SESSION_ID.test(sessionId)) return sendJson(res, 400, { error: "missing-session" });
				try {
					const snapshot = await ctx.sessionQuery.readSession(sessionId);
					sendJson(res, 200, {
						sessionId,
						title: snapshot.session?.title ?? null,
						evidence: summarizeEvidence(snapshot.events, { cwd: snapshot.session?.cwd ?? null }),
					});
				} catch (error) {
					const message = error instanceof Error ? error.message : String(error);
					if (/not.?found/i.test(message)) return sendJson(res, 404, { error: "session-not-found" });
					throw error;
				}
			},
		},
		{
			path: "/tasks/open",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req);
				const target = typeof body?.path === "string" ? body.path.trim() : "";
				const home = homedir();
				if (!target || !isAbsolute(target) || (target !== home && !target.startsWith(`${home}/`))) {
					return sendJson(res, 400, { error: "path-outside-home" });
				}
				try {
					if (!statSync(target).isDirectory()) return sendJson(res, 400, { error: "not-a-directory" });
				} catch {
					return sendJson(res, 404, { error: "missing" });
				}
				const child = spawn("xdg-open", [target], { detached: true, stdio: "ignore" });
				child.unref();
				sendJson(res, 200, { ok: true });
			},
		},
	];
}

export function apply(ctx) {
	const byPath = new Map();
	for (const route of routes(ctx)) {
		if (!byPath.has(route.path)) byPath.set(route.path, {});
		const methods = byPath.get(route.path);
		if (methods[route.method]) throw new Error(`tasks: ruta duplicada ${route.method} ${route.path}`);
		methods[route.method] = route.handler;
	}
	for (const [path, methods] of byPath) {
		ctx.effect(
			() =>
				ctx.webServer.register({
					kind: "exact",
					path,
					handler: async (req, res) => {
						const method = req.method ?? "GET";
						const handler = methods[method];
						if (!handler) return sendJson(res, 405, { error: "method-not-allowed", allow: Object.keys(methods) });
						if (method === "POST" && req.headers["x-dsh-tasks"] !== "1") return sendJson(res, 403, { error: "forbidden" });
						try {
							await handler(req, res);
						} catch (error) {
							fail(res, error);
						}
					},
				}),
			`tasks: route ${path}`,
		);
	}
	ctx.logger?.info?.("tasks: tareas por proyecto y evidencia montadas");
}
