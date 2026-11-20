/**
 * Reconstruye los pedidos de una conversación ya existente, pero solo los que
 * fueron tareas de verdad: un turno cuenta si el agente abrió una tarea con
 * `task_plan`. Un mensaje suelto de una conversación vieja no es una tarea.
 * El título sale del plan; el texto del usuario solo rellena cuando falta.
 */
import { firstLine, textOfMessage } from "./events.js";
import { shortTaskTitle } from "./plan.js";

/** Título y objetivo declarados por el agente en `task_plan`. */
function planOf(event) {
	const raw = event?.data?.arguments;
	if (typeof raw !== "string" || !raw.trim()) return null;
	try {
		const args = JSON.parse(raw);
		const title = String(args?.title ?? args?.tasks?.[0]?.title ?? "").trim();
		if (!title) return null;
		return { title: title.slice(0, 80), goal: String(args?.detail ?? "").trim().slice(0, 600) };
	} catch {
		return null;
	}
}

/**
 * @param events - log completo de la sesión.
 * @returns pedidos en orden, listos para crear como tareas.
 */
export function planBackfill(events) {
	const requests = new Map();
	const plans = new Map();
	const ends = new Map();
	let turn = 0;
	let pending = "";
	for (const event of Array.isArray(events) ? events : []) {
		if (event.type === "turn/start") {
			const value = Number(event.data?.turn ?? 0);
			if (Number.isSafeInteger(value) && value > 0) {
				turn = value;
				if (pending && !requests.has(turn)) {
					requests.set(turn, pending);
					pending = "";
				}
			}
			continue;
		}
		if (event.type === "turn/end") {
			const value = Number(event.data?.turn ?? turn);
			const reason = String(event.data?.reason?.kind ?? "");
			if (Number.isSafeInteger(value) && value > 0 && reason) ends.set(value, reason);
			continue;
		}
		if (event.type === "tool/call" && event.data?.name === "task_plan") {
			const at = Number(event.data?.turn ?? turn);
			const plan = planOf(event);
			if (plan && Number.isSafeInteger(at) && at > 0 && !plans.has(at)) plans.set(at, plan);
			continue;
		}
		if (event.type !== "user/message") continue;
		if (event.data?.source?.kind !== "user") continue;
		const text = textOfMessage(event.data);
		if (!text) continue;
		if (!turn) pending = text;
		else if (!requests.has(turn)) requests.set(turn, text);
	}
	return [...plans.entries()]
		.sort((a, b) => a[0] - b[0])
		.map(([order, plan]) => {
			const text = requests.get(order) ?? "";
			const title = plan.title || shortTaskTitle(text) || firstLine(text) || `Pedido del turno ${order}`;
			return {
				turn: order,
				title,
				goal: plan.goal,
				closeReason: ends.get(order) ?? null,
			};
		});
}
