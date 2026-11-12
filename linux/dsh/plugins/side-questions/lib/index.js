/**
 * dsh-local-side-questions — host half.
 *
 * Responde una pregunta corta sobre un texto seleccionado de la conversación
 * sin escribir nada en la sesión: una llamada directa al modelo con el
 * extracto visible, la cita y la pregunta. La respuesta solo viaja al panel
 * del cliente (POST /side-questions/ask).
 *
 * Por qué una ruta HTTP propia y no un evento remoto: la lista de eventos
 * remotos de la aplicación es cerrada (dsh-api-remotes), así que un plugin
 * local no puede declarar un canal nuevo. La ruta vive detrás del mismo
 * servidor web autenticado y exige un header propio (un sitio externo no
 * puede mandarlo sin preflight).
 */

const ROUTE = "/side-questions/ask";
const MAX_BODY_BYTES = 256 * 1024;
const MAX_TRANSCRIPT_CHARS = 14000;
const MAX_QUOTE_CHARS = 4000;
const MAX_QUESTION_CHARS = 2000;
const MAX_ANSWER_TOKENS = 700;
const CALL_TIMEOUT_MS = 90_000;

const SYSTEM = [
	"Sos un asistente de lectura dentro de un cliente de chat.",
	"Recibís un extracto de la conversación, el texto que el usuario seleccionó y su pregunta.",
	"Respondé breve: máximo 8 líneas, en el idioma de la pregunta, usando solo lo que dice el extracto.",
	"Si la respuesta no está en el extracto, decí en una línea qué información falta.",
	"No propongas ejecutar comandos ni modificar archivos: esto es una consulta de lectura."
].join(" ");

/** Recorta por el final: el contexto más cercano a la pregunta es el que importa. */
function tail(text, limit) {
	return text.length > limit ? text.slice(text.length - limit) : text;
}

/** Cuerpo JSON del request, con techo de tamaño. */
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

/** Respuesta JSON sin cache. */
function sendJson(res, status, value) {
	const body = JSON.stringify(value);
	res.writeHead(status, {
		"content-type": "application/json; charset=utf-8",
		"content-length": String(Buffer.byteLength(body)),
		"cache-control": "no-store"
	});
	res.end(body);
}

/** Provider/modelo de la sesión que está mirando el usuario. */
function resolveTarget(ctx, sessionId) {
	const session = typeof sessionId === "string" && sessionId.length > 0 ? ctx.sessions?.get?.(sessionId) : void 0;
	const config = session?.requestHeader?.()?.config;
	if (typeof config?.provider === "string" && typeof config?.model === "string") {
		return {
			provider: config.provider,
			model: config.model,
			...typeof config.reasoningEffort === "string" ? { reasoningEffort: config.reasoningEffort } : {}
		};
	}
	return void 0;
}

/** Acumula el texto del stream y falla si el modelo terminó mal. */
async function collectAnswer(llm, options) {
	let text = "";
	let failure;
	for await (const chunk of llm.stream(options)) {
		if (chunk.type === "text-delta") text += chunk.text;
		else if (chunk.type === "finish" && chunk.reason !== void 0 && chunk.reason.kind !== "stop" && chunk.reason.kind !== "length") failure = chunk.reason;
	}
	if (failure !== void 0) throw new Error(`model finished with ${failure.kind}${typeof failure.message === "string" ? `: ${failure.message}` : ""}`);
	return text.trim();
}

export const inject = ["webServer", "llm", "sessions"];

/**
 * @param ctx - host context carrying webServer, llm and sessions.
 */
export function apply(ctx) {
	const logger = ctx.logger;

	const handler = async (req, res) => {
		if (req.method !== "POST") {
			sendJson(res, 405, { error: "method-not-allowed" });
			return;
		}
		if (req.headers["x-dsh-side-question"] !== "1") {
			sendJson(res, 403, { error: "forbidden" });
			return;
		}
		let payload;
		try {
			payload = await readJsonBody(req);
		} catch (error) {
			sendJson(res, 400, { error: "bad-request", message: error instanceof Error ? error.message : String(error) });
			return;
		}
		const sessionId = typeof payload?.sessionId === "string" ? payload.sessionId : "";
		const quote = typeof payload?.quote === "string" ? payload.quote.slice(0, MAX_QUOTE_CHARS).trim() : "";
		const question = typeof payload?.question === "string" ? payload.question.slice(0, MAX_QUESTION_CHARS).trim() : "";
		const transcript = typeof payload?.transcript === "string" ? tail(payload.transcript, MAX_TRANSCRIPT_CHARS) : "";
		if (question.length === 0) {
			sendJson(res, 400, { error: "empty-question" });
			return;
		}
		const target = resolveTarget(ctx, sessionId);
		if (target === void 0) {
			sendJson(res, 409, { error: "no-model", message: "la sesión todavía no eligió modelo; mandá un mensaje en el chat primero" });
			return;
		}
		const prompt = [
			"EXTRACTO DE LA CONVERSACIÓN:",
			transcript.length > 0 ? transcript : "(vacío)",
			"",
			"TEXTO SELECCIONADO:",
			quote.length > 0 ? quote : "(sin selección)",
			"",
			"PREGUNTA:",
			question
		].join("\n");
		try {
			const answer = await collectAnswer(ctx.llm, {
				provider: target.provider,
				model: target.model,
				...target.reasoningEffort === void 0 ? {} : { reasoningEffort: target.reasoningEffort },
				system: SYSTEM,
				messages: [{
					role: "user",
					content: [{
						type: "text",
						text: prompt
					}]
				}],
				maxTokens: MAX_ANSWER_TOKENS,
				...sessionId.length === 0 ? {} : { sessionId },
				signal: AbortSignal.timeout(CALL_TIMEOUT_MS)
			});
			sendJson(res, 200, {
				answer: answer.length > 0 ? answer : "(el modelo no devolvió texto)",
				model: target.model
			});
		} catch (error) {
			logger?.warn?.(error instanceof Error ? error : new Error(String(error)));
			sendJson(res, 500, {
				error: "llm-failed",
				message: error instanceof Error ? error.message : String(error)
			});
		}
	};

	ctx.effect(() => ctx.webServer.register({
		kind: "exact",
		path: ROUTE,
		handler
	}), "side-questions: route");
}
