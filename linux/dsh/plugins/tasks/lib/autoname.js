/**
 * Nombre de respaldo para una tarea que el agente no nombró. No se inventa
 * semántica: se usa lo que el propio agente escribió al cerrar el turno, podado
 * hasta quedar como título. Si no hay nada usable, la tarea queda "sin nombre"
 * y la vista muestra el pedido abajo, nunca como título.
 */

const MAX_TITLE = 72;
const MAX_WORDS = 9;

const FILLERS = /^(listo|lista|hecho|hecha|ya está|ya esta|quedó|quedo|ahora|verificado|verifiqué|verifique|terminado|terminé|termine|encontré|encontre|tenés razón|tenes razon|dos cosas|una cosa|sí|si)[\s,.:;—-]+/i;

/** Texto plano de un mensaje del agente. */
function plain(value) {
	return String(value ?? "")
		.replace(/```[\s\S]*?```/g, " ")
		.replace(/`([^`]*)`/g, "$1")
		.replace(/[*_#>]+/g, " ")
		.replace(/\s+/g, " ")
		.trim();
}

/**
 * @param summary - lo que el agente dijo al cerrar el turno.
 * @returns un título corto o "" si no hay nada que sirva.
 */
export function titleFromSummary(summary) {
	let text = plain(summary);
	if (!text) return "";
	// Se prueba con la primera oración, después con el texto completo.
	const sentence = text.split(/(?<=[.!?])\s/)[0] ?? text;
	text = sentence;
	for (let pass = 0; pass < 3; pass += 1) {
		const stripped = text.replace(FILLERS, "").trim();
		if (stripped === text) break;
		text = stripped;
	}
	text = text.replace(/^(el|la|los|las|un|una)\s+/i, (match) => match);
	const words = text
		.replace(/[.;:!?]+$/g, "")
		.split(" ")
		.filter(Boolean)
		.slice(0, MAX_WORDS);
	const title = words.join(" ").trim();
	if (!title || title.length < 8) return "";
	return title.charAt(0).toUpperCase() + title.slice(1, MAX_TITLE);
}
