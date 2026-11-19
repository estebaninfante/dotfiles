import test from "node:test";
import assert from "node:assert/strict";
import { taskTurns } from "../lib/store.js";

test("una tarea sabe todos los turnos que trabajó", () => {
	assert.deepEqual(taskTurns({ turn: 4, turns: [4, 5] }), [4, 5]);
});

test("las tareas viejas, con un solo turno, siguen funcionando", () => {
	assert.deepEqual(taskTurns({ turn: 7 }), [7]);
});

test("una tarea suelta no inventa turnos", () => {
	assert.deepEqual(taskTurns({ turn: null }), []);
	assert.deepEqual(taskTurns({}), []);
	assert.deepEqual(taskTurns(null), []);
});
