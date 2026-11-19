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

test("arma un pedido por turno con el texto que escribió el usuario", () => {
	const plan = planBackfill([
		turnStart(1, 1),
		userMessage(2, "Arreglá el login\nque no guarda la sesión"),
		userMessage(3, "<system-reminder> contexto interno", "runtime-context"),
		turnEnd(4, 1, "completed"),
		turnStart(5, 2),
		userMessage(6, "Ahora los tests"),
		turnEnd(7, 2, "error"),
	]);
	assert.equal(plan.length, 2);
	assert.equal(plan[0].turn, 1);
	assert.equal(plan[0].title, "Arreglá el login");
	assert.equal(plan[0].goal, "");
	assert.equal(plan[0].closeReason, "completed");
	assert.equal(plan[1].turn, 2);
	assert.equal(plan[1].closeReason, "error");
});

test("un turno sin mensaje real del usuario no genera tarea", () => {
	const plan = planBackfill([turnStart(1, 1), userMessage(2, "runtime", "runtime-context"), turnEnd(3, 1, "completed")]);
	assert.equal(plan.length, 0);
});

test("un mensaje llega antes del turn/start y se asigna al turno siguiente", () => {
	const plan = planBackfill([userMessage(1, "pedido suelto"), turnStart(2, 3), turnEnd(3, 3, "completed")]);
	assert.equal(plan.length, 1);
	assert.equal(plan[0].turn, 3);
});
