/**
 * Normaliza lo que el agente declara en `task_plan`: títulos cortos y concretos,
 * uno por cada cosa distinta que pidió el usuario en el mismo pedido.
 */

const MAX_TASKS = 8;
const MAX_TITLE = 80;
const MAX_DETAIL = 600;

function clean(value, max) {
	return typeof value === "string" ? value.replace(/\s+/g, " ").trim().slice(0, max) : "";
}

/**
 * @param args - argumentos crudos de la tool, sin confiar en su forma.
 * @returns lista de tareas a registrar, sin títulos vacíos ni repetidos.
 */
export function planTasks(args) {
	const raw = Array.isArray(args?.tasks) ? args.tasks : [];
	const seen = new Set();
	const plan = [];
	for (const item of raw) {
		const title = clean(item?.title, MAX_TITLE);
		if (!title) continue;
		const key = title.toLowerCase();
		if (seen.has(key)) continue;
		seen.add(key);
		plan.push({ title, detail: clean(item?.detail, MAX_DETAIL) });
		if (plan.length >= MAX_TASKS) break;
	}
	return plan;
}

/**
 * Título provisorio cuando el agente todavía no nombró el pedido: primera
 * oración útil, corta, sin relleno de conversación.
 */
export function shortTaskTitle(text) {
	const plain = String(text ?? "")
		.replace(/```[\s\S]*?```/g, " ")
		.replace(/`([^`]*)`/g, "$1")
		.replace(/[*_#>\s]+/g, " ")
		.trim();
	const sentence = plain.split(/(?<=[.!?])\s/)[0] ?? plain;
	const words = sentence.split(" ").filter(Boolean).slice(0, 10);
	return words.join(" ").replace(/[.,;:]+$/, "").slice(0, 72);
}
