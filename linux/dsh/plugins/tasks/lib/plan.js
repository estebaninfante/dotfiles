/**
 * Normaliza lo que el agente declara en `task_plan`: UNA tarea por pedido, con
 * sus pasos adentro. La tarea es lo que pidió el usuario; los pasos son lo que
 * hay que hacer para cumplirlo, no tareas aparte.
 */

const MAX_STEPS = 12;
const MAX_TITLE = 80;
const MAX_DETAIL = 600;

function clean(value, max) {
	return typeof value === "string" ? value.replace(/\s+/g, " ").trim().slice(0, max) : "";
}

/**
 * @param args - argumentos crudos de la tool, sin confiar en su forma.
 * @returns la tarea del pedido con sus pasos, o null si no hay título.
 */
export function planTask(args) {
	const steps = Array.isArray(args?.steps) ? args.steps : [];
	const seen = new Set();
	const list = [];
	for (const step of steps) {
		const title = clean(typeof step === "string" ? step : step?.title, MAX_TITLE);
		if (!title) continue;
		const key = title.toLowerCase();
		if (seen.has(key)) continue;
		seen.add(key);
		list.push(title);
		if (list.length >= MAX_STEPS) break;
	}
	const title = clean(args?.title, MAX_TITLE);
	if (!title) return null;
	return { title, detail: clean(args?.detail, MAX_DETAIL), steps: list };
}

/**
 * Compatibilidad: si el agente todavía manda varias entradas, la primera es la
 * tarea y el resto son sus pasos.
 */
export function planTasks(args) {
	const raw = Array.isArray(args?.tasks) ? args.tasks : [];
	if (!raw.length) return planTask(args) ? [planTask(args)] : [];
	const task = planTask({ title: raw[0]?.title, detail: raw[0]?.detail, steps: raw.slice(1) });
	return task ? [task] : [];
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

// Mensajes que no piden trabajo nuevo: siguen la tarea que ya está abierta.
const CONTINUATION_WORDS = new Set([
	"continue",
	"continua",
	"continuá",
	"continuar",
	"segui",
	"seguí",
	"sigue",
	"seguir",
	"dale",
	"ok",
	"okay",
	"oka",
	"listo",
	"gracias",
	"perfecto",
	"bien",
	"vamos",
	"adelante",
	"procede",
	"procedé",
	"hacelo",
	"hazlo",
	"go",
	"next",
	"si",
	"sí",
	"yes",
	"ahora",
	"mira",
	"y",
]);

/**
 * ¿El mensaje es una continuación del trabajo en curso en vez de un pedido
 * nuevo? Un "continue" no es una tarea: es el mismo trabajo que sigue.
 */
export function isContinuation(text) {
	const plain = String(text ?? "")
		.replace(/```[\s\S]*?```/g, " ")
		.replace(/[`*_#>]/g, " ")
		.replace(/\s+/g, " ")
		.trim()
		.toLowerCase();
	if (!plain) return true;
	const words = plain
		.replace(/[.,;:!?¡¿"'()…]/g, " ")
		.split(" ")
		.filter(Boolean);
	if (!words.length) return true;
	if (words.every((word) => CONTINUATION_WORDS.has(word))) return true;
	return words.length <= 3 && CONTINUATION_WORDS.has(words[0]);
}
