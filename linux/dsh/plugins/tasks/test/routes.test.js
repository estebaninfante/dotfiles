/**
 * Las rutas de tareas servidas de verdad: create, upload en crudo y file.
 * Levanta el webServer falso sobre las rutas del plugin y le habla por HTTP.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";

const HOME = await mkdtemp(join(tmpdir(), "dsh-tasks-routes-"));
process.env.DSH_HOME = HOME;

const { registerRoutes } = await import("../lib/routes.js");

const handlers = new Map();
const ctx = {
	effect: (fn) => fn(),
	webServer: { register: ({ path, handler }) => handlers.set(path, handler) },
	sessionQuery: { readSession: async () => ({ events: [], session: null }) },
};
const live = { currentTurn: new Map(), turnEnds: new Map(), running: new Set(), planned: new Map(), denials: new Map(), inflight: new Map(), requestText: new Map(), continuation: new Map() };
registerRoutes(ctx, live);

const server = createServer((req, res) => {
	const { pathname } = new URL(req.url ?? "/", "http://127.0.0.1");
	const handler = handlers.get(pathname);
	if (!handler) {
		res.writeHead(404, { "content-type": "application/json" }).end('{"error":"no-route"}');
		return;
	}
	handler(req, res);
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const base = `http://127.0.0.1:${server.address().port}`;

test.after(async () => {
	await new Promise((done) => server.close(done));
	await rm(HOME, { recursive: true, force: true });
});

const post = (path, body, headers = {}) =>
	fetch(`${base}${path}`, {
		method: "POST",
		headers: { "content-type": "application/json", "x-dsh-tasks": "1", ...headers },
		body: typeof body === "string" || body instanceof Uint8Array || body?.pipe ? body : JSON.stringify(body),
	});

test("crear una tarea guarda el pedido y devuelve su id", async () => {
	const response = await post("/tasks/create", { workspace: "/home/eztvn", request: "arreglá el login de la app", title: "" });
	assert.equal(response.status, 200);
	const { task } = await response.json();
	assert.ok(task.id);
	assert.equal(task.request, "arreglá el login de la app");
	// Sin título se usa la primera línea del mensaje: la tarea es el mensaje.
	assert.equal(task.title, "arreglá el login de la app");
	assert.deepEqual(task.attachments, []);
});

test("subir un archivo en crudo lo deja en la tarea y se puede leer tal cual", async () => {
	const created = await (await post("/tasks/create", { workspace: "/home/eztvn", request: "mirá esta captura" })).json();
	const taskId = created.task.id;
	const bytes = Buffer.alloc(3 * 1024 * 1024, 7);
	const uploaded = await post(`/tasks/upload?task=${taskId}&name=${encodeURIComponent("captura.png")}`, bytes, { "content-type": "image/png" });
	assert.equal(uploaded.status, 200);
	const { attachment, task } = await uploaded.json();
	assert.equal(attachment.size, bytes.length);
	assert.equal(attachment.kind, "image");
	assert.equal(task.attachments.length, 1);

	const served = await fetch(`${base}/tasks/file?path=${encodeURIComponent(attachment.path)}`);
	assert.equal(served.status, 200);
	assert.equal(served.headers.get("content-type"), "image/png");
	assert.equal(served.headers.get("content-length"), String(bytes.length));
	const back = Buffer.from(await served.arrayBuffer());
	assert.equal(back.length, bytes.length);
	assert.deepEqual(back, bytes);
});

test("un archivo de otro lado no se sirve, y un POST sin la cabecera se rechaza", async () => {
	const denied = await fetch(`${base}/tasks/file?path=${encodeURIComponent("/etc/passwd")}`);
	assert.equal(denied.status, 400);
	const sinCabecera = await fetch(`${base}/tasks/create`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ workspace: "/home/eztvn", request: "x" }) });
	assert.equal(sinCabecera.status, 403);
});

test("el desglose de workspaces trae la carpeta del home", async () => {
	const response = await fetch(`${base}/tasks/workspaces`);
	const payload = await response.json();
	assert.equal(payload.home, homedir());
	assert.ok(Array.isArray(payload.workspaces));
});

test("sin nombre ni tarea la subida no inventa nada", async () => {
	const missingTask = await post("/tasks/upload?name=x.png", Buffer.from("x"), { "content-type": "image/png" });
	assert.equal(missingTask.status, 400);
	const missingId = await post("/tasks/upload?task=no-existe&name=x.png", Buffer.from("x"), { "content-type": "image/png" });
	assert.equal(missingId.status, 404);
});

test("borrar la tarea se lleva sus archivos", async () => {
	const created = await (await post("/tasks/create", { workspace: "/home/eztvn", request: "con archivo" })).json();
	const taskId = created.task.id;
	const { attachment } = await (await post(`/tasks/upload?task=${taskId}&name=${encodeURIComponent("log.txt")}`, Buffer.from("hola"), { "content-type": "text/plain" })).json();
	assert.equal(await readFile(attachment.path, "utf8"), "hola");
	const removed = await post("/tasks/delete", { id: taskId });
	assert.equal(removed.status, 200);
	await assert.rejects(() => readFile(attachment.path, "utf8"));
});
