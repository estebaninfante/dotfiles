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
const MAX_TOKENS = 500;
const CALL_TIMEOUT_MS = 45_000;
/**
 * Proveedores como opencode Go rechazan llamadas sin id de sesión (lo usan
 * para rutear la caché). Un id propio y fijo: no se mezcla con la caché de la
 * conversación y las llamadas comparten el prefijo del system prompt.
 */
const ROUTING_SESSION_ID = "intra-turn-feedforward";

const SYSTEM = [
	"Sos el copiloto de alguien que está escribiendo un pedido a un agente de IA.",
	"Tu trabajo NO es responder el pedido: es mostrar, antes de que lo mande, qué va a asumir por su cuenta.",
	"Devolvé SOLO JSON válido, sin markdown ni texto alrededor, con esta forma:",
	'{"assumptions":[{"label":"...","value":"..."}],"missing":[{"label":"...","options":["...","..."]}]}',
	"assumptions: 1 a 3 cosas que el agente va a decidir solo y que podrían estar mal (idioma, alcance, formato, profundidad, a quién va dirigido).",
	"missing: 0 a 3 datos que faltan y que cambiarían la respuesta (con 2 a 4 opciones cortas cada uno).",
	"label: máximo 6 palabras, en español, concreto. value: la suposición, máximo 8 palabras.",
	"Prohibido explicar, saludar o agregar claves. Si el pedido ya es preciso, devolvé listas vacías."
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

/** El modelo a veces envuelve el JSON en ```json … ``` o agrega una frase. */
function parsePayload(text) {
	const cleaned = text
		.replace(/^\s*```(?:json)?/i, "")
		.replace(/```\s*$/i, "")
		.trim();
	const start = cleaned.indexOf("{");
	const end = cleaned.lastIndexOf("}");
	if (start < 0 || end <= start) return { assumptions: [], missing: [] };
	let parsed;
	try {
		parsed = JSON.parse(cleaned.slice(start, end + 1));
	} catch {
		return { assumptions: [], missing: [] };
	}
	const clean = (list, withOptions) =>
		(Array.isArray(list) ? list : [])
			.map((item) => {
				if (item === null || typeof item !== "object") return null;
				const label = typeof item.label === "string" ? item.label.trim().slice(0, 60) : "";
				const value = typeof item.value === "string" ? item.value.trim().slice(0, 120) : "";
				const options = withOptions && Array.isArray(item.options)
					? item.options.filter((o) => typeof o === "string").map((o) => o.trim().slice(0, 40)).slice(0, 4)
					: [];
				if (!label) return null;
				return withOptions ? { label, options } : { label, value };
			})
			.filter((item) => item !== null)
			.slice(0, 3);
	return { assumptions: clean(parsed.assumptions, false), missing: clean(parsed.missing, true) };
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
			sendJson(res, 200, parsePayload(text));
		} catch (error) {
			sendJson(res, 500, {
				error: "llm-failed",
				message: error instanceof Error ? error.message : String(error)
			});
		}
	};

	ctx.effect(() => ctx.webServer.register({ kind: "exact", path: ROUTE, handler }), "intra-turn: route");
}
