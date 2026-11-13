/**
 * dsh-local-machine — host half.
 *
 * Puente entre el panel y la base `machine.db`. Todo el SQL vive en el CLI
 * `machine`; acá solo se lo invoca y se devuelve JSON. Así el panel, los
 * agentes y la terminal leen exactamente lo mismo: una sola fuente de verdad.
 *
 * Rutas (todas loopback, servidas por el webServer del perfil):
 *   GET  /machine/projects      lista con hechos
 *   GET  /machine/project?slug  ficha + tareas
 *   POST /machine/entity        { slug, state?, kind?, note? }
 *   POST /machine/task          { slug, title }
 *   POST /machine/task-done     { task }
 *   POST /machine/open          { path }   abre la carpeta en el gestor
 *
 * Los POST exigen el header `x-dsh-machine: 1`: un sitio externo no puede
 * mandarlo sin preflight, así que no puede tocar la base del navegador.
 */

import { execFile, spawn } from "node:child_process";
import { statSync } from "node:fs";
import { homedir } from "node:os";
import { promisify } from "node:util";

const run = promisify(execFile);
const BIN = `${homedir()}/.local/bin/machine`;
const TIMEOUT = 15000;
const MAX_BODY = 64 * 1024;

export const inject = ["webServer"];

function sendJson(res, status, payload) {
	res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
	res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
	return new Promise((resolve, reject) => {
		let size = 0;
		const chunks = [];
		req.on("data", (chunk) => {
			size += chunk.length;
			if (size > MAX_BODY) {
				reject(new Error("body-too-large"));
				req.destroy();
				return;
			}
			chunks.push(chunk);
		});
		req.on("end", () => {
			try {
				resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
			} catch (error) {
				reject(error);
			}
		});
		req.on("error", reject);
	});
}

async function machine(args) {
	const { stdout } = await run(BIN, args, { timeout: TIMEOUT, maxBuffer: 8 << 20 });
	return stdout;
}

async function machineJson(args) {
	const out = await machine(args);
	return JSON.parse(out);
}

function fail(res, error) {
	sendJson(res, 500, {
		error: "machine-failed",
		message: error instanceof Error ? error.message : String(error),
	});
}

export function apply(ctx) {
	const routes = [
		{
			path: "/machine/projects",
			method: "GET",
			handler: async (req, res) => {
				try {
					sendJson(res, 200, { projects: await machineJson(["ls", "--json"]) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/project",
			method: "GET",
			handler: async (req, res) => {
				const url = new URL(req.url ?? "/", "http://127.0.0.1");
				const slug = (url.searchParams.get("slug") ?? "").trim();
				if (!slug) {
					sendJson(res, 400, { error: "missing-slug" });
					return;
				}
				try {
					sendJson(res, 200, await machineJson(["show", slug, "--json"]));
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/gh",
			method: "GET",
			handler: async (req, res) => {
				try {
					sendJson(res, 200, await machineJson(["gh-status", "--json"]));
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/scan",
			method: "POST",
			handler: async (req, res) => {
				try {
					sendJson(res, 200, { ok: true, out: await machine(["scan"]) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/entity",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const slug = typeof body?.slug === "string" ? body.slug.trim() : "";
				if (!slug) {
					sendJson(res, 400, { error: "missing-slug" });
					return;
				}
				const args = ["set", slug];
				if (typeof body.state === "string") args.push("--state", body.state);
				if (typeof body.kind === "string") args.push("--kind", body.kind);
				if (typeof body.note === "string") args.push("--note", body.note);
				if (args.length === 2) {
					sendJson(res, 400, { error: "nothing-to-change" });
					return;
				}
				try {
					sendJson(res, 200, { ok: true, out: await machine(args) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/idea",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const text = typeof body?.text === "string" ? body.text.trim() : "";
				if (!text) {
					sendJson(res, 400, { error: "missing-text" });
					return;
				}
				try {
					sendJson(res, 200, { ok: true, out: await machine(["idea", text]) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/rename",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const slug = typeof body?.slug === "string" ? body.slug.trim() : "";
				if (!slug) {
					sendJson(res, 400, { error: "missing-slug" });
					return;
				}
				const args = ["rename", slug];
				if (body?.auto === true) args.push("--auto");
				else if (typeof body?.title === "string" && body.title.trim()) args.push(body.title.trim());
				else {
					sendJson(res, 400, { error: "missing-title" });
					return;
				}
				try {
					sendJson(res, 200, { ok: true, out: await machine(args), project: await machineJson(["show", slug, "--json"]) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/trash",
			method: "GET",
			handler: async (req, res) => {
				try {
					sendJson(res, 200, { entries: await machineJson(["trash", "--json"]) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/trash-delete",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const slug = typeof body?.slug === "string" ? body.slug.trim() : "";
				if (!slug && body?.all !== true) {
					sendJson(res, 400, { error: "missing-slug" });
					return;
				}
				const args = ["purge", "--yes"];
				if (body?.all === true) args.push("--all");
				else args.push("--slug", slug);
				try {
					sendJson(res, 200, { ok: true, out: await machine(args) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/service-disable",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const slug = typeof body?.slug === "string" ? body.slug.trim() : "";
				if (!slug) {
					sendJson(res, 400, { error: "missing-slug" });
					return;
				}
				try {
					const out = await machine(["service-disable", slug]);
					await machine(["scan"]);
					sendJson(res, 200, { ok: true, out, project: await machineJson(["show", slug, "--json"]) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/trash-recover",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const slug = typeof body?.slug === "string" ? body.slug.trim() : "";
				if (!slug) {
					sendJson(res, 400, { error: "missing-slug" });
					return;
				}
				try {
					const out = await machine(["restore", slug]);
					await machine(["scan"]);
					sendJson(res, 200, { ok: true, out });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/trash",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const slug = typeof body?.slug === "string" ? body.slug.trim() : "";
				if (!slug) {
					sendJson(res, 400, { error: "missing-slug" });
					return;
				}
				const args = ["trash", slug, "--yes"];
				if (body?.github === true) args.push("--github");
				try {
					sendJson(res, 200, { ok: true, out: await machine(args) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/task",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const slug = typeof body?.slug === "string" ? body.slug.trim() : "";
				const title = typeof body?.title === "string" ? body.title.trim() : "";
				if (!slug || !title) {
					sendJson(res, 400, { error: "missing-fields" });
					return;
				}
				try {
					sendJson(res, 200, { ok: true, out: await machine(["task", "add", slug, title]) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			// Abrir la carpeta del proyecto en el gestor de archivos del escritorio.
			// Solo carpetas dentro del home: esto nunca abre URLs ni binarios.
			path: "/machine/open",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const target = typeof body?.path === "string" ? body.path.trim() : "";
				const home = homedir();
				if (!target || !target.startsWith(`${home}/`)) {
					sendJson(res, 400, { error: "path-outside-home" });
					return;
				}
				try {
					if (!statSync(target).isDirectory()) {
						sendJson(res, 400, { error: "not-a-directory" });
						return;
					}
				} catch {
					sendJson(res, 404, { error: "missing" });
					return;
				}
				try {
					const child = spawn("xdg-open", [target], { detached: true, stdio: "ignore" });
					child.unref();
					sendJson(res, 200, { ok: true });
				} catch (error) {
					fail(res, error);
				}
			},
		},
		{
			path: "/machine/task-done",
			method: "POST",
			handler: async (req, res) => {
				const body = await readJsonBody(req).catch(() => null);
				const task = typeof body?.task === "string" ? body.task.trim() : "";
				if (!task) {
					sendJson(res, 400, { error: "missing-task" });
					return;
				}
				try {
					sendJson(res, 200, { ok: true, out: await machine(["task", "done", task]) });
				} catch (error) {
					fail(res, error);
				}
			},
		},
	];

	// El webServer registra **un handler por path**: GET y POST del mismo path
	// tienen que entrar por la misma puerta y despacharse adentro.
	const byPath = new Map();
	for (const route of routes) {
		if (!byPath.has(route.path)) byPath.set(route.path, {});
		const methods = byPath.get(route.path);
		if (methods[route.method]) throw new Error(`machine: ruta duplicada ${route.method} ${route.path}`);
		methods[route.method] = route.handler;
	}

	for (const [path, methods] of byPath) {
		ctx.effect(
			() =>
				ctx.webServer.register({
					kind: "exact",
					path,
					handler: async (req, res) => {
						const method = req.method ?? "GET";
						const handler = methods[method];
						if (!handler) {
							sendJson(res, 405, { error: "method-not-allowed", allow: Object.keys(methods) });
							return;
						}
						if (method === "POST" && req.headers["x-dsh-machine"] !== "1") {
							sendJson(res, 403, { error: "forbidden" });
							return;
						}
						try {
							await handler(req, res);
						} catch (error) {
							fail(res, error);
						}
					},
				}),
			`machine: route ${path}`,
		);
	}

	ctx.logger?.info?.("machine: panel de proyectos montado");
}
