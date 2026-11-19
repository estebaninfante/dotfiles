/**
 * Lectura de los eventos de sesión que importan para tareas: mensajes escritos
 * por el usuario, sesiones raíz (no subagentes) y título del pedido.
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

/** Primera línea del pedido, como título de la tarea. */
export function firstLine(text) {
	const line = String(text ?? "").split("\n").find((item) => item.trim() !== "") ?? "";
	return line.trim().slice(0, 120);
}
