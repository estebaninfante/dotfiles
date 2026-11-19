import test from "node:test";
import assert from "node:assert/strict";
import { summarizeEvidence } from "../lib/evidence.js";

const T = 1700000000000;

function call(seq, callId, name, args, turn = 1) {
	return { type: "tool/call", seq, time: T, data: { turn, step: 1, callId, name, arguments: JSON.stringify(args) } };
}

function result(seq, callId, text, options = {}) {
	return {
		type: "tool/result",
		seq,
		time: T,
		data: {
			turn: options.turn ?? 1,
			step: 1,
			message: {
				role: "tool",
				source: { kind: "tool", callId },
				toolCallId: callId,
				content: [{ type: "text", text }],
				isError: options.isError === true,
			},
		},
	};
}

function assistant(seq, text, turn = 1) {
	return {
		type: "assistant/message",
		seq,
		time: T,
		data: { turn, step: 1, message: { role: "assistant", content: [{ type: "text", text }] } },
	};
}

function events() {
	return [
		call(1, "c1", "write", { file_path: "/repo/src/login.ts", content: "x" }),
		result(2, "c1", "ok"),
		call(3, "c2", "edit", { file_path: "/repo/src/login.ts", old_string: "a", new_string: "b" }),
		result(4, "c2", "ok"),
		call(5, "c3", "bash", { command: "pnpm run test", description: "Run tests" }),
		result(6, "c3", "all green"),
		call(7, "c4", "bash", { command: "pnpm run build", description: "Build" }),
		result(8, "c4", "error TS2304", { isError: true }),
		call(9, "c5", "bash", { command: "ls nope", description: "List" }),
		result(10, "c5", "ls: nope: No such file\n[exit code: 2]"),
		call(11, "c6", "present", { files: [{ path: "/repo/out/informe.pdf", description: "Informe" }] }),
		result(12, "c6", "presented"),
		assistant(13, "Quedó andando. Cambié /repo/src/login.ts, generé /repo/out/informe.pdf y actualicé /repo/docs/nunca-existio.md."),
		{ type: "turn/end", seq: 14, time: T, data: { turn: 1, reason: { kind: "completed" } } },
		assistant(15, ""),
	];
}

test("cuenta archivos, comandos, tests y entregables", () => {
	const summary = summarizeEvidence(events(), { cwd: "/repo" });
	assert.equal(summary.stats.files, 1, "un archivo, aunque se tocó dos veces");
	assert.equal(summary.files[0].action, "creado");
	assert.equal(summary.stats.commands, 3);
	assert.equal(summary.stats.testsOk, 1);
	assert.equal(summary.stats.testsFail, 1);
	assert.equal(summary.stats.deliverables, 1);
	assert.equal(summary.stats.failures, 2, "build fallido + ls con exit 2");
	assert.equal(summary.tests.length, 2);
});

test("marca el cierre del turno y la última declaración del agente", () => {
	const summary = summarizeEvidence(events());
	assert.equal(summary.end.reason, "completed");
	assert.equal(summary.declaration.turn, 1);
	assert.match(summary.declaration.text, /informe/);
});

test("cruza lo que el agente dijo con lo que realmente tocó", () => {
	const summary = summarizeEvidence(events());
	const touched = summary.claims.find((claim) => claim.claim.endsWith("login.ts"));
	const delivered = summary.claims.find((claim) => claim.claim.endsWith("informe.pdf"));
	const invented = summary.claims.find((claim) => claim.claim.endsWith("nunca-existio.md"));
	assert.ok(touched, "la ruta tocada aparece en los cruces");
	assert.equal(touched.verified, true);
	assert.ok(delivered, "el entregable nombrado también se cruza");
	assert.equal(delivered.verified, true);
	assert.ok(invented, "una ruta inventada se marca");
	assert.equal(invented.verified, false);
});

test("una sesión vacía no inventa evidencia", () => {
	const summary = summarizeEvidence([], {});
	assert.equal(summary.stats.files, 0);
	assert.equal(summary.stats.commands, 0);
	assert.equal(summary.declaration, null);
	assert.equal(summary.end, null);
});

test("las imágenes capturadas o entregadas son prueba visual", () => {
	const list = [
		call(1, "m1", "bash", { command: "pantalla-agente capturar /tmp/prueba-login.png", description: "Capturar login" }),
		result(2, "m1", "ok"),
		call(3, "m2", "read_image", { path: "/tmp/prueba-login.png" }),
		result(4, "m2", "una imagen de 1440x900"),
		call(5, "m3", "present", { files: [{ path: "/repo/out/demo.mp4", description: "Demo" }] }),
		result(6, "m3", "presented"),
	];
	const summary = summarizeEvidence(list);
	assert.equal(summary.stats.media, 2);
	const image = summary.media.find((item) => item.path.endsWith("prueba-login.png"));
	const video = summary.media.find((item) => item.path.endsWith("demo.mp4"));
	assert.equal(image.kind, "imagen");
	assert.equal(image.source, "adjunto");
	assert.equal(image.label, "prueba-login.png");
	assert.equal(video.kind, "video");
	assert.equal(video.source, "entregable");
});

test("un turno filtrado deja solo la evidencia de ese pedido", () => {
	const list = [
		call(1, "a1", "write", { file_path: "/repo/a.ts", content: "x" }, 1),
		result(2, "a1", "ok", { turn: 1 }),
		call(3, "b1", "bash", { command: "pnpm test", description: "Tests" }, 2),
		result(4, "b1", "ok", { turn: 2 }),
		assistant(5, "listo", 1),
		{ type: "turn/end", seq: 6, time: T, data: { turn: 1, reason: { kind: "completed" } } },
		assistant(7, "listo también", 2),
		{ type: "turn/end", seq: 8, time: T, data: { turn: 2, reason: { kind: "completed" } } },
	];
	const turn2 = summarizeEvidence(list.filter((event) => Number(event.data?.turn) === 2));
	assert.equal(turn2.stats.files, 0);
	assert.equal(turn2.stats.commands, 1);
	assert.equal(turn2.stats.testsOk, 1);
	assert.equal(turn2.declaration.text, "listo también");
});
