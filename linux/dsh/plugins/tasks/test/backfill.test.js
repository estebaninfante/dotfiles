import test from "node:test";
import assert from "node:assert/strict";
import { planBackfill } from "../lib/backfill.js";

const T = 1700000000000;

function turnStart(seq, turn) {
	return { type: "turn/start", seq, time: T, data: { turn } };
}

function userMessage(seq, text, kind = "user") {
	return { type: "user/message", seq, time: T, data: { role: "user", source: { kind }, content: [{ type: "text", text }] } };
}

function turnEnd(seq, turn, reason) {
	return { type: "turn/end", seq, time: T, data: { turn, reason: { kind: reason } } };
}

function planCall(seq, turn, title, detail = "") {
	return { type: "tool/call", seq, time: T, data: { turn, step: 1, callId: `c${seq}`, name: "task_plan", arguments: JSON.stringify({ title, detail }) } };
}

test("un pedido por tarea abierta, con el título del plan y el cierre del turno", () => {
	const plan = planBackfill([
		turnStart(1, 1),
		userMessage(2, "Arreglá el login\nque no guarda la sesión"),
		planCall(3, 1, "Arreglar el login", "La sesión no se guarda"),
		turnEnd(4, 1, "completed"),
		turnStart(5, 2),
		userMessage(6, "Ahora los tests"),
		planCall(7, 2, "Arreglar los tests"),
		turnEnd(8, 2, "error"),
	]);
	assert.equal(plan.length, 2);
	assert.equal(plan[0].turn, 1);
	assert.equal(plan[0].title, "Arreglar el login");
	assert.equal(plan[0].goal, "La sesión no se guarda");
	assert.equal(plan[0].closeReason, "completed");
	assert.equal(plan[1].title, "Arreglar los tests");
	assert.equal(plan[1].closeReason, "error");
});

test("un mensaje suelto sin tarea abierta no genera tarea falsa", () => {
	const plan = planBackfill([
		turnStart(1, 1),
		userMessage(2, "No"),
		turnEnd(3, 1, "completed"),
		userMessage(4, "sí hay IMG 0681"),
	]);
	assert.equal(plan.length, 0);
});

test("una tarea sin título en el plan no existe, y el siguiente plan del turno manda", () => {
	const plan = planBackfill([
		turnStart(1, 1),
		userMessage(2, "pedido"),
		planCall(3, 1, ""),
		planCall(4, 1, "El título bueno"),
		turnEnd(5, 1, "completed"),
	]);
	assert.equal(plan.length, 1);
	assert.equal(plan[0].title, "El título bueno");
});

test("sin plan no hay tarea, aunque el turno tenga mensaje real", () => {
	const plan = planBackfill([turnStart(1, 1), userMessage(2, "runtime", "runtime-context"), turnEnd(3, 1, "completed")]);
	assert.equal(plan.length, 0);
});
