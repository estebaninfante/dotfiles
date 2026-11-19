/**
 * Imágenes y videos de la evidencia: qué rutas son servibles y cómo se
 * enriquecen con tamaño y URL. Solo home y /tmp, solo extensiones conocidas.
 */
import { stat } from "node:fs/promises";
import { homedir } from "node:os";
import { extname, resolve } from "node:path";

export const MAX_MEDIA_BYTES = 120 * 1024 * 1024;

const MIME = {
	png: "image/png",
	jpg: "image/jpeg",
	jpeg: "image/jpeg",
	webp: "image/webp",
	gif: "image/gif",
	avif: "image/avif",
	bmp: "image/bmp",
	svg: "image/svg+xml",
	mp4: "video/mp4",
	webm: "video/webm",
	mov: "video/quicktime",
	mkv: "video/x-matroska",
};

/** Solo imágenes y videos bajo el home o /tmp: nunca URLs, binarios ni rutas raras. */
export function mediaInfo(path) {
	const target = resolve(path);
	const home = homedir();
	if (target !== home && !target.startsWith(`${home}/`) && !target.startsWith("/tmp/")) return null;
	const mime = MIME[extname(target).slice(1).toLowerCase()];
	if (!mime) return null;
	return { path: target, mime };
}

export async function readableMedia(path) {
	const info = mediaInfo(path);
	if (!info) return null;
	try {
		const details = await stat(info.path);
		if (!details.isFile() || details.size <= 0 || details.size > MAX_MEDIA_BYTES) return null;
		return { ...info, bytes: details.size, url: `/tasks/media?path=${encodeURIComponent(info.path)}` };
	} catch {
		return null;
	}
}

/** Deja solo las pruebas que existen y se pueden servir. */
export async function enrichMedia(evidence) {
	const media = [];
	for (const item of evidence.media) {
		const readable = await readableMedia(item.path);
		if (readable) media.push({ ...item, ...readable });
	}
	evidence.media = media;
	evidence.stats.media = media.length;
	return evidence;
}
