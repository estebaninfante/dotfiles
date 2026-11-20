/**
 * Archivos de una tarea: lo que explica el problema (imágenes, videos, PDFs,
 * logs, zip). Cada tarea tiene su carpeta en ~/.dsh/tasks/<id>/ y todo se sirve
 * desde ahí: el pedido que se guarda y el agente que después lo resuelve leen
 * los mismos bytes.
 *
 * La subida llega en crudo (no JSON) y se escribe en streaming: un video de
 * cientos de MB no tiene que entrar en memoria ni en el body de 64 KB.
 */
import { createWriteStream } from "node:fs";
import { mkdir, rename, rm, stat, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, extname, join, resolve } from "node:path";

const HOME = process.env.DSH_HOME ?? join(homedir(), ".dsh");
const ROOT = join(HOME, "tasks");

export const MAX_UPLOAD_BYTES = 512 * 1024 * 1024;

const MIME = {
	png: "image/png",
	jpg: "image/jpeg",
	jpeg: "image/jpeg",
	webp: "image/webp",
	gif: "image/gif",
	avif: "image/avif",
	bmp: "image/bmp",
	svg: "image/svg+xml",
	heic: "image/heic",
	mp4: "video/mp4",
	webm: "video/webm",
	mov: "video/quicktime",
	mkv: "video/x-matroska",
	avi: "video/x-msvideo",
	mp3: "audio/mpeg",
	ogg: "audio/ogg",
	wav: "audio/wav",
	m4a: "audio/mp4",
	pdf: "application/pdf",
	txt: "text/plain; charset=utf-8",
	md: "text/plain; charset=utf-8",
	log: "text/plain; charset=utf-8",
	csv: "text/csv; charset=utf-8",
	json: "application/json; charset=utf-8",
	zip: "application/zip",
	gz: "application/gzip",
	tar: "application/x-tar",
	har: "application/json; charset=utf-8",
	docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
	xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
	pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
};

/** De imagen a archivo: la UI decide con esto si muestra miniatura o fila. */
export function kindOf(name) {
	const ext = extname(String(name ?? "")).slice(1).toLowerCase();
	if (/^(png|jpe?g|webp|gif|avif|bmp|svg|heic)$/.test(ext)) return "image";
	if (/^(mp4|webm|mov|mkv|avi)$/.test(ext)) return "video";
	if (/^(mp3|ogg|wav|m4a)$/.test(ext)) return "audio";
	return "file";
}

export function mimeOf(name) {
	return MIME[extname(String(name ?? "")).slice(1).toLowerCase()] ?? "application/octet-stream";
}

/** Nombre de archivo seguro: sin carpetas, sin control ni caracteres raros. */
export function safeName(raw, fallback = "archivo") {
	const base = basename(String(raw ?? "").replace(/\\/g, "/")).trim();
	const cleaned = base
		.replace(/[\u0000-\u001f<>:"|?*]/g, "-")
		.replace(/^\.+/, "")
		.replace(/\s+/g, " ")
		.slice(-120)
		.trim();
	return cleaned || fallback;
}

export function taskDir(taskId) {
	return join(ROOT, String(taskId ?? "").replace(/[^A-Za-z0-9-]/g, ""));
}

function insideRoot(target) {
	const root = resolve(ROOT);
	const path = resolve(target);
	return path.startsWith(`${root}/`);
}

/** Ruta libre dentro de la tarea: si el nombre ya existe, agrega " (2)". */
async function uniquePath(dir, name) {
	const ext = extname(name);
	const stem = name.slice(0, name.length - ext.length);
	for (let index = 1; index < 500; index += 1) {
		const candidate = join(dir, index === 1 ? name : `${stem} (${index})${ext}`);
		try {
			await stat(candidate);
		} catch {
			return candidate;
		}
	}
	return join(dir, `${stem}-${Date.now()}${ext}`);
}

/**
 * Guarda un archivo subido y devuelve su registro para la tarea. El cuerpo se
 * escribe a un temporal y recién se renombra si entró completo y dentro del
 * límite: nunca queda un archivo a medias con el nombre final.
 */
export async function saveUpload(taskId, rawName, stream) {
	const dir = taskDir(taskId);
	if (!dir || !insideRoot(dir)) throw new Error("tarea inválida");
	await mkdir(dir, { recursive: true });
	const name = safeName(rawName);
	const target = await uniquePath(dir, name);
	const partial = `${target}.part`;
	const out = createWriteStream(partial);
	let size = 0;
	try {
		for await (const chunk of stream) {
			size += chunk.length;
			if (size > MAX_UPLOAD_BYTES) throw new Error("archivo demasiado grande (máximo 512 MB)");
			if (!out.write(chunk)) await new Promise((done) => out.once("drain", done));
		}
		await new Promise((done, fail) => out.end((error) => (error ? fail(error) : done())));
	} catch (error) {
		out.destroy();
		await unlink(partial).catch(() => {});
		throw error;
	}
	await rename(partial, target);
	return { name: basename(target), path: target, size, mime: mimeOf(target), kind: kindOf(target) };
}

/** Borra la carpeta de una tarea: los archivos no sobreviven a la tarea. */
export async function removeTaskFiles(taskId) {
	const dir = taskDir(taskId);
	if (!dir || !insideRoot(dir)) return;
	await rm(dir, { recursive: true, force: true }).catch(() => {});
}

/** Archivo de una tarea: solo dentro de ~/.dsh/tasks, nunca una ruta cualquiera. */
export function attachmentInfo(path) {
	const target = resolve(String(path ?? ""));
	if (!insideRoot(target)) return null;
	const name = basename(target);
	if (!name) return null;
	return { path: target, mime: mimeOf(target), kind: kindOf(target), name };
}

/** Quita un archivo adjunto del disco y de la tarea. */
export async function removeAttachment(path) {
	const info = attachmentInfo(path);
	if (!info) throw new Error("archivo fuera de la carpeta de tareas");
	await unlink(info.path);
	return { ok: true, path: info.path };
}

export { ROOT as ATTACHMENTS_ROOT };
