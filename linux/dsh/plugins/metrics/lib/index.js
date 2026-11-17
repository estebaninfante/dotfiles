/**
 * dsh-local-metrics — host half.
 *
 * Lee el log durable de una sesión y devuelve, en JSON, sus métricas:
 * tiempos, latencias, tokens, tools, reintentos, fallos y contexto. No
 * mantiene estado propio: la persistencia de sesiones es la fuente de verdad,
 * así que sirve igual para la conversación abierta y para una vieja.
 *
 * Ruta (loopback, servida por el webServer del perfil):
 *   GET /metrics/session?session=<id>
 */

import { foldSession } from "./fold.js";

export const name = "dsh-local-metrics";
export const inject = ["webServer", "sessionPersistence"];

/** Ids de sesión que la persistencia puede contener. */
const SESSION_ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,200}$/;
/** evita releer el mismo log en ráfagas de la vista. */
const CACHE_MS = 1500;
const CACHE_MAX = 32;
const cache = new Map();

function sendJson(res, status, payload) {
	res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
	res.end(JSON.stringify(payload));
}

export function apply(ctx) {
	ctx.effect(
		() =>
			ctx.webServer.register({
				kind: "exact",
				path: "/metrics/session",
				handler: async (req, res) => {
					if ((req.method ?? "GET") !== "GET") {
						sendJson(res, 405, { ok: false, error: "method-not-allowed" });
						return;
					}
					const url = new URL(req.url ?? "/", "http://127.0.0.1");
					const id = (url.searchParams.get("session") ?? "").trim();
					if (!SESSION_ID.test(id)) {
						sendJson(res, 400, { ok: false, error: "bad-session" });
						return;
					}
					const hit = cache.get(id);
					if (hit !== undefined && Date.now() - hit.at < CACHE_MS) {
						sendJson(res, 200, hit.payload);
						return;
					}
					try {
						const handle = await ctx.sessionPersistence.open(id, "read");
						try {
							const { events } = await handle.read(0);
							const payload = { ok: true, ...foldSession(handle.header, events) };
							if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value);
							cache.set(id, { at: Date.now(), payload });
							sendJson(res, 200, payload);
						} finally {
							await handle.close();
						}
					} catch (error) {
						if (error?.name === "SessionPersistenceNotFoundError") {
							sendJson(res, 404, { ok: false, error: "not-found" });
							return;
						}
						ctx.logger?.warn?.(`metrics: no se pudo leer la sesión "${id}": %o`, error);
						sendJson(res, 500, {
							ok: false,
							error: "metrics-failed",
							message: error instanceof Error ? error.message : String(error),
						});
					}
				},
			}),
		"metrics: ruta /metrics/session",
	);
}
