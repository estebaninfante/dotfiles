/**
 * dsh-local-video-preview — host half.
 *
 * El visor del panel lateral necesita bytes para PDF, imágenes y Office, y por
 * eso no puede con un video: el techo de lectura es de unos pocos MB y aun así
 * habría que tenerlo entero en memoria. Acá se sirve con streaming y soporte
 * de `Range`, que es lo que `<video>` pide para arrancar y para adelantar.
 *
 * La ruta no es pública: pasa por el mismo cerco que `/api` (host confiable +
 * cookie firmada de la sesión del navegador). Un `<video>` manda la cookie
 * por ser same-origin, así que reproducir funciona igual en local y por
 * Tailscale.
 */

import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { isAbsolute } from "node:path";

const ROUTE = "/video-preview/stream";

/** Extensiones que el navegador puede reproducir (o casi). */
const MEDIA_TYPES = {
	mp4: "video/mp4",
	m4v: "video/mp4",
	mov: "video/quicktime",
	webm: "video/webm",
	mkv: "video/x-matroska",
	ogv: "video/ogg",
	ogg: "video/ogg"
};

/** Respuesta corta sin cuerpo útil. */
function sendText(res, status, headers, text) {
	res.writeHead(status, {
		"content-type": "text/plain; charset=utf-8",
		"cache-control": "no-store",
		...headers
	});
	res.end(text);
}

/** Tipo de medio por extensión, con un fallback genérico. */
function mediaTypeOf(path) {
	const dot = path.lastIndexOf(".");
	if (dot < 0) return "application/octet-stream";
	const extension = path.slice(dot + 1).toLowerCase();
	return MEDIA_TYPES[extension] ?? "application/octet-stream";
}

/**
 * Lee un `Range: bytes=…` de un solo tramo.
 * @param header - valor de la cabecera Range, si vino.
 * @param size - tamaño total del archivo.
 * @returns el tramo pedido, `null` si es insatisfacible, o `undefined` si hay
 * que servir el archivo completo (sin cabecera o con sintaxis que no se maneja).
 */
function parseRange(header, size) {
	if (typeof header !== "string") return void 0;
	const match = /^bytes=(\d*)-(\d*)$/u.exec(header.trim());
	if (match === null) return void 0;
	const rawStart = match[1] ?? "";
	const rawEnd = match[2] ?? "";
	if (rawStart === "" && rawEnd === "") return void 0;
	if (size === 0) return null;
	if (rawStart === "") {
		const suffix = Number(rawEnd);
		if (!Number.isSafeInteger(suffix) || suffix <= 0) return void 0;
		return { start: Math.max(0, size - suffix), end: size - 1 };
	}
	const start = Number(rawStart);
	const end = rawEnd === "" ? size - 1 : Number(rawEnd);
	if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end)) return void 0;
	if (start >= size) return null;
	return { start, end: Math.min(end, size - 1) };
}

export const inject = ["webServer", "connection"];

/**
 * @param ctx - host context with the web server and the connection gate.
 */
export function apply(ctx) {
	/** @param req - request del navegador. @param res - respuesta propia. */
	const handler = async (req, res) => {
		if (req.method !== "GET" && req.method !== "HEAD") {
			sendText(res, 405, { allow: "GET, HEAD" }, "method not allowed");
			return;
		}

		// Mismo cerco que /api: host confiable (loopback o --trusted-host) y
		// cookie de sesión válida. Sin esto, cualquier proceso local podría leer
		// el disco por esta ruta.
		const gate = ctx.connection;
		if (gate === void 0 || typeof gate.requestRejection !== "function") {
			sendText(res, 503, {}, "connection unavailable");
			return;
		}
		const rejection = gate.requestRejection(req);
		if (rejection !== void 0) {
			sendText(res, rejection, {}, rejection === 401 ? "unauthorized" : "forbidden");
			return;
		}

		const url = new URL(req.url ?? "/", "http://dsh.invalid");
		const path = url.searchParams.get("path");
		if (path === null || path.length === 0 || path.includes("\0") || !isAbsolute(path)) {
			sendText(res, 400, {}, "absolute path required");
			return;
		}

		let info;
		try {
			info = await stat(path);
		} catch (error) {
			const missing = error !== null && typeof error === "object" && error.code === "ENOENT";
			sendText(res, missing ? 404 : 403, {}, missing ? "not found" : "cannot read file");
			return;
		}
		if (!info.isFile()) {
			sendText(res, 403, {}, "not a regular file");
			return;
		}

		const size = info.size;
		const range = parseRange(req.headers.range, size);
		if (range === null) {
			res.writeHead(416, {
				"content-range": `bytes */${size}`,
				"accept-ranges": "bytes",
				"cache-control": "private, no-store"
			});
			res.end();
			return;
		}

		const start = range?.start ?? 0;
		const end = range?.end ?? Math.max(0, size - 1);
		const length = size === 0 ? 0 : end - start + 1;
		const headers = {
			"content-type": mediaTypeOf(path),
			"content-length": String(length),
			"accept-ranges": "bytes",
			"cache-control": "private, no-store",
			"x-content-type-options": "nosniff"
		};
		if (range !== void 0) headers["content-range"] = `bytes ${start}-${end}/${size}`;
		res.writeHead(range === void 0 ? 200 : 206, headers);

		if (req.method === "HEAD" || length === 0) {
			res.end();
			return;
		}

		const stream = createReadStream(path, { start, end });
		stream.on("error", () => {
			// La cabecera ya salió: no hay status que corregir, solo cortar.
			res.destroy();
		});
		req.on("close", () => {
			stream.destroy();
		});
		stream.pipe(res);
	};

	ctx.effect(() => ctx.webServer.register({
		kind: "exact",
		path: ROUTE,
		handler
	}), "video-preview: stream route");
}
