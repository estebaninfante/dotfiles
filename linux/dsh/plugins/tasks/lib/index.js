/**
 * dsh-local-tasks — host half.
 *
 * Tareas por proyecto (carpeta) y evidencia real de cada conversación tomada del
 * log de la sesión (`ctx.sessionQuery`), no de lo que el agente dice.
 *
 * Cada pedido del usuario queda registrado como tarea: al abrirse un turno se
 * crea la tarea del proyecto con el texto del pedido, y un guard impide que el
 * agente actúe mientras esa tarea no exista.
 *
 * Rutas (loopback, servidas por el webServer del perfil):
 *   GET  /tasks/list?workspace=/abs/path   tareas de esa carpeta
 *   POST /tasks/create                     { workspace, title, goal }
 *   POST /tasks/update                     { id, state?, title?, goal?, sessionId? }
 *   POST /tasks/delete                     { id }
 *   GET  /tasks/evidence?session=<id>[&turn=N]   evidencia verificable
 *   GET  /tasks/media?path=/abs/file       imagen o video de la evidencia
 *   POST /tasks/open                       { path }  abre la carpeta en el gestor
 *
 * Los POST exigen `x-dsh-tasks: 1`: un sitio externo no puede mandarlo sin
 * preflight. Las GET son de solo lectura.
 */
import { spawn } from "node:child_process";
import { createReadStream, statSync } from "node:fs";
import { stat } from "node:fs/promises";
import { homedir } from "node:os";
import { extname, isAbsolute, resolve } from "node:path";
import { summarizeEvidence } from "./evidence.js";
import { adoptTurn, createTask, deleteTask, findSessionTask, findTurnTask, listTasks, updateTask } from "./store.js";

const MAX_BODY = 64 * 1024;
const MAX_MEDIA_BYTES = 120 * 1024 * 1024;
const SESSION_ID = /^[A-Za-z0-9:._-]{8,160}$/;
const MIME = {
	png: "image/png",
	jpg: "image/jpeg",
	jpeg: "image/jpeg",
	webp: "image/webp",
	gif: "image/gif",
	avif: "image/avif",
	bmp: "image/bmp",
	svg: "image/svg+xml",
	mp4: "video/mp4",
	webm: "video/webm",
	mov: "video/quicktime",
	mkv: "video/x-matroska",
};

export const inject = ["webServer", "sessionQuery", "systemPrompt", "tools"];

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

/** Solo imágenes y videos bajo el home o /tmp: nunca URLs, binarios ni rutas raras. */
function mediaInfo(path) {
	const target = resolve(path);
	const home = homedir();
	if (target !== home && !target.startsWith(`${home}/`) && !target.startsWith("/tmp/")) return null;
	const mime = MIME[extname(target).slice(1).toLowerCase()];
	if (!mime) return null;
	return { path: target, mime };
}

async function readableMedia(path) {
	const info = mediaInfo(path);
	if (!info) return null;
	try {
		const details = await stat(info.path);
		if (!details.isFile() || details.size <= 0 || details.size > MAX_MEDIA_BYTES) return null;
		return { ...info, bytes: details.size, url: `/tasks/media?path=${encodeURIComponent(info.path)}` };
	} catch {
		return null;
	}
}

function textOfMessage(message) {
	if (!message || !Array.isArray(message.content)) return "";
	return message.content
		.filter((part) => part && part.type === "text" && typeof part.text === "string")
		.map((part) => part.text)
		.join("\n")
		.trim();
}

function rootSession(session) {
	const header = session?.header;
	if (!header) return false;
	if (header.origin === "subagent") return false;
	if ((header.delegationDepth ?? 0) > 0) return false;
	return typeof header.cwd === "string" && header.cwd.startsWith("/");
}

function firstLine(text) {
	const line = String(text ?? "").split("\n").find((item) => item.trim() !== "") ?? "";
	return line.trim().slice(0, 120);
}

/** Estado en vivo de un pedido: el turno que lo originó sigue o ya cerró. */
function liveStatus(live, task) {
	if (!task.sessionId || !task.turn) return null;
	const end = live.turnEnds.get(task.sessionId);
	if (end && end.turn === task.turn) return end.reason === "completed" ? "cerró bien" : `cerró: ${end.reason}`;
	if (live.running.has(task.sessionId) && live.currentTurn.get(task.sessionId) === task.turn) return "en curso";
	return null;
}

async function enrichMedia(evidence) {
	const media = [];
	for (const item of evidence.media) {
		const readable = await readableMedia(item.path);
		if (readable) media.push({ ...item, ...readable });
	}
	evidence.media = media;
	evidence.stats.media = media.length;
	return evidence;
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
			path: "/tasks/turn",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const sessionId = (url.searchParams.get("session") ?? "").trim();
				if (!SESSION_ID.test(sessionId)) return sendJson(res, 400, { error: "missing-session" });
				try {
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
					const reason = running ? "en curso" : end && end.turn === turn ? (end.reason === "completed" ? "cerró bien" : `cerró: ${end.reason}`) : evidence.end ? (evidence.end.reason === "completed" ? "cerró bien" : `cerró: ${evidence.end.reason}`) : null;
					sendJson(res, 200, { sessionId, turn, running, status: reason, task, evidence });
				} catch (error) {
					const message = error instanceof Error ? error.message : String(error);
					if (/not.?found/i.test(message)) return sendJson(res, 404, { error: "session-not-found" });
					throw error;
				}
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
				sendJson(res, 200, {
					task: await createTask({
						workspace,
						title: body.title,
						goal: body.goal,
						sessionId: body?.sessionId,
						turn: body?.turn,
						origin: "ui",
					}),
				});
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
			path: "/tasks/evidence",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const sessionId = (url.searchParams.get("session") ?? "").trim();
				const turnParam = (url.searchParams.get("turn") ?? "").trim();
				const turn = /^\d+$/.test(turnParam) ? Number(turnParam) : null;
				if (!SESSION_ID.test(sessionId)) return sendJson(res, 400, { error: "missing-session" });
				try {
					const snapshot = await ctx.sessionQuery.readSession(sessionId);
					const events = turn === null ? snapshot.events : snapshot.events.filter((event) => Number(event.data?.turn) === turn);
					const evidence = await enrichMedia(summarizeEvidence(events, { cwd: snapshot.session?.cwd ?? null }));
					sendJson(res, 200, { sessionId, turn, title: snapshot.session?.title ?? null, evidence });
				} catch (error) {
					const message = error instanceof Error ? error.message : String(error);
					if (/not.?found/i.test(message)) return sendJson(res, 404, { error: "session-not-found" });
					throw error;
				}
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
				res.writeHead(200, {
					"content-type": info.mime,
					"content-length": details.size,
					"cache-control": "private, max-age=120",
				});
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
	// Estado en vivo de los pedidos: turno actual, cierre y registro en curso.
	const live = {
		currentTurn: new Map(),
		turnEnds: new Map(),
		running: new Set(),
		registering: new Map(),
		inflight: new Map(),
		requestText: new Map(),
	};
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

	// Cada pedido es una tarea: cuando llega el mensaje escrito por el usuario
	// dentro de un turno se crea la tarea del proyecto. Un turno = una tarea.
	// Solo cuentan los mensajes con source.kind "user": los recordatorios y el
	// runtime context del harness también llegan como user/message.
	async function registerRequest(session) {
		const sessionId = session.id;
		const turn = live.currentTurn.get(sessionId);
		const request = live.requestText.get(sessionId) ?? "";
		if (!turn || !request) return;
		if ((await findTurnTask(sessionId, turn)) !== null) return;
		const linked = await findSessionTask(sessionId);
		if (linked !== null && linked.turn == null) {
			await adoptTurn(sessionId, turn);
			return;
		}
		const title = firstLine(request) || `Pedido del turno ${turn}`;
		await createTask({
			workspace: session.header.cwd,
			title,
			goal: request.length > title.length ? request.slice(0, 2000) : "",
			sessionId,
			turn,
			origin: "auto",
		});
	}
	function scheduleRegister(session) {
		const sessionId = session.id;
		if (live.inflight.has(sessionId)) return;
		live.registering.set(sessionId, { at: Date.now() });
		const job = registerRequest(session)
			.catch(() => undefined)
			.finally(() => {
				live.inflight.delete(sessionId);
				live.registering.delete(sessionId);
				live.requestText.delete(sessionId);
			});
		live.inflight.set(sessionId, job);
	}
	ctx.on("session/event", (session, event) => {
		if (!rootSession(session)) return;
		if (event.type === "turn/start") {
			const turn = Number(event.data?.turn ?? 0);
			if (!Number.isSafeInteger(turn) || turn <= 0) return;
			live.currentTurn.set(session.id, turn);
			live.running.add(session.id);
			if (live.requestText.has(session.id)) scheduleRegister(session);
			return;
		}
		if (event.type === "turn/end") {
			const turn = Number(event.data?.turn ?? 0);
			const reason = String(event.data?.reason?.kind ?? "?");
			live.running.delete(session.id);
			if (Number.isSafeInteger(turn) && turn > 0) live.turnEnds.set(session.id, { turn, reason });
			return;
		}
		if (event.type !== "user/message") return;
		if (event.data?.source?.kind !== "user") return;
		const text = textOfMessage(event.data);
		if (!text) return;
		live.requestText.set(session.id, text);
		if (live.currentTurn.has(session.id)) scheduleRegister(session);
	});
	ctx.effect(
		() =>
			ctx.tools.guard((execution) => {
				const sessionId = execution?.agent?.id;
				if (!sessionId) return undefined;
				const state = live.registering.get(sessionId);
				if (!state) return undefined;
				if (Date.now() - state.at > 8000) return undefined;
				if (execution.name === "ask_user_question") return undefined;
				return "El harness está registrando este pedido como tarea del proyecto. Reintentá la misma llamada en un instante.";
			}),
		"tasks: cada pedido necesita tarea",
	);

	ctx.effect(
		() =>
			ctx.systemPrompt.section({
				name: "local-tasks/evidence",
				order: 45,
				text: [
					"## Tareas y evidencia",
					"Cada pedido del usuario queda registrado como una tarea del proyecto en la vista Tareas; no hace falta crearla a mano.",
					"Una tarea no está terminada porque se tocaron archivos: está terminada cuando hay prueba que se pueda VER.",
					"- Si el cambio se ve en pantalla, capturá la app real (pantalla-agente montar y capturar, o grim) y guardá la imagen bajo el proyecto o /tmp.",
					"- Si hay tests o build, corrélos y mostrá cómo terminaron.",
					"- Cerrá nombrando las rutas de las imágenes o videos y qué prueba cada una; la tarjeta de Evidencia las levanta del log de la sesión.",
					"Sin captura ni prueba visual, la tarea queda sin evidencia visible.",
				].join("\n"),
			}),
		"tasks: instrucciones de evidencia",
	);

	ctx.logger?.info?.("tasks: tareas por proyecto y evidencia montadas");
}
