import test from "node:test";
import assert from "node:assert/strict";
import { Readable } from "node:stream";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Cada corrida escribe en su propia carpeta: nunca toca ~/.dsh de verdad.
const HOME = await mkdtemp(join(tmpdir(), "dsh-tasks-test-"));
process.env.DSH_HOME = HOME;

const attach = await import("../lib/attach.js");
const store = await import("../lib/store.js");

test.after(() => rm(HOME, { recursive: true, force: true }));

test("el nombre del archivo pierde carpetas y caracteres raros", () => {
	assert.equal(attach.safeName("../../etc/passwd"), "passwd");
	assert.equal(attach.safeName("/home/eztvn/Descargas/foto 1.png"), "foto 1.png");
	assert.equal(attach.safeName("a<b>c|d?.png"), "a-b-c-d-.png");
	assert.equal(attach.safeName(""), "archivo");
	assert.equal(attach.safeName("   "), "archivo");
});

test("cada extensión sabe si es imagen, video, audio o archivo", () => {
	assert.equal(attach.kindOf("captura.PNG"), "image");
	assert.equal(attach.kindOf("demo.mp4"), "video");
	assert.equal(attach.kindOf("voz.ogg"), "audio");
	assert.equal(attach.kindOf("trace.har"), "file");
	assert.equal(attach.mimeOf("captura.png"), "image/png");
	assert.equal(attach.mimeOf("raro.xyz"), "application/octet-stream");
});

test("un archivo subido queda en la carpeta de la tarea, con sus bytes", async () => {
	const task = await store.createTask({ workspace: "/home/eztvn", title: "Con archivos", request: "mirá la captura" });
	const bytes = Buffer.from("hola evidencia");
	const file = await attach.saveUpload(task.id, "captura.png", Readable.from([bytes]));
	assert.equal(file.name, "captura.png");
	assert.equal(file.size, bytes.length);
	assert.equal(file.kind, "image");
	assert.equal(file.path, join(HOME, "tasks", task.id, "captura.png"));
	assert.deepEqual(await readFile(file.path), bytes);
	await rm(HOME, { recursive: true, force: true });
});

test("dos archivos con el mismo nombre no se pisan", async () => {
	const task = await store.createTask({ workspace: "/home/eztvn", title: "Dos iguales" });
	const one = await attach.saveUpload(task.id, "log.txt", Readable.from([Buffer.from("uno")]));
	const two = await attach.saveUpload(task.id, "log.txt", Readable.from([Buffer.from("dos")]));
	assert.equal(one.name, "log.txt");
	assert.equal(two.name, "log (2).txt");
	assert.equal(await readFile(one.path, "utf8"), "uno");
	assert.equal(await readFile(two.path, "utf8"), "dos");
});

test("lo que está fuera de la carpeta de tareas no se sirve", () => {
	assert.equal(attach.attachmentInfo("/etc/passwd"), null);
	assert.equal(attach.attachmentInfo("relative/path.png"), null);
	const inside = join(HOME, "tasks", "abc", "foto.png");
	assert.equal(attach.attachmentInfo(inside)?.kind, "image");
});

test("la tarea guarda el pedido y sus adjuntos, y los pierde al borrarse", async () => {
	const task = await store.createTask({ workspace: "/home/eztvn", title: "Pedido guardado", request: "arreglá el login" });
	assert.equal(task.request, "arreglá el login");
	assert.deepEqual(task.attachments, []);

	const file = await attach.saveUpload(task.id, "error.png", Readable.from([Buffer.from("png")]));
	const withFile = await store.attachFile(task.id, file);
	assert.equal(withFile.attachments.length, 1);
	assert.equal(withFile.attachments[0].path, file.path);

	const edited = await store.updateTask(task.id, { request: "mejorá el login", launchedAt: 123 });
	assert.equal(edited.request, "mejorá el login");
	assert.equal(edited.launchedAt, 123);

	const detached = await store.detachFile(task.id, file.path);
	assert.deepEqual(detached.attachments, []);

	const again = await store.attachFile(task.id, file);
	assert.equal(again.attachments.length, 1);
	await store.deleteTask(task.id);
	assert.equal(existsSync(join(HOME, "tasks", task.id)), false);
});

test("sin título ni pedido no hay tarea", async () => {
	await assert.rejects(() => store.createTask({ workspace: "/home/eztvn", title: "" }), /obligatorios/);
	await assert.rejects(() => store.createTask({ workspace: "", title: "algo" }), /obligatorios/);
});
