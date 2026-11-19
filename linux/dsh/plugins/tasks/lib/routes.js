/**
 * Rutas HTTP del plugin de tareas (loopback, servidas por webServer):
 *
 *   GET  /tasks/list?workspace=/abs/path          tareas de esa carpeta, con estado en vivo
 *   POST /tasks/create                            { workspace, title, goal }
 *   POST /tasks/update                            { id, state?, title?, goal?, sessionId? }
 *   POST /tasks/delete                            { id }
 *   POST /tasks/backfill                          { session }  trae los pedidos de una conversación
 *   GET  /tasks/turn?session=<id>                 pedido actual con su prueba visual
 *   GET  /tasks/evidence?session=<id>[&turn=N]    evidencia verificable de un turno
 *   GET  /tasks/media?path=/abs/file              imagen o video de la evidencia
 *   POST /tasks/open                              { path }  abre la carpeta en el gestor
 *
 * Los POST exigen `x-dsh-tasks: 1`: un sitio externo no puede mandarlo sin
 * preflight. Las GET son de solo lectura.
 */
import { spawn } from "node:child_process";
import { createReadStream, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute } from "node:path";
import { planBackfill } from "./backfill.js";
import { summarizeEvidence } from "./evidence.js";
import { MAX_MEDIA_BYTES, enrichMedia, mediaInfo } from "./media.js";
import { createTask, deleteTask, findSessionTask, findTurnTask, listTasks, updateTask } from "./store.js";

const MAX_BODY = 64 * 1024;
const SESSION_ID = /^[A-Za-z0-9:._-]{8,160}$/;

function sendJson(res, status, payload) {
	res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
	res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
	return new Promise((resolveBody, reject) => {
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
				resolveBody(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
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

/** Motivo de cierre en palabras, no en jerga del log. */
function closeText(reason) {
	if (reason === "completed") return "cerró bien";
	if (reason === "interrupted") return "se interrumpió";
	if (reason === "aborted") return "se abortó";
	if (reason === "error") return "terminó con error";
	return `cerró: ${reason}`;
}

/** Estado en vivo de un pedido: el turno que lo originó sigue o ya cerró. */
function liveStatus(live, task) {
	if (task.closeReason) return closeText(task.closeReason);
	if (!task.sessionId || !task.turn) return null;
	const end = live.turnEnds.get(task.sessionId);
	if (end && end.turn === task.turn) return closeText(end.reason);
	if (live.running.has(task.sessionId) && live.currentTurn.get(task.sessionId) === task.turn) return "en curso";
	return null;
}

function turnStatus(task, evidence, end, turn, running) {
	if (running) return "en curso";
	if (task?.closeReason) return closeText(task.closeReason);
	if (end && end.turn === turn) return closeText(end.reason);
	if (evidence.end) return closeText(evidence.end.reason);
	return null;
}

function routes(ctx, live) {
	return [
		{
			path: "/tasks/list",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const workspace = absoluteWorkspace(url.searchParams.get("workspace"));
				const tasks = await listTasks(workspace);
				sendJson(res, 200, { workspace: workspace || null, tasks: tasks.map((task) => ({ ...task, status: liveStatus(live, task) })) });
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
				sendJson(res, 200, { task: await createTask({ workspace, title: body.title, goal: body.goal, sessionId: body?.sessionId, turn: body?.turn, origin: "ui" }) });
			},
		},
		{
			path: "/tasks/update",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req);
				const id = typeof body?.id === "string" ? body.id.trim() : "";
				if (!id) return sendJson(res, 400, { error: "missing-id" });
				const patch = { state: body?.state, title: body?.title, goal: body?.goal, sessionId: body?.sessionId, turn: body?.turn };
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
			path: "/tasks/backfill",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req);
				const sessionId = (body?.session ?? "").trim();
				if (!SESSION_ID.test(sessionId)) return sendJson(res, 400, { error: "missing-session" });
				const snapshot = await ctx.sessionQuery.readSession(sessionId);
				const workspace = absoluteWorkspace(snapshot.session?.cwd);
				if (!workspace) return sendJson(res, 400, { error: "session-without-workspace" });
				const plan = planBackfill(snapshot.events);
				let created = 0;
				for (const item of plan) {
					if ((await findTurnTask(sessionId, item.turn)) !== null) continue;
					const task = await createTask({ workspace, title: item.title, goal: item.goal, sessionId, turn: item.turn, origin: "import" });
					if (item.closeReason) await updateTask(task.id, { closeReason: item.closeReason, closedAt: Date.now() });
					created += 1;
				}
				sendJson(res, 200, { created, tasks: await listTasks(workspace) });
			},
		},
		{
			path: "/tasks/turn",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const sessionId = (url.searchParams.get("session") ?? "").trim();
				if (!SESSION_ID.test(sessionId)) return sendJson(res, 400, { error: "missing-session" });
				const snapshot = await ctx.sessionQuery.readSession(sessionId);
				const events = snapshot.events;
				let latest = 0;
				for (const event of events) {
					const value = Number(event.data?.turn);
					if (Number.isSafeInteger(value) && value > latest) latest = value;
				}
				const running = live.running.has(sessionId);
				const end = live.turnEnds.get(sessionId);
				const turn = running ? (live.currentTurn.get(sessionId) ?? latest) : (end?.turn ?? latest);
				const task = (turn ? await findTurnTask(sessionId, turn) : null) ?? (await findSessionTask(sessionId));
				const evidence = await enrichMedia(summarizeEvidence(turn ? events.filter((event) => Number(event.data?.turn) === turn) : [], { cwd: snapshot.session?.cwd ?? null }));
				sendJson(res, 200, { sessionId, turn, running, status: turnStatus(task, evidence, end, turn, running), task, evidence });
			},
		},
		{
			path: "/tasks/evidence",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const sessionId = (url.searchParams.get("session") ?? "").trim();
				const turnParam = (url.searchParams.get("turn") ?? "").trim();
				const turn = /^\d+$/.test(turnParam) ? Number(turnParam) : null;
				if (!SESSION_ID.test(sessionId)) return sendJson(res, 400, { error: "missing-session" });
				const snapshot = await ctx.sessionQuery.readSession(sessionId);
				const events = turn === null ? snapshot.events : snapshot.events.filter((event) => Number(event.data?.turn) === turn);
				const evidence = await enrichMedia(summarizeEvidence(events, { cwd: snapshot.session?.cwd ?? null }));
				sendJson(res, 200, { sessionId, turn, title: snapshot.session?.title ?? null, evidence });
			},
		},
		{
			path: "/tasks/media",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const info = mediaInfo(url.searchParams.get("path") ?? "");
				if (!info) return sendJson(res, 400, { error: "unsupported-media" });
				let details;
				try {
					details = statSync(info.path);
				} catch {
					return sendJson(res, 404, { error: "missing" });
				}
				if (!details.isFile() || details.size <= 0 || details.size > MAX_MEDIA_BYTES) return sendJson(res, 413, { error: "too-large" });
				res.writeHead(200, { "content-type": info.mime, "content-length": details.size, "cache-control": "private, max-age=120" });
				const stream = createReadStream(info.path);
				stream.on("error", () => res.destroy());
				stream.pipe(res);
			},
		},
		{
			path: "/tasks/open",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req);
				const target = typeof body?.path === "string" ? body.path.trim() : "";
				const home = homedir();
				if (!target || !isAbsolute(target) || (target !== home && !target.startsWith(`${home}/`))) return sendJson(res, 400, { error: "path-outside-home" });
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

/** Registra todas las rutas en el webServer y captura sus errores. */
export function registerRoutes(ctx, live) {
	const byPath = new Map();
	for (const route of routes(ctx, live)) {
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
}
