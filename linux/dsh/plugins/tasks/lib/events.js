/**
 * Lectura de los eventos de sesión que importan para tareas: mensajes escritos
 * por el usuario, sesiones raíz (no subagentes), título del pedido y resumen de
 * lo que el agente dijo al cerrar un turno.
 */

/** Texto plano de un mensaje del log (bloques "text"). */
export function textOfMessage(message) {
	if (!message || !Array.isArray(message.content)) return "";
	return message.content
		.filter((part) => part && part.type === "text" && typeof part.text === "string")
		.map((part) => part.text)
		.join("\n")
		.trim();
}

/** Solo sesiones raíz con carpeta: los subagentes no crean tareas. */
export function rootSession(session) {
	const header = session?.header;
	if (!header) return false;
	if (header.origin === "subagent") return false;
	if ((header.delegationDepth ?? 0) > 0) return false;
	return typeof header.cwd === "string" && header.cwd.startsWith("/");
}

/** Primera línea del pedido, como título provisorio de la tarea. */
export function firstLine(text) {
	const line = String(text ?? "").split("\n").find((item) => item.trim() !== "") ?? "";
	return line.trim().slice(0, 120);
}

/** Texto plano: sin marcas de markdown, sin listas, en una sola línea. */
function plainText(text) {
	return String(text ?? "")
		.replace(/```[\s\S]*?```/g, " ")
		.replace(/`([^`]*)`/g, "$1")
		.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
		.replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
		.replace(/[#>*_~]+/g, " ")
		.replace(/\s+/g, " ")
		.trim();
}

/**
 * Resumen corto de lo que el agente dijo al cerrar: el último mensaje del
 * turno, en texto plano y recortado en una oración.
 *
 * @param events - eventos del turno (o de la sesión completa).
 * @param maxLen - largo máximo del resumen.
 */
export function assistantSummary(events, maxLen = 240) {
	let text = "";
	for (const event of Array.isArray(events) ? events : []) {
		if (event.type !== "assistant/message") continue;
		const value = textOfMessage(event.data?.message);
		if (value) text = value;
	}
	const plain = plainText(text);
	if (!plain) return "";
	if (plain.length <= maxLen) return plain;
	const cut = plain.slice(0, maxLen);
	const sentence = cut.match(/^[\s\S]*?[.!?](?=\s|$)/);
	return (sentence ? sentence[0] : cut).trim();
}
