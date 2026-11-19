import test from "node:test";
import assert from "node:assert/strict";
import { planTasks } from "../lib/plan.js";

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
