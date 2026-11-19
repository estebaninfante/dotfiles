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
import { assistantSummary, textOfMessage } from "./events.js";
import { summarizeEvidence } from "./evidence.js";
import { MAX_MEDIA_BYTES, enrichMedia, mediaInfo } from "./media.js";
import { createTask, deleteTask, findLatestTask, findTurnTask, listTasks, taskTurns, updateTask } from "./store.js";

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

/**
 * Los seis estados de una tarea. Todo lo demás (motivo de cierre, resultado,
 * si el turno sigue) se traduce a uno de estos; la UI no inventa variantes.
 */
const STATE_TEXT = {
	abierta: "abierta",
	en_curso: "en curso",
	por_cerrar: "por cerrar",
	cerrada: "cerrada",
	fallada: "fallada",
	cancelada: "cancelada",
};

/** Motivo de cierre en palabras, para el detalle: no es el estado. */
function closeText(reason) {
	if (reason === "completed") return "terminó el turno";
	if (reason === "interrupted") return "lo detuviste";
	if (reason === "aborted") return "se abortó";
	if (reason === "error") return "terminó con error";
	return `cerró: ${reason}`;
}

/**
 * Estado de una tarea: en curso si se trabaja ahora, cerrada si el agente la dio
 * por terminada, fallada si falló, cancelada si el usuario detuvo el turno,
 * por cerrar cuando el turno terminó y todavía nadie la revisó, y abierta si
 * falta trabajo.
 */
function taskState(task, live = {}) {
	if (task?.state === "cancelada" || task?.outcome === "cancelada") return STATE_TEXT.cancelada;
	const turns = taskTurns(task);
	// Si el turno está corriendo, la tarea está en curso aunque antes se cerrara.
	if (live.running && live.current && turns.includes(live.current)) return STATE_TEXT.en_curso;
	if (task?.outcome === "falló") return STATE_TEXT.fallada;
	if (task?.state === "resuelta" || task?.outcome === "ok") return STATE_TEXT.cerrada;
	// El turno terminó (con evidencia o no) y la tarea quedó sin revisar.
	if (task?.outcome === "parcial" || live.ended) return STATE_TEXT.por_cerrar;
	return STATE_TEXT.abierta;
}

/** Estado en vivo de un pedido con lo que sabe el proceso ahora mismo. */
function liveStatus(live, task) {
	const state = taskState(task, {
		running: Boolean(task.sessionId && live.running.has(task.sessionId)),
		current: task.sessionId ? live.currentTurn.get(task.sessionId) : null,
		ended: Boolean(task.closeReason),
	});
	return state;
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
			path: "/tasks/all",
			method: "GET",
			handler: async (req, res) => {
				const tasks = await listTasks(undefined);
				const now = Date.now();
				sendJson(res, 200, {
					tasks: tasks.map((task) => ({
						...task,
						workspaceName: task.workspace.split("/").filter(Boolean).pop() ?? task.workspace,
						openMs: Math.max(0, now - Number(task.createdAt ?? now)),
						status: liveStatus(live, task),
					})),
				});
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
				const patch = { state: body?.state, title: body?.title, goal: body?.goal, steps: body?.steps, outcome: body?.outcome, note: body?.note, sessionId: body?.sessionId, turn: body?.turn };
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
				const byTurn = new Map();
				const ends = new Map();
				let latest = 0;
				for (const event of snapshot.events) {
					const turn = Number(event.data?.turn);
					if (!Number.isSafeInteger(turn) || turn <= 0) continue;
					if (turn > latest) latest = turn;
					if (event.type === "turn/end") ends.set(turn, String(event.data?.reason?.kind ?? "?"));
					const bucket = byTurn.get(turn) ?? [];
					bucket.push(event);
					byTurn.set(turn, bucket);
				}
				const running = latest > 0 && !ends.has(latest);
				// Mientras el turno corre, la tarjeta es la tarea de ESE turno: lo que se
				// está trabajando ahora, no la prueba del pedido anterior.
				const runningTask = running ? await findTurnTask(sessionId, latest) : null;
				// La tarjeta muestra la evidencia del último pedido terminado que dejó
				// prueba visual: un turno nuevo sin terminar no la esconde.
				let chosen = null;
				if (!runningTask) {
					for (const turn of [...byTurn.keys()].sort((a, b) => b - a)) {
						if (!ends.has(turn)) continue;
						const evidence = await enrichMedia(summarizeEvidence(byTurn.get(turn), { cwd: snapshot.session?.cwd ?? null }));
						if (evidence.media.length || evidence.deliverables.length) {
							chosen = { turn, evidence, reason: ends.get(turn) };
							break;
						}
					}
				}
				// Sin prueba todavía: la tarjeta igual muestra la tarea en curso apenas
				// el agente la nombra, con su estado y el resumen que haya.
				const current = runningTask ?? (!chosen ? await findLatestTask(sessionId) : null);
				const currentTurn = runningTask ? latest : current ? (taskTurns(current).slice(-1)[0] ?? latest) : 0;
				const task = chosen ? await findTurnTask(sessionId, chosen.turn) : current;
				const evidence =
					chosen?.evidence ??
					(currentTurn
						? await enrichMedia(summarizeEvidence(byTurn.get(currentTurn) ?? [], { cwd: snapshot.session?.cwd ?? null }))
						: await enrichMedia(summarizeEvidence([], { cwd: snapshot.session?.cwd ?? null })));
				const turnEnded = ends.get(currentTurn ?? 0);
				sendJson(res, 200, {
					sessionId,
					turn: chosen?.turn ?? currentTurn ?? 0,
					latestTurn: latest,
					running,
					status: task
						? taskState(task, { running, current: running ? latest : null, ended: Boolean(turnEnded) })
						: turnEnded
							? "abierta"
							: running
								? "en curso"
								: null,
					closeReason: chosen ? closeText(chosen.reason) : turnEnded ? closeText(turnEnded) : null,
					summary: chosen ? assistantSummary(byTurn.get(chosen.turn)) : currentTurn ? assistantSummary(byTurn.get(currentTurn) ?? []) : "",
					task,
					evidence,
				});
			},
		},
		{
			path: "/tasks/session",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const sessionId = (url.searchParams.get("session") ?? "").trim();
				if (!SESSION_ID.test(sessionId)) return sendJson(res, 400, { error: "missing-session" });
				const snapshot = await ctx.sessionQuery.readSession(sessionId);
				const byTurn = new Map();
				const ends = new Map();
				// Tiempos por turno: cuándo arrancó y cuándo cerró, para medir el trabajo.
				const times = new Map();
				let latest = 0;
				for (const event of snapshot.events) {
					const turn = Number(event.data?.turn);
					if (!Number.isSafeInteger(turn) || turn <= 0) continue;
					if (turn > latest) latest = turn;
					const stamp = Number(event.time ?? 0);
					const slot = times.get(turn) ?? {};
					if (event.type === "turn/start") slot.start = slot.start ?? stamp;
					else if (event.type === "turn/end") slot.end = stamp;
					else if (!slot.start && Number.isSafeInteger(stamp) && stamp > 0) slot.start = stamp;
					if (event.type === "turn/end") ends.set(turn, String(event.data?.reason?.kind ?? "?"));
					times.set(turn, slot);
					const bucket = byTurn.get(turn) ?? [];
					bucket.push(event);
					byTurn.set(turn, bucket);
				}
				const workspace = absoluteWorkspace(snapshot.session?.cwd);
				const tasks = workspace ? (await listTasks(workspace)).filter((task) => task.sessionId === sessionId) : [];
				const userText = new Map();
				let current = 0;
				for (const event of snapshot.events) {
					if (event.type === "turn/start") {
						const turn = Number(event.data?.turn ?? 0);
						if (Number.isSafeInteger(turn) && turn > 0) current = turn;
					} else if (event.type === "user/message" && event.data?.source?.kind === "user") {
						const text = textOfMessage(event.data);
						if (text && current) userText.set(current, text);
					}
				}
				const items = [];
				let mediaTotal = 0;
				let deliverablesTotal = 0;
				// Una tarea puede abarcar varios turnos: su evidencia es la de todos.
				const addItem = async (task, turns) => {
					const list = turns.length ? turns : [];
					const bucket = list.length ? list.flatMap((turn) => byTurn.get(turn) ?? []) : snapshot.events;
					const evidence = await enrichMedia(summarizeEvidence(bucket, { cwd: snapshot.session?.cwd ?? null }));
					const first = list.length ? list[0] : 0;
					const last = list.length ? list[list.length - 1] : 0;
					const reason = task?.closeReason ?? (last ? ends.get(last) : null) ?? null;
					const now = Date.now();
					// Cuánto se trabajó y cuándo fue la última vez: los turnos de la tarea.
					let workedMs = 0;
					let lastWorkedAt = 0;
					for (const turn of list) {
						const slot = times.get(turn) ?? {};
						const start = Number(slot.start ?? 0);
						if (!start) continue;
						const end = Number(slot.end ?? 0) || (turn === latest ? now : start);
						workedMs += Math.max(0, end - start);
						if (end > lastWorkedAt) lastWorkedAt = end;
					}
					const openedAt = Number(times.get(first)?.start ?? 0) || Number(task?.createdAt ?? 0) || now;
					mediaTotal += evidence.media.length;
					deliverablesTotal += evidence.deliverables.length;
					items.push({
						id: task?.id ?? `turn-${first}`,
						// El título lo elige el agente. Si no lo nombró, se dice, no se
						// rellena con el mensaje del usuario.
						title: task?.title ?? `Sin título · turno ${first}`,
						steps: task?.steps ?? [],
						turn: first,
						turns: list,
						request: userText.get(first) ?? "",
						state: task?.state ?? "abierta",
						status: taskState(task, {
							running: list.includes(latest) && !ends.has(latest),
							current: latest,
							ended: Boolean(reason),
						}),
						openMs: Math.max(0, now - openedAt),
						workedMs,
						lastWorkedMs: lastWorkedAt ? Math.max(0, now - lastWorkedAt) : null,
						outcome: task?.outcome ?? "",
						note: task?.note ?? "",
						closeReason: reason ? closeText(reason) : null,
						summary: assistantSummary(bucket),
						media: evidence.media,
						deliverables: evidence.deliverables,
					});
				};
				const withTask = new Set();
				for (const task of tasks) {
					const turns = taskTurns(task);
					if (!turns.length) continue;
					for (const turn of turns) withTask.add(turn);
					await addItem(task, turns);
				}
				// Turnos anteriores al registro automático: se muestran igual, con su
				// evidencia, para que la vista tenga toda la sesión.
				for (const turn of [...byTurn.keys()].sort((a, b) => a - b)) {
					if (withTask.has(turn) || !userText.has(turn)) continue;
					await addItem(null, [turn]);
				}
				for (const task of tasks) {
					if (taskTurns(task).length) continue;
					await addItem(task, []);
				}
				items.sort((a, b) => (a.turn ?? 0) - (b.turn ?? 0));
				sendJson(res, 200, {
					sessionId,
					workspace,
					tasks: items,
					stats: { tasks: items.length, media: mediaTotal, deliverables: deliverablesTotal },
				});
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
		{
			// Reinicia el harness desde la UI. Se programa con --restart-later para
			// que la respuesta llegue antes de que el servidor se caiga.
			path: "/tasks/restart",
			method: "POST",
			handler: async (_req, res) => {
				const child = spawn("dsh-web", ["--restart-later", "2"], { detached: true, stdio: "ignore" });
				child.unref();
				sendJson(res, 200, { ok: true, message: "El harness se reinicia en 2 segundos: recargá cuando vuelva." });
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
