/**
 * Tareas por proyecto. Un solo JSON bajo ~/.dsh/storages; escritura atómica y
 * serializada para que dos pestañas no pisen el archivo.
 *
 * Cada pedido del usuario se registra como tarea del proyecto: `turn` es el
 * turno de la conversación del que salió y `origin` dice quién la creó.
 */
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

const DIR = join(process.env.DSH_HOME ?? join(homedir(), ".dsh"), "storages");
const FILE = join(DIR, "local-tasks.json");
const STATES = new Set(["abierta", "resuelta", "cancelada"]);

/**
 * Turnos de una tarea. Una tarea no es un turno: el pedido que la abre y los
 * mensajes de continuación que la siguen trabajando todos sobre lo mismo.
 */
export function taskTurns(task) {
	if (Array.isArray(task?.turns) && task.turns.length) return task.turns;
	return Number.isSafeInteger(task?.turn) && task.turn > 0 ? [task.turn] : [];
}
const OUTCOMES = new Set(["ok", "parcial", "falló", "abierta", "cancelada"]);

let chain = Promise.resolve();
function serialized(work) {
	const run = chain.then(work, work);
	chain = run.then(
		() => undefined,
		() => undefined,
	);
	return run;
}

async function readDb() {
	try {
		const parsed = JSON.parse(await readFile(FILE, "utf8"));
		if (!parsed || !Array.isArray(parsed.tasks)) return { version: 1, tasks: [] };
		return parsed;
	} catch {
		return { version: 1, tasks: [] };
	}
}

async function writeDb(db) {
	await mkdir(DIR, { recursive: true });
	const tmp = `${FILE}.${process.pid}.tmp`;
	await writeFile(tmp, `${JSON.stringify(db, null, 2)}\n`, "utf8");
	await rename(tmp, FILE);
}

function clean(value, max) {
	return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function order(a, b) {
	if (a.state !== b.state) return a.state === "abierta" ? -1 : 1;
	// Pedidos de una conversación: del más nuevo al más viejo. Lo demás por fecha.
	const turnA = a.turn ?? 0;
	const turnB = b.turn ?? 0;
	if (turnA !== turnB) return turnB - turnA;
	const left = a.state === "resuelta" ? (a.resolvedAt ?? a.updatedAt) : a.createdAt;
	const right = b.state === "resuelta" ? (b.resolvedAt ?? b.updatedAt) : b.createdAt;
	return right - left;
}

export async function listTasks(workspace) {
	const db = await readDb();
	const tasks = workspace ? db.tasks.filter((task) => task.workspace === workspace) : db.tasks;
	return tasks.slice().sort(order);
}

export function createTask(input) {
	return serialized(async () => {
		const db = await readDb();
		const now = Date.now();
		const task = {
			id: randomUUID(),
			workspace: clean(input.workspace, 1024),
			title: clean(input.title, 200),
			goal: clean(input.goal, 2000),
			state: "abierta",
			sessionId: clean(input.sessionId, 120) || null,
			turn: Number.isSafeInteger(input.turn) && input.turn > 0 ? input.turn : null,
			turns: Number.isSafeInteger(input.turn) && input.turn > 0 ? [input.turn] : [],
			origin: typeof input.origin === "string" ? clean(input.origin, 20) : "ui",
			createdAt: now,
			updatedAt: now,
			resolvedAt: null,
			cancelledAt: null,
			closeReason: null,
			closedAt: null,
			outcome: null,
			note: "",
			reviewedAt: null,
		};
		if (!task.workspace || !task.title) throw new Error("workspace y título son obligatorios");
		db.tasks.push(task);
		await writeDb(db);
		return task;
	});
}

export function updateTask(id, patch) {
	return serialized(async () => {
		const db = await readDb();
		const task = db.tasks.find((item) => item.id === id);
		if (!task) throw new Error("tarea no encontrada");
		if (typeof patch.title === "string") task.title = clean(patch.title, 200) || task.title;
		if (typeof patch.goal === "string") task.goal = clean(patch.goal, 2000);
		if (typeof patch.sessionId === "string" && patch.sessionId.trim()) task.sessionId = clean(patch.sessionId, 120);
		if (Number.isSafeInteger(patch.turn) && patch.turn > 0) task.turn = patch.turn;
		if (typeof patch.closeReason === "string" && patch.closeReason.trim()) {
			task.closeReason = clean(patch.closeReason, 40);
			task.closedAt = Number.isSafeInteger(patch.closedAt) ? patch.closedAt : Date.now();
		}
		if (OUTCOMES.has(patch.outcome)) {
			task.outcome = patch.outcome;
			task.reviewedAt = Number.isSafeInteger(patch.reviewedAt) ? patch.reviewedAt : Date.now();
		}
		if (typeof patch.note === "string") task.note = clean(patch.note, 400);
		if (STATES.has(patch.state) && patch.state !== task.state) {
			task.state = patch.state;
			// Cancelada = el usuario detuvo el turno; no es un cierre exitoso.
			task.resolvedAt = patch.state === "resuelta" ? Date.now() : null;
			task.cancelledAt = patch.state === "cancelada" ? Date.now() : null;
		}
		task.updatedAt = Date.now();
		await writeDb(db);
		return task;
	});
}

/** Tarea ligada a una conversación, para saber si el turno ya tiene tarea. */
export async function findSessionTask(sessionId) {
	const db = await readDb();
	return db.tasks.find((task) => task.sessionId === sessionId) ?? null;
}

/** Tarea abierta de la conversación que puede seguir trabajándose. */
export async function findOpenTask(sessionId) {
	const db = await readDb();
	const open = db.tasks
		.filter((task) => task.sessionId === sessionId && task.state === "abierta" && task.outcome !== "ok")
		.sort((a, b) => (b.turn ?? 0) - (a.turn ?? 0));
	return open[0] ?? null;
}

/** Todas las tareas de una conversación, en orden de turno. */
export async function findSessionTasks(sessionId) {
	const db = await readDb();
	return db.tasks.filter((task) => task.sessionId === sessionId).sort((a, b) => (a.turn ?? 0) - (b.turn ?? 0));
}

/** Tarea de un pedido concreto: un turno de la conversación. */
export async function findTurnTask(sessionId, turn) {
	const db = await readDb();
	return db.tasks.find((task) => task.sessionId === sessionId && taskTurns(task).includes(turn)) ?? null;
}

/** Todas las tareas de un pedido: un mismo pedido puede pedir varias cosas. */
export async function findTurnTasks(sessionId, turn) {
	const db = await readDb();
	return db.tasks.filter((task) => task.sessionId === sessionId && taskTurns(task).includes(turn));
}

/** Suma un turno a una tarea abierta: la continuación trabaja la misma tarea. */
export function addTurn(id, turn) {
	return serialized(async () => {
		const db = await readDb();
		const task = db.tasks.find((item) => item.id === id);
		if (!task) return null;
		const turns = taskTurns(task);
		if (!turns.includes(turn)) task.turns = [...turns, turn].sort((a, b) => a - b);
		await writeDb(db);
		return task;
	});
}

/** Une una tarea de continuación en la tarea que venía trabajando. */
export function mergeTasks(intoId, fromId) {
	return serialized(async () => {
		const db = await readDb();
		const into = db.tasks.find((item) => item.id === intoId);
		const from = db.tasks.find((item) => item.id === fromId);
		if (!into || !from || into.id === from.id) return null;
		const turns = [...new Set([...taskTurns(into), ...taskTurns(from)])].sort((a, b) => a - b);
		if (turns.length) {
			into.turns = turns;
			into.turn = turns[0];
		}
		if (!into.outcome && from.outcome) {
			into.outcome = from.outcome;
			into.note = from.note || into.note;
			into.reviewedAt = from.reviewedAt ?? into.reviewedAt;
		}
		into.updatedAt = Date.now();
		db.tasks = db.tasks.filter((item) => item.id !== fromId);
		await writeDb(db);
		return into;
	});
}

/** Tarea recién creada desde la UI que todavía no sabe de qué turno salió. */
export async function adoptTurn(sessionId, turn) {
	return serialized(async () => {
		const db = await readDb();
		const task = db.tasks.find((item) => item.sessionId === sessionId && item.turn == null);
		if (!task) return null;
		task.turn = turn;
		task.updatedAt = Date.now();
		await writeDb(db);
		return task;
	});
}

export function deleteTask(id) {
	return serialized(async () => {
		const db = await readDb();
		const before = db.tasks.length;
		db.tasks = db.tasks.filter((item) => item.id !== id);
		if (db.tasks.length === before) throw new Error("tarea no encontrada");
		await writeDb(db);
		return { ok: true };
	});
}
