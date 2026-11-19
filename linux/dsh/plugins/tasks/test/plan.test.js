import test from "node:test";
import assert from "node:assert/strict";
import { isContinuation, planTasks } from "../lib/plan.js";

test("limpia y deduplica los títulos que declara el agente", () => {
	const plan = planTasks({
		tasks: [
			{ title: "  Arreglar   el login ", detail: "Que la sesión persista." },
			{ title: "arreglar el login" },
			{ title: "" },
			{ title: "Revisar tests" },
		],
	});
	assert.deepEqual(
		plan.map((item) => item.title),
		["Arreglar el login", "Revisar tests"],
	);
	assert.equal(plan[0].detail, "Que la sesión persista.");
});

test("un pedido puede tener varias tareas y se recortan a un máximo", () => {
	const plan = planTasks({ tasks: Array.from({ length: 12 }, (_, index) => ({ title: `Tarea ${index}` })) });
	assert.equal(plan.length, 8);
});

test("sin argumentos válidos no inventa tareas", () => {
	assert.deepEqual(planTasks(undefined), []);
	assert.deepEqual(planTasks({ tasks: "no" }), []);
	assert.deepEqual(planTasks({ tasks: [{ title: "   " }] }), []);
});

test("un 'continue' no es una tarea nueva: sigue el trabajo abierto", () => {
	for (const text of ["continue", "Continue.", "dale", "ok, dale", "seguí", "seguí con eso", "gracias", "  "]) {
		assert.equal(isContinuation(text), true, `debería ser continuación: ${text}`);
	}
});

test("un pedido concreto no es una continuación", () => {
	for (const text of ["arreglá el login", "mira en learnharness, ajusta el gráfico", "por qué no aparece la tarjeta"]) {
		assert.equal(isContinuation(text), false, `no debería ser continuación: ${text}`);
	}
});
