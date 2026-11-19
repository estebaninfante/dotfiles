/**
 * Reconstruye los pedidos de una conversación ya existente: un pedido por turno
 * con el texto que escribió el usuario y cómo cerró el turno. Sirve para traer a
 * Tareas las conversaciones que empezaron antes de que el harness registrara
 * tareas solo.
 */
import { firstLine, textOfMessage } from "./events.js";

/**
 * @param events - log completo de la sesión.
 * @returns pedidos en orden, listos para crear como tareas.
 */
export function planBackfill(events) {
	const requests = new Map();
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
		if (event.type !== "user/message") continue;
		if (event.data?.source?.kind !== "user") continue;
		const text = textOfMessage(event.data);
		if (!text) continue;
		if (!turn) pending = text;
		else if (!requests.has(turn)) requests.set(turn, text);
	}
	return [...requests.entries()]
		.sort((a, b) => a[0] - b[0])
		.map(([order, text]) => {
			const title = firstLine(text) || `Pedido del turno ${order}`;
			return {
				turn: order,
				title,
				goal: "",
				closeReason: ends.get(order) ?? null,
			};
		});
}
