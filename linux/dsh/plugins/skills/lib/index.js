/**
 * dsh-local-skills — host half.
 *
 * Puente entre el panel lateral y el registro de skills del harness
 * (`ctx.skills`). No escanea carpetas a mano: pregunta al mismo registro que
 * alimenta el catálogo del modelo, así el panel muestra exactamente lo que el
 * harness cargó, con su origen y la ruta real del SKILL.md.
 *
 * Rutas (loopback, servidas por el webServer del perfil):
 *   GET /skills/list       catálogo completo, con invocación y origen
 *   GET /skills/read?name  el SKILL.md completo de una skill
 *
 * Solo lectura. Cualquier escritura futura va por rutas POST aparte.
 */

export const inject = ["webServer", "skills"];

const MAX_NAME_CHARS = 200;
const CACHE = "no-store, max-age=0";

function sendJson(res, status, payload) {
	res.writeHead(status, {
		"content-type": "application/json; charset=utf-8",
		"cache-control": CACHE,
	});
	res.end(JSON.stringify(payload));
}

function fail(res, error) {
	const message = error instanceof Error ? error.message : String(error);
	sendJson(res, 500, { ok: false, error: message });
}

/** Resumen plano: solo lo que la UI dibuja, sin locators ni handles internos. */
function shape(skill) {
	return {
		name: skill.name,
		description: skill.description ?? "",
		whenToUse: skill.whenToUse ?? "",
		source: skill.source ?? "custom",
		path: skill.path ?? "",
		model: skill.invocation?.modelInvocable === true,
		user: skill.invocation?.userInvocable === true,
	};
}

export function apply(ctx) {
	const routes = [
		{
			path: "/skills/list",
			method: "GET",
			handler: async (req, res) => {
				try {
					const skills = await ctx.skills.list({});
					const rows = skills.map(shape).sort((a, b) => a.name.localeCompare(b.name));
					sendJson(res, 200, {
						ok: true,
						count: rows.length,
						model: rows.filter((row) => row.model).length,
						command: rows.filter((row) => !row.model && row.user).length,
						skills: rows,
					});
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/skills/read",
			method: "GET",
			handler: async (req, res) => {
				let name = "";
				try {
					const url = new URL(req.url ?? "/", "http://localhost");
					name = (url.searchParams.get("name") ?? "").trim();
				} catch {
					name = "";
				}
				if (!name || name.length > MAX_NAME_CHARS) {
					sendJson(res, 400, { ok: false, error: "missing-name" });
					return;
				}
				try {
					const skill = await ctx.skills.get(name, {});
					if (skill === undefined || skill === null) {
						sendJson(res, 404, { ok: false, error: "unknown-skill", name });
						return;
					}
					sendJson(res, 200, {
						ok: true,
						skill: {
							...shape(skill),
							content: skill.content ?? "",
						},
					});
				} catch (error) {
					fail(res, error);
				}
			},
		},
	];

	for (const route of routes) {
		ctx.effect(
			() =>
				ctx.webServer.register({
					kind: "exact",
					path: route.path,
					handler: async (req, res) => {
						const method = req.method ?? "GET";
						if (method !== route.method) {
							sendJson(res, 405, { ok: false, error: "method-not-allowed", allow: [route.method] });
							return;
						}
						try {
							await route.handler(req, res);
						} catch (error) {
							fail(res, error);
						}
					},
				}),
			`skills: route ${route.path}`,
		);
	}

	ctx.logger?.info?.("skills: panel de skills montado");
}
