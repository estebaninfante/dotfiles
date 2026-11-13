/**
 * dsh-local-skills — host half.
 *
 * Catálogo de skills para el panel lateral. No le pide el catálogo al registro
 * global del harness (`ctx.skills`) porque el bundle web DESACTIVA el
 * `skill-filesystem` de host y lo monta dentro de cada preset: un plugin de
 * perfil lee ese registro vacío. Así que acá se descubren los mismos roots que
 * el harness escanea, con las mismas reglas (carpeta con SKILL.md o archivo
 * `<nombre>.md`, frontmatter con `name` y `description`), y se suman las skills
 * que el registro global sí tenga (runtime / bundled).
 *
 * Rutas (loopback, servidas por el webServer del perfil):
 *   GET  /skills/list       catálogo con origen, ruta y permisos de invocación
 *   GET  /skills/read?name  el SKILL.md completo de una skill
 *   POST /skills/save       { name, content } — guarda el SKILL.md editado
 *   POST /skills/delete     { name } — mueve la skill a la papelera
 *
 * La escritura y el borrado solo tocan rutas que el descubrimiento ya había
 * encontrado (nunca una ruta que llegue del navegador) y exigen el header
 * `x-dsh-skills: 1`: un sitio externo no puede mandarlo sin preflight.
 *
 * Borrar NO usa `rm -rf`: mueve la carpeta (o el archivo) a
 * `~/.local/share/skills/trash/<fecha>/`, así se recupera copiándola de vuelta.
 * Si la skill es un symlink (las de dotfiles), se mueve el enlace: el contenido
 * del repo queda intacto.
 */

import {
	existsSync,
	lstatSync,
	mkdirSync,
	readFileSync,
	readdirSync,
	realpathSync,
	renameSync,
	statSync,
	writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";

export const inject = ["webServer"];

const DSH_HOME = process.env.DSH_HOME ?? join(homedir(), ".dsh");
const AGENTS_HOME = process.env.DSH_AGENTS_HOME ?? join(homedir(), ".agents");
const MAX_NAME_CHARS = 200;
const MAX_BODY_BYTES = 256 * 1024;
const CACHE = "no-store, max-age=0";
/** Papelera: recuperable a mano, nunca un `rm -rf`. */
const TRASH_DIR = process.env.DSH_SKILLS_TRASH ?? join(homedir(), ".local/share/skills/trash");
/** Mismo gramático que el harness: kebab-case en minúsculas. */
const NAME_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** Roots de usuario, con el rank del harness (menor gana en duplicados). */
function userRoots() {
	return [
		{ path: join(DSH_HOME, "skills"), source: "user-dsh", rank: 400, skipSystem: true },
		{ path: join(AGENTS_HOME, "skills"), source: "user-agents", rank: 500 },
		{
			path: "/skills/ai-edit",
			method: "POST",
			handler: async (req, res) => {
				if (req.headers["x-dsh-skills"] !== "1") {
					sendJson(res, 403, { ok: false, error: "falta el header x-dsh-skills" });
					return;
				}
				const body = await readJsonBody(req).catch(() => null);
				const name = typeof body?.name === "string" ? body.name.trim() : "";
				const instruction = typeof body?.instruction === "string" ? body.instruction.trim() : "";
				const given = typeof body?.content === "string" ? body.content : "";
				if (name.length === 0 || name.length > MAX_NAME_CHARS || !NAME_RE.test(name)) {
					sendJson(res, 400, { ok: false, error: "nombre inválido" });
					return;
				}
				if (instruction.length < 3) {
					sendJson(res, 400, { ok: false, error: "escribí qué querés cambiar" });
					return;
				}
				const llm = ctx.get?.("llm");
				const selection = ctx.get?.("agentDefaultModel")?.currentSelection?.();
				if (llm === undefined || selection === undefined) {
					sendJson(res, 409, { ok: false, error: "no hay modelo por defecto configurado" });
					return;
				}
				try {
					let current = given;
					if (current.trim().length === 0) {
						const { skills } = await collect(ctx, "");
						const match = skills.find((skill) => skill.name === name);
						if (match === undefined || typeof match.realPath !== "string") {
							sendJson(res, 404, { ok: false, error: "esa skill no está en el catálogo" });
							return;
						}
						current = readFileSync(match.realPath, "utf8");
					}
					const prompt = [`INSTRUCCIÓN DEL USUARIO:`, instruction, "", "SKILL.md ACTUAL:", unwrapFence(current)].join("\n");
					const answer = await collectAnswer(llm, {
						provider: selection.provider,
						model: selection.model,
						...(selection.reasoningEffort === undefined ? {} : { reasoningEffort: selection.reasoningEffort }),
						system: AI_SYSTEM,
						messages: [{ role: "user", content: [{ type: "text", text: prompt }] }],
						maxTokens: 6000,
						signal: AbortSignal.timeout(150000),
					});
					const content = unwrapFence(answer);
					if (content.trim().length === 0) {
						sendJson(res, 502, { ok: false, error: "el modelo no devolvió texto" });
						return;
					}
					const meta = parseFrontmatter(content);
					const valid =
						typeof meta.name === "string" &&
						NAME_RE.test(meta.name.trim()) &&
						typeof meta.description === "string" &&
						meta.description.trim().length > 0;
					sendJson(res, 200, {
						ok: true,
						model: selection.model,
						content,
						warning: valid ? "" : "el modelo devolvió algo sin name/description válidos: revisalo antes de guardar",
					});
				} catch (error) {
					fail(res, error);
				}
			},
		},
	];
}

/** Roots de un proyecto concreto, solo si el panel pide `?cwd=`. */
function projectRoots(cwd) {
	if (typeof cwd !== "string" || cwd.length === 0) return [];
	const base = resolve(cwd.replace(/^~(?=\/|$)/, homedir()));
	return [
		{ path: join(base, ".dsh/skills"), source: "project-dsh", rank: 100 },
		{ path: join(base, ".agents/skills"), source: "project-agents", rank: 200 },
	];
}

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

/** Ruta para mostrar: la home se acorta a `~`. */
function displayPath(path) {
	const home = homedir();
	return path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

/** Booleanos como los acepta el harness; `undefined` = valor inválido. */
function parseBool(raw) {
	const value = raw.trim().toLowerCase();
	if (["true", "yes", "on", "1"].includes(value)) return true;
	if (["false", "no", "off", "0"].includes(value)) return false;
	return undefined;
}

/**
 * Frontmatter del SKILL.md: `name`, `description`, `whenToUse` (o
 * `when-to-use`) y los dos booleanos de invocación, con valores entre comillas
 * o bloques `>` / `|`.
 */
function parseFrontmatter(text) {
	const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
	if (match === null) return {};
	const lines = match[1].split(/\r?\n/);
	const meta = {};
	for (let i = 0; i < lines.length; i += 1) {
		const kv = lines[i].match(/^([A-Za-z][A-Za-z0-9_-]*):[ \t]*(.*)$/);
		if (kv === null) continue;
		const key = kv[1];
		let value = kv[2].trim();
		if (value === ">" || value === "|" || value === ">-" || value === "|-") {
			const block = [];
			while (i + 1 < lines.length && /^[ \t]+\S/.test(lines[i + 1])) {
				i += 1;
				block.push(lines[i].trim());
			}
			value = value.startsWith(">") ? block.join(" ") : block.join("\n");
		} else if (value.length > 1 && /^["']/.test(value) && value.at(-1) === value[0]) {
			value = value.slice(1, -1);
		}
		meta[key] = value;
	}
	return meta;
}

/** Un root: carpetas con SKILL.md (sin bajar más) o archivos sueltos `<nombre>.md`. */
function discoverRoot(root) {
	if (!existsSync(root.path)) return { skills: [], ignored: [], exists: false };
	let entries;
	try {
		entries = readdirSync(root.path, { withFileTypes: true });
	} catch {
		return { skills: [], ignored: [], exists: true };
	}
	const skills = [];
	const ignored = [];
	for (const entry of entries) {
		const name = entry.name;
		if (name.startsWith(".")) continue;
		if (root.skipSystem === true && name === ".system") continue;
		const full = join(root.path, name);
		let isDir = entry.isDirectory();
		let isFile = entry.isFile();
		if (entry.isSymbolicLink()) {
			try {
				const stat = statSync(full);
				isDir = stat.isDirectory();
				isFile = stat.isFile();
			} catch {
				continue;
			}
		}
		const file = isDir ? join(full, "SKILL.md") : isFile && name.endsWith(".md") ? full : undefined;
		if (file === undefined || !existsSync(file)) continue;
		let text;
		let modified = 0;
		try {
			const stat = statSync(file);
			if (stat.size > MAX_BODY_BYTES) {
				ignored.push({ name, path: displayPath(file), reason: "archivo demasiado grande" });
				continue;
			}
			modified = Math.round(stat.mtimeMs);
			text = readFileSync(file, "utf8");
		} catch {
			continue;
		}
		const meta = parseFrontmatter(text);
		const skillName =
			typeof meta.name === "string" && meta.name.length > 0 ? meta.name : isDir ? name : name.slice(0, -3);
		const description = typeof meta.description === "string" ? meta.description.trim() : "";
		if (!NAME_RE.test(skillName)) {
			ignored.push({ name: skillName, path: displayPath(file), reason: "nombre inválido (kebab-case)" });
			continue;
		}
		if (description.length === 0) {
			ignored.push({ name: skillName, path: displayPath(file), reason: "sin description" });
			continue;
		}
		const whenToUse =
			typeof meta.whenToUse === "string"
				? meta.whenToUse
				: typeof meta["when-to-use"] === "string"
					? meta["when-to-use"]
					: "";
		const rawModel = (meta["disable-model-invocation"] ?? "").trim();
		const rawUser = (meta["user-invocable"] ?? "").trim();
		// Ausente = permitido: sin `disable-model-invocation` el modelo la ve, y
		// sin `user-invocable` el humano la puede llamar. Presente con una
		// ortografía rara = se descarta la skill entera (igual que el harness).
		const modelHidden = rawModel.length === 0 ? false : parseBool(rawModel);
		const userAllowed = rawUser.length === 0 ? true : parseBool(rawUser);
		if (modelHidden === undefined || userAllowed === undefined) {
			ignored.push({ name: skillName, path: displayPath(file), reason: "booleano de invocación inválido" });
			continue;
		}
		skills.push({
			name: skillName,
			description,
			whenToUse,
			source: root.source,
			path: displayPath(file),
			realPath: file,
			rank: root.rank,
			modified,
			model: modelHidden === false,
			user: userAllowed === true,
		});
	}
	return { skills, ignored, exists: true };
}

/** Descubrimiento completo: roots de usuario, roots de proyecto y registro global. */
async function collect(ctx, cwd) {
	const roots = [...projectRoots(cwd), ...userRoots()];
	const byName = new Map();
	const rootInfo = [];
	const ignored = [];
	for (const root of roots) {
		const found = discoverRoot(root);
		rootInfo.push({
			path: displayPath(root.path),
			source: root.source,
			exists: found.exists,
			count: found.skills.length,
		});
		ignored.push(...found.ignored);
		for (const skill of found.skills) {
			const previous = byName.get(skill.name);
			if (previous === undefined) {
				byName.set(skill.name, skill);
				continue;
			}
			if (skill.rank < previous.rank) {
				byName.set(skill.name, skill);
				ignored.push({ name: skill.name, path: previous.path, reason: `duplicada de ${skill.source}` });
			} else {
				ignored.push({ name: skill.name, path: skill.path, reason: `duplicada de ${previous.source}` });
			}
		}
	}

	// Las skills que el registro global sí tenga (runtime / bundled) se suman
	// sin pisar lo que vino del disco.
	try {
		const registry = ctx.get?.("skills");
		const extra = registry === undefined || registry === null ? [] : await registry.list({});
		for (const skill of extra) {
			if (byName.has(skill.name)) continue;
			byName.set(skill.name, {
				name: skill.name,
				description: skill.description ?? "",
				whenToUse: skill.whenToUse ?? "",
				source: skill.source ?? "runtime",
				path: typeof skill.path === "string" ? displayPath(skill.path) : "",
				realPath: skill.path,
				rank: 600,
				model: skill.invocation?.modelInvocable === true,
				user: skill.invocation?.userInvocable === true,
			});
		}
	} catch {
		// Sin registro global se sigue igual: el disco es la mayor parte del catálogo.
	}

	const skills = [...byName.values()].sort((a, b) => a.name.localeCompare(b.name));
	return { skills, roots: rootInfo, ignored };
}

function publicSkill(skill) {
	return {
		name: skill.name,
		description: skill.description,
		whenToUse: skill.whenToUse,
		source: skill.source,
		path: skill.path,
		modified: skill.modified ?? 0,
		model: skill.model,
		user: skill.user,
	};
}

function queryOf(req) {
	try {
		return new URL(req.url ?? "/", "http://localhost").searchParams;
	} catch {
		return new URLSearchParams();
	}
}

/** Junta el texto del stream y falla si el modelo terminó mal. */
async function collectAnswer(llm, options) {
	let text = "";
	let failure;
	for await (const chunk of llm.stream(options)) {
		if (chunk.type === "text-delta") text += chunk.text;
		else if (chunk.type === "finish" && chunk.reason !== undefined && chunk.reason.kind !== "stop" && chunk.reason.kind !== "length") {
			failure = chunk.reason;
		}
	}
	if (failure !== undefined) {
		throw new Error(`el modelo terminó con ${failure.kind}${typeof failure.message === "string" ? `: ${failure.message}` : ""}`);
	}
	return text.trim();
}

const AI_SYSTEM = [
	"Sos un editor de skills del harness DeepSeek.",
	"Recibís un SKILL.md completo y una instrucción de edición.",
	"Devolvés ÚNICAMENTE el archivo Markdown completo y corregido.",
	"Reglas:",
	"- Mantené el frontmatter YAML entre --- con `name` (kebab-case) y `description` (una frase que diga cuándo usarla).",
	"- El cuerpo tiene que quedar claro, corto y accionable, en el idioma que ya usa el archivo.",
	"- No agregues bloques de código que envuelvan todo el archivo, ni comentarios sobre lo que cambiaste.",
	"- Si la instrucción pide algo imposible sin más contexto, dejá el archivo igual y agregá una línea final con: <!-- falta contexto: ... -->",
].join("\n");

/** Quita el cerco ```markdown ... ``` si el modelo envolvió todo el archivo. */
function unwrapFence(text) {
	const match = text.match(/^```[a-zA-Z]*\r?\n([\s\S]*?)\r?\n```\s*$/);
	return match === null ? text : match[1];
}

function readJsonBody(req) {
	return new Promise((resolvePromise, reject) => {
		let size = 0;
		const chunks = [];
		req.on("data", (chunk) => {
			size += chunk.length;
			if (size > MAX_BODY_BYTES) {
				reject(new Error("el cuerpo supera el límite"));
				req.destroy();
				return;
			}
			chunks.push(chunk);
		});
		req.on("end", () => {
			try {
				resolvePromise(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
			} catch (error) {
				reject(error);
			}
		});
		req.on("error", reject);
	});
}

/**
 * Escritura de un archivo que el descubrimiento ya encontró. Resuelve el
 * symlink (un skill enlazado a dotfiles escribe el archivo real), conserva los
 * permisos y no deja el archivo a medias: escribe un temporal al lado y lo
 * renombra.
 */
function writeSkillFile(file, content) {
	const target = realpathSync(file);
	if (!statSync(target).isFile()) throw new Error("la ruta no es un archivo");
	const mode = statSync(target).mode;
	const temp = `${target}.tmp-${process.pid}`;
	writeFileSync(temp, content, { encoding: "utf8", mode });
	renameSync(temp, target);
}

function stamp() {
	return new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
}

/**
 * Saca una skill del catálogo moviéndola a la papelera. Nunca `rm -rf`:
 * si la entrada es un symlink (las skills enlazadas a dotfiles) se mueve el
 * enlace y el contenido del repo queda intacto.
 */
function moveToTrash(skill) {
	const file = skill.realPath;
	const entry = basename(file) === "SKILL.md" ? dirname(file) : file;
	const isLink = lstatSync(entry).isSymbolicLink();
	const target = join(TRASH_DIR, stamp(), basename(entry));
	mkdirSync(dirname(target), { recursive: true });
	renameSync(entry, target);
	return { target, isLink };
}

export function apply(ctx) {
	const routes = [
		{
			path: "/skills/list",
			method: "GET",
			handler: async (req, res) => {
				const params = queryOf(req);
				try {
					const { skills, roots, ignored } = await collect(ctx, params.get("cwd") ?? "");
					sendJson(res, 200, {
						ok: true,
						count: skills.length,
						model: skills.filter((skill) => skill.model).length,
						command: skills.filter((skill) => !skill.model && skill.user).length,
						roots,
						ignored,
						skills: skills.map(publicSkill),
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
				const params = queryOf(req);
				const name = (params.get("name") ?? "").trim();
				if (name.length === 0 || name.length > MAX_NAME_CHARS || !NAME_RE.test(name)) {
					sendJson(res, 400, { ok: false, error: "nombre inválido" });
					return;
				}
				try {
					const { skills } = await collect(ctx, params.get("cwd") ?? "");
					const match = skills.find((skill) => skill.name === name);
					if (match === undefined) {
						sendJson(res, 404, { ok: false, error: "esa skill no está en el catálogo" });
						return;
					}
					if (typeof match.realPath !== "string" || !existsSync(match.realPath)) {
						sendJson(res, 409, { ok: false, error: "la skill no tiene archivo (viene de un plugin)" });
						return;
					}
					if (statSync(match.realPath).size > MAX_BODY_BYTES) {
						sendJson(res, 413, { ok: false, error: "el SKILL.md es demasiado grande" });
						return;
					}
					sendJson(res, 200, {
						ok: true,
						skill: { ...publicSkill(match), content: readFileSync(match.realPath, "utf8") },
					});
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/skills/save",
			method: "POST",
			handler: async (req, res) => {
				if (req.headers["x-dsh-skills"] !== "1") {
					sendJson(res, 403, { ok: false, error: "falta el header x-dsh-skills" });
					return;
				}
				const body = await readJsonBody(req).catch(() => null);
				const name = typeof body?.name === "string" ? body.name.trim() : "";
				const content = typeof body?.content === "string" ? body.content : "";
				if (name.length === 0 || name.length > MAX_NAME_CHARS || !NAME_RE.test(name)) {
					sendJson(res, 400, { ok: false, error: "nombre inválido" });
					return;
				}
				if (content.trim().length === 0) {
					sendJson(res, 400, { ok: false, error: "el contenido está vacío" });
					return;
				}
				try {
					const { skills } = await collect(ctx, "");
					const match = skills.find((skill) => skill.name === name);
					if (match === undefined) {
						sendJson(res, 404, { ok: false, error: "esa skill no está en el catálogo" });
						return;
					}
					if (typeof match.realPath !== "string" || !existsSync(match.realPath)) {
						sendJson(res, 409, { ok: false, error: "la skill no tiene archivo propio" });
						return;
					}
					// El frontmatter tiene que seguir siendo válido: si se rompe,
					// el harness dejaría de cargar la skill.
					const meta = parseFrontmatter(content);
					const nextName = typeof meta.name === "string" ? meta.name.trim() : "";
					const nextDescription = typeof meta.description === "string" ? meta.description.trim() : "";
					if (!NAME_RE.test(nextName)) {
						sendJson(res, 422, { ok: false, error: "el frontmatter necesita `name` en kebab-case" });
						return;
					}
					if (nextDescription.length === 0) {
						sendJson(res, 422, { ok: false, error: "el frontmatter necesita `description`" });
						return;
					}
					if (nextName !== name && skills.some((skill) => skill.name === nextName)) {
						sendJson(res, 409, { ok: false, error: `ya existe otra skill llamada ${nextName}` });
						return;
					}
					writeSkillFile(match.realPath, content);
					const after = await collect(ctx, "");
					const updated =
						after.skills.find((skill) => skill.realPath === match.realPath) ?? {
							...match,
							name: nextName,
							description: nextDescription,
						};
					sendJson(res, 200, { ok: true, skill: { ...publicSkill(updated), content } });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/skills/delete",
			method: "POST",
			handler: async (req, res) => {
				if (req.headers["x-dsh-skills"] !== "1") {
					sendJson(res, 403, { ok: false, error: "falta el header x-dsh-skills" });
					return;
				}
				const body = await readJsonBody(req).catch(() => null);
				const name = typeof body?.name === "string" ? body.name.trim() : "";
				if (name.length === 0 || name.length > MAX_NAME_CHARS || !NAME_RE.test(name)) {
					sendJson(res, 400, { ok: false, error: "nombre inválido" });
					return;
				}
				try {
					const { skills } = await collect(ctx, "");
					const match = skills.find((skill) => skill.name === name);
					if (match === undefined) {
						sendJson(res, 404, { ok: false, error: "esa skill no está en el catálogo" });
						return;
					}
					if (typeof match.realPath !== "string" || !existsSync(match.realPath)) {
						sendJson(res, 409, { ok: false, error: "la skill no tiene archivo propio (viene de un plugin)" });
						return;
					}
					const moved = moveToTrash(match);
					const after = await collect(ctx, "");
					ctx.logger?.info?.(`skills: "${match.name}" movida a ${moved.target}`);
					sendJson(res, 200, {
						ok: true,
						name: match.name,
						trash: displayPath(moved.target),
						symlink: moved.isLink,
						count: after.skills.length,
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
