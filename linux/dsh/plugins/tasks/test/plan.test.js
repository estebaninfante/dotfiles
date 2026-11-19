import test from "node:test";
import assert from "node:assert/strict";
import { isContinuation, planTasks } from "../lib/plan.js";

test("un pedido es una tarea, con sus pasos adentro", () => {
	const plan = planTasks({
		title: "  Revisar   el modo llamada ",
		detail: "Que el input y la barra se transformen.",
		steps: [{ title: "Ver el modal actual" }, { title: "Rediseñar la barra" }, { title: "Probar en pantalla" }],
	});
	assert.equal(plan.length, 1);
	assert.equal(plan[0].title, "Revisar el modo llamada");
	assert.equal(plan[0].detail, "Que el input y la barra se transformen.");
	assert.deepEqual(plan[0].steps, ["Ver el modal actual", "Rediseñar la barra", "Probar en pantalla"]);
});

test("si manda varias entradas, la primera es la tarea y el resto pasos", () => {
	const plan = planTasks({
		tasks: [{ title: "Arreglar el login" }, { title: "Revisar tests" }, { title: "Revisar tests" }, { title: "" }],
	});
	assert.equal(plan.length, 1);
	assert.equal(plan[0].title, "Arreglar el login");
	assert.deepEqual(plan[0].steps, ["Revisar tests"]);
});

test("los pasos se recortan a un máximo y no se repiten", () => {
	const plan = planTasks({
		title: "Tarea grande",
		steps: Array.from({ length: 20 }, (_, index) => ({ title: `Paso ${index % 15}` })),
	});
	assert.equal(plan[0].steps.length, 12);
	assert.equal(new Set(plan[0].steps).size, 12);
});

test("sin argumentos válidos no inventa tareas", () => {
	assert.deepEqual(planTasks(undefined), []);
	assert.deepEqual(planTasks({ tasks: "no" }), []);
	assert.deepEqual(planTasks({ tasks: [{ title: "   " }] }), []);
	assert.deepEqual(planTasks({ steps: [{ title: "Paso sin título de tarea" }] }), []);
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
