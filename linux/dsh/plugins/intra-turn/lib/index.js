/**
 * dsh-local-intra-turn — host half.
 *
 * "Feedforward": antes de que mandes el mensaje, el modelo dice qué va a
 * asumir por vos y qué le falta saber. Una llamada corta, sin escribir nada en
 * la sesión: el resultado solo viaja al panel del cliente.
 *
 * Ruta propia (POST /intra-turn/feedforward) por la misma razón que
 * `side-questions`: la lista de eventos remotos de la app es cerrada y un
 * plugin local no puede declarar uno nuevo. La ruta vive detrás del servidor
 * autenticado y exige un header propio.
 */

const ROUTE = "/intra-turn/feedforward";
const MAX_BODY_BYTES = 64 * 1024;
const MAX_DRAFT_CHARS = 4000;
const MAX_TOKENS = 1500;
const CALL_TIMEOUT_MS = 45_000;
/**
 * Proveedores como opencode Go rechazan llamadas sin id de sesión (lo usan
 * para rutear la caché). Un id propio y fijo: no se mezcla con la caché de la
 * conversación y las llamadas comparten el prefijo del system prompt.
 */
const ROUTING_SESSION_ID = "intra-turn-feedforward";

const SYSTEM = [
	"Sos el copiloto de alguien que está escribiendo un pedido a un agente de IA.",
	"Tu trabajo NO es responder el pedido: es mostrar, antes de que lo mande, qué va a interpretar y qué le falta saber, anclado a las palabras exactas del borrador.",
	"Devolvé SOLO JSON válido, sin markdown ni texto alrededor, con esta forma:",
	'{"assumptions":[{"quote":"...","emoji":"🗺️","label":"...","value":"...","options":["...","..."]}],"missing":[{"quote":"...","label":"...","options":["...","..."]}]}',
	"quote: copiá LITERAL de 1 a 4 palabras del borrador (mismas letras, mayúsculas y tildes) que disparan esa interpretación o pregunta. Nunca inventes ni parafrasees el quote.",
	"assumptions: 1 a 3 cosas que el agente va a decidir solo y que podrían estar mal (alcance, formato, profundidad, destino, a quién va dirigido). Cada una con un quote distinto.",
	"label: el aspecto, máximo 4 palabras (ej. 'Formato', 'Destino', 'Nivel de detalle'). value: lo que va a asumir, máximo 6 palabras. options: 2 o 3 alternativas reales, distintas de value, máximo 5 palabras cada una. emoji: uno solo que represente el aspecto.",
	"missing: 0 a 3 datos que faltan y que cambiarían la respuesta. label es la pregunta corta (ej. '¿Qué edad tienen?'), options 2 a 5 respuestas cortas. Varias preguntas pueden compartir el mismo quote.",
	"Escribí label, value y options en el idioma del borrador. Prohibido explicar, saludar o agregar claves. Si el pedido ya es preciso, devolvé listas vacías."
].join(" ");

function readJsonBody(req) {
	return new Promise((resolve, reject) => {
		const chunks = [];
		let size = 0;
		req.on("data", (chunk) => {
			size += chunk.length;
			if (size > MAX_BODY_BYTES) {
				reject(new Error("body too large"));
				req.destroy();
				return;
			}
			chunks.push(chunk);
		});
		req.on("end", () => {
			try {
				resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
			} catch (error) {
				reject(new Error("invalid JSON body", { cause: error }));
			}
		});
		req.on("error", reject);
	});
}

function sendJson(res, status, value) {
	const body = JSON.stringify(value);
	res.writeHead(status, {
		"content-type": "application/json; charset=utf-8",
		"content-length": String(Buffer.byteLength(body)),
		"cache-control": "no-store"
	});
	res.end(body);
}

function pickTarget(config) {
	if (typeof config?.provider !== "string" || typeof config?.model !== "string") return void 0;
	return {
		provider: config.provider,
		model: config.model,
		...typeof config.reasoningEffort === "string" ? { reasoningEffort: config.reasoningEffort } : {}
	};
}

/**
 * Provider/modelo de la sesión que está mirando el usuario; si la sesión es
 * nueva (todavía sin request header), el modelo por defecto del perfil, que es
 * el que va a usar el primer mensaje.
 */
function resolveTarget(ctx, sessionId) {
	const session = typeof sessionId === "string" && sessionId.length > 0 ? ctx.sessions?.get?.(sessionId) : void 0;
	const fromSession = pickTarget(session?.requestHeader?.()?.config);
	if (fromSession !== void 0) return fromSession;
	try {
		return pickTarget(ctx.agentDefaultModel?.currentSelection?.());
	} catch {
		return void 0;
	}
}

async function collectText(llm, options) {
	let text = "";
	let failure;
	for await (const chunk of llm.stream(options)) {
		if (chunk.type === "text-delta") text += chunk.text;
		else if (chunk.type === "finish" && chunk.reason !== void 0 && chunk.reason.kind !== "stop" && chunk.reason.kind !== "max-tokens") failure = chunk.reason;
	}
	if (failure !== void 0) throw new Error(`model finished with ${failure.kind}${typeof failure.failure?.message === "string" ? `: ${failure.failure.message}` : ""}`);
	return text.trim();
}

/**
 * Ubica `quote` en el borrador y devuelve la subcadena tal cual está escrita.
 * Primero exacto; después sin distinguir mayúsculas ni espacios repetidos (el
 * modelo a veces normaliza). Si no aparece, no hay anclaje: undefined.
 */
function locateQuote(draft, quote) {
	if (typeof quote !== "string") return void 0;
	const wanted = quote.replace(/\s+/g, " ").trim().replace(/^["“”'«»]+|["“”'«».,;:]+$/g, "");
	if (wanted.length === 0 || wanted.length > 80) return void 0;
	if (draft.includes(wanted)) return wanted;
	const pattern = wanted
		.split(" ")
		.map((word) => word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
		.join("\\s+");
	const match = new RegExp(pattern, "iu").exec(draft);
	return match === null ? void 0 : match[0];
}

const cleanText = (value, max) => (typeof value === "string" ? value.replace(/\s+/g, " ").trim().slice(0, max) : "");
const cleanOptions = (list, max, exclude) =>
	(Array.isArray(list) ? list : [])
		.map((option) => cleanText(option, 48))
		.filter((option, index, all) => option.length > 0 && option !== exclude && all.indexOf(option) === index)
		.slice(0, max);

/** El modelo a veces envuelve el JSON en ```json … ``` o agrega una frase. */
function parsePayload(text, draft) {
	const empty = { assumptions: [], missing: [] };
	const cleaned = text
		.replace(/^\s*```(?:json)?/i, "")
		.replace(/```\s*$/i, "")
		.trim();
	const start = cleaned.indexOf("{");
	const end = cleaned.lastIndexOf("}");
	if (start < 0 || end <= start) return empty;
	let parsed;
	try {
		parsed = JSON.parse(cleaned.slice(start, end + 1));
	} catch {
		return empty;
	}
	const items = (list) => (Array.isArray(list) ? list : []).filter((item) => item !== null && typeof item === "object");
	// Sin anclaje en el texto no se muestra: la UI vive pegada a las palabras.
	const assumptions = items(parsed.assumptions)
		.map((item) => {
			const quote = locateQuote(draft, item.quote);
			const label = cleanText(item.label, 60);
			const value = cleanText(item.value, 120);
			if (quote === void 0 || !label || !value) return null;
			const emoji = cleanText(item.emoji, 8);
			return { quote, label, value, options: cleanOptions(item.options, 3, value), ...(emoji ? { emoji } : {}) };
		})
		.filter((item) => item !== null)
		.slice(0, 3);
	const missing = items(parsed.missing)
		.map((item) => {
			const quote = locateQuote(draft, item.quote);
			const label = cleanText(item.label, 80);
			if (quote === void 0 || !label) return null;
			return { quote, label, options: cleanOptions(item.options, 5) };
		})
		.filter((item) => item !== null)
		.slice(0, 3);
	return { assumptions, missing };
}

export const inject = ["webServer", "llm", "sessions", "agentDefaultModel"];

export function apply(ctx) {
	const handler = async (req, res) => {
		if (req.method !== "POST") {
			sendJson(res, 405, { error: "method-not-allowed" });
			return;
		}
		if (req.headers["x-dsh-intra-turn"] !== "1") {
			sendJson(res, 403, { error: "forbidden" });
			return;
		}
		let payload;
		try {
			payload = await readJsonBody(req);
		} catch (error) {
			sendJson(res, 400, { error: "bad-request" });
			return;
		}
		const draft = typeof payload?.draft === "string" ? payload.draft.slice(0, MAX_DRAFT_CHARS).trim() : "";
		if (draft.length < 8) {
			sendJson(res, 200, { assumptions: [], missing: [] });
			return;
		}
		const target = resolveTarget(ctx, payload?.sessionId);
		if (target === void 0) {
			sendJson(res, 409, { error: "no-model", message: "No hay modelo: ni la sesión ni el perfil eligieron uno." });
			return;
		}
		try {
			const text = await collectText(ctx.llm, {
				provider: target.provider,
				model: target.model,
				...target.reasoningEffort === void 0 ? {} : { reasoningEffort: target.reasoningEffort },
				system: SYSTEM,
				messages: [{ role: "user", content: [{ type: "text", text: draft }] }],
				maxTokens: MAX_TOKENS,
				temperature: 0.2,
				sessionId: ROUTING_SESSION_ID,
				signal: AbortSignal.timeout(CALL_TIMEOUT_MS)
			});
			sendJson(res, 200, parsePayload(text, draft));
		} catch (error) {
			sendJson(res, 500, {
				error: "llm-failed",
				message: error instanceof Error ? error.message : String(error)
			});
		}
	};

	ctx.effect(() => ctx.webServer.register({ kind: "exact", path: ROUTE, handler }), "intra-turn: route");
}
