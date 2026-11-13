/**
 * dsh-local-web-search-rustxng — el `web_search` del harness busca con RustXNG.
 *
 * Registra el provider `rustxng` en el seam `ctx.web`: en vez de pedirle la
 * búsqueda a la API de DeepSeek (que cobra por búsqueda y falla sin saldo),
 * consulta el metbuscador self-hosted RustXNG por su API JSON.
 *
 * El servicio no queda prendido: se levanta en la primera búsqueda que lo
 * necesita y se apaga solo tras `idleSeconds` sin uso (RUSTXNG_IDLE_TIMEOUT).
 * Si ya hay una instancia escuchando en `baseURL`, la reusa.
 *
 * Se configura desde el patch del perfil:
 *
 *   - insert:
 *       - id: local-web-search-rustxng
 *         name: dsh-local-web-search-rustxng
 *         config:
 *           baseURL: http://127.0.0.1:29483
 *           binary: ~/.local/bin/rustxng
 *
 * El binario se instala con `linux/bin/rustxng-ensure` (release verificado).
 *
 * @module dsh-local-web-search-rustxng
 */

import { spawn } from "node:child_process";
import { closeSync, existsSync, mkdirSync, openSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export const name = "dsh-local-web-search-rustxng";
export const inject = ["web"];

/** Id con el que el provider se registra en `ctx.web` y se pinea en el perfil. */
export const PROVIDER_ID = "rustxng";

const DEFAULT_BASE_URL = "http://127.0.0.1:29483";
const DEFAULT_BINARY = join(homedir(), ".local", "bin", "rustxng");
const DEFAULT_LOG = join(homedir(), ".local", "state", "rustxng", "rustxng.log");
const DEFAULT_IDLE_SECONDS = 300;
const DEFAULT_START_TIMEOUT_MS = 20000;
const DEFAULT_SEARCH_TIMEOUT_MS = 45000;
const HEALTH_TIMEOUT_MS = 1000;
const POLL_MS = 200;
/** Solo se levanta un proceso si el endpoint configurado es de la propia máquina. */
const LOOPBACK = new Set(["127.0.0.1", "::1", "localhost"]);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Error con `code` propio, mismo vocabulario que el seam `ctx.web`. */
function providerError(message, code, cause) {
	return Object.assign(new Error(message, cause === undefined ? undefined : { cause }), {
		name: "WebError",
		code,
	});
}

function abortError() {
	return Object.assign(new Error("búsqueda cancelada"), { name: "AbortError", code: "WEB_ABORTED" });
}

function throwIfAborted(signal) {
	if (signal !== undefined && signal.aborted) throw abortError();
}

/** Mensaje útil aunque el fetch envuelva la causa real (`ECONNREFUSED`). */
function errorText(error) {
	if (!(error instanceof Error)) return String(error);
	const cause = error.cause;
	if (cause instanceof Error && cause.message.length > 0) return `${error.message}: ${cause.message}`;
	return error.message;
}

function expandHome(value) {
	return value.startsWith("~/") ? join(homedir(), value.slice(2)) : value;
}

/** Aplana la config del patch en opciones ya resueltas. */
export function resolveOptions(config = {}) {
	const baseURL = (config.baseURL ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
	const url = new URL(baseURL);
	const port = url.port.length > 0 ? url.port : url.protocol === "https:" ? "443" : "80";
	return {
		baseURL,
		host: url.hostname,
		port,
		binary: expandHome(config.binary ?? DEFAULT_BINARY),
		logFile: expandHome(config.logFile ?? DEFAULT_LOG),
		profile: config.profile ?? "",
		idleSeconds: config.idleSeconds ?? DEFAULT_IDLE_SECONDS,
		startTimeoutMs: config.startTimeoutMs ?? DEFAULT_START_TIMEOUT_MS,
		searchTimeoutMs: config.searchTimeoutMs ?? DEFAULT_SEARCH_TIMEOUT_MS,
	};
}

/** Provider de búsqueda contra RustXNG (`/search?format=json`). */
export class RustxngSearchProvider {
	id = PROVIDER_ID;

	#options;
	#starting;
	#identityChecked = false;

	constructor(options) {
		this.#options = options;
	}

	/** Chequeo local y barato: el endpoint está bien formado. */
	available() {
		return URL.canParse(this.#options.baseURL);
	}

	async search(request, signal) {
		throwIfAborted(signal);
		await this.#ensureServer(signal);
		throwIfAborted(signal);

		const url = new URL("/search", `${this.#options.baseURL}/`);
		url.searchParams.set("q", request.query);
		url.searchParams.set("format", "json");
		if (request.maxResults !== undefined && request.maxResults > 0) {
			url.searchParams.set("max_results", String(request.maxResults));
		}

		const timeout = AbortSignal.timeout(this.#options.searchTimeoutMs);
		const composite = signal === undefined ? timeout : AbortSignal.any([signal, timeout]);
		let response;
		try {
			response = await fetch(url, { signal: composite, headers: { accept: "application/json" } });
		} catch (error) {
			if (signal !== undefined && signal.aborted) throw abortError();
			throw providerError(
				`RustXNG no respondió la búsqueda (${errorText(error)}). Log: ${this.#options.logFile}`,
				"WEB_PROVIDER_ERROR",
			);
		}
		if (!response.ok) {
			throw providerError(
				`RustXNG respondió HTTP ${response.status} en ${url.origin}${url.pathname}.`,
				"WEB_PROVIDER_ERROR",
			);
		}

		let payload;
		try {
			payload = await response.json();
		} catch {
			throw providerError(`RustXNG devolvió JSON inválido en ${url.origin}.`, "WEB_PROVIDER_ERROR");
		}

		const results = Array.isArray(payload?.results) ? payload.results : [];
		const seen = new Set();
		const sources = [];
		for (const item of results) {
			const link = typeof item?.url === "string" ? item.url : "";
			if (link.length === 0 || seen.has(link)) continue;
			seen.add(link);
			sources.push({
				url: link,
				...(typeof item.title === "string" && item.title.length > 0 ? { title: item.title } : {}),
				...(typeof item.content === "string" && item.content.length > 0 ? { snippet: item.content } : {}),
				...(typeof item.publishedDate === "string" && item.publishedDate.length > 0
					? { publishedAt: item.publishedDate }
					: {}),
			});
		}

		if (sources.length === 0) {
			const down = Array.isArray(payload?.unresponsive_engines) ? payload.unresponsive_engines : [];
			if (down.length > 0) {
				throw providerError(
					`RustXNG no obtuvo resultados; motores caídos: ${down.slice(0, 5).map(String).join(", ")}.`,
					"WEB_PROVIDER_ERROR",
				);
			}
		}

		return { sources, truncated: false };
	}

	/** Reusa el servicio si está sano; si no, lo levanta una sola vez por vez. */
	async #ensureServer(signal) {
		if (await this.#healthy()) {
			await this.#checkIdentity();
			return;
		}
		if (this.#starting === undefined) {
			this.#starting = this.#startServer(signal).finally(() => {
				this.#starting = undefined;
			});
		}
		await this.#starting;
	}

	async #healthy() {
		try {
			const response = await fetch(new URL("/healthz", `${this.#options.baseURL}/`), {
				signal: AbortSignal.timeout(HEALTH_TIMEOUT_MS),
			});
			if (!response.ok) return false;
			await response.text();
			return true;
		} catch {
			return false;
		}
	}

	/** Una vez por proceso: el puerto responde, pero ¿es RustXNG? */
	async #checkIdentity() {
		if (this.#identityChecked) return;
		let payload;
		try {
			const response = await fetch(new URL("/config", `${this.#options.baseURL}/`), {
				signal: AbortSignal.timeout(3000),
			});
			if (!response.ok) return;
			payload = await response.json();
		} catch {
			return;
		}
		if (typeof payload?.version !== "string" || !payload.version.startsWith("RustXNG")) {
			throw providerError(
				`${this.#options.baseURL} responde pero no es RustXNG; revisá el puerto o el baseURL del plugin.`,
				"WEB_PROVIDER_CONFIGURED_UNAVAILABLE",
			);
		}
		this.#identityChecked = true;
	}

	/** Levanta RustXNG en loopback y espera `/healthz`. */
	async #startServer(signal) {
		const options = this.#options;
		const url = new URL(options.baseURL);
		if (!LOOPBACK.has(url.hostname)) {
			throw providerError(
				`No hay RustXNG en ${options.baseURL} y la URL no es local: levantá la instancia o cambiá baseURL.`,
				"WEB_PROVIDER_UNAVAILABLE",
			);
		}
		if (!existsSync(options.binary)) {
			throw providerError(
				`No encuentro el binario de RustXNG en ${options.binary}. Instalalo con ~/dotfiles/linux/bin/rustxng-ensure.`,
				"WEB_PROVIDER_UNAVAILABLE",
			);
		}

		mkdirSync(dirname(options.logFile), { recursive: true });
		const logFd = openSync(options.logFile, "a");
		const args = ["--bind", options.host, "--port", options.port];
		if (options.profile.length > 0) args.push("--profile", options.profile);
		const child = spawn(options.binary, args, {
			detached: true,
			stdio: ["ignore", logFd, logFd],
			env: {
				...process.env,
				SEARXNG_PORT: options.port,
				RUSTXNG_IDLE_TIMEOUT: String(options.idleSeconds),
			},
		});
		closeSync(logFd);
		child.unref();

		let spawnFailure;
		child.once("error", (error) => {
			spawnFailure = error;
		});

		const deadline = Date.now() + options.startTimeoutMs;
		while (Date.now() < deadline) {
			throwIfAborted(signal);
			if (await this.#healthy()) {
				await this.#checkIdentity();
				return;
			}
			await sleep(POLL_MS);
		}

		try {
			child.kill("SIGTERM");
		} catch {
			// el proceso ya terminó
		}
		const why =
			spawnFailure === undefined
				? `no respondió /healthz en ${options.startTimeoutMs} ms`
				: `no pudo ejecutarse (${spawnFailure.message})`;
		throw providerError(`RustXNG ${why}. Log: ${options.logFile}`, "WEB_PROVIDER_UNAVAILABLE");
	}
}

/** Registra el provider en el seam web del harness. */
export function apply(ctx, config = {}) {
	ctx.web.registerSearchProvider(new RustxngSearchProvider(resolveOptions(config)));
}
