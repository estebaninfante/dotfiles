import test from "node:test";
import assert from "node:assert/strict";
import { assistantSummary } from "../lib/events.js";

const T = 1700000000000;

function assistant(seq, parts) {
	return { type: "assistant/message", seq, time: T, data: { turn: 1, message: { role: "assistant", content: parts } } };
}

test("resume lo que dijo el agente al cerrar, en texto plano", () => {
	const events = [
		assistant(1, [{ type: "text", text: "Primer intento." }]),
		assistant(2, [
			{ type: "text", text: "Quedó andando.\n\n- Cambié **el login** en `src/login.ts`.\n- La prueba está en /tmp/shot.png." },
			{ type: "tool-call", id: "c1", name: "bash", arguments: "{}" },
		]),
	];
	assert.equal(assistantSummary(events), "Quedó andando. - Cambié el login en src/login.ts. - La prueba está en /tmp/shot.png.");
});

test("recorta en la primera oración cuando el texto es largo", () => {
	const largo = "Esta es la primera oración que resume el trabajo. Y esta segunda parte es relleno que no debería aparecer.";
	assert.equal(assistantSummary([assistant(1, [{ type: "text", text: largo }])], 60), "Esta es la primera oración que resume el trabajo.");
});

test("sin mensajes del agente no hay resumen", () => {
	assert.equal(assistantSummary([]), "");
	assert.equal(assistantSummary([assistant(1, [{ type: "reasoning", text: "pensando" }])]), "");
});
