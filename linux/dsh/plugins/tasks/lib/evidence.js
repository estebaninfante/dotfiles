/**
 * Convierte el log real de una sesión en evidencia verificable: qué archivos
 * tocó, qué comandos corrió (y cómo terminaron), qué tests pasaron, qué
 * entregables presentó y qué dijo el agente al cerrar. Nada de esto lo declara
 * el agente: sale de sus tool calls y resultados.
 */

const FILE_TOOLS = new Map([
	["write", "creado"],
	["edit", "modificado"],
	["multiedit", "modificado"],
	["str_replace_editor", "modificado"],
	["apply_patch", "modificado"],
]);

const TEST_CMD =
	/(?:^|[^\w-])(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?(?:test|tests|check|lint|typecheck|type-check|build|e2e)\b|\b(?:pytest|vitest|jest|tsc|svelte-check|vue-tsc|go\s+test|cargo\s+test|node\s+--test|make\s+test|bun\s+test)\b/i;

const EXIT_MARK = /\[exit code: (\d+)\]/;
const PATH_TOKEN = /(?:~\/|\/)[^\s"'`()[\]<>,;]+/g;
// Solo una captura o grabación cuenta como prueba: nombrar o borrar un archivo no prueba nada.
const CAPTURE_CMD = /\b(captur\w*|screenshot\w*|grim|scrot|ffmpeg|record\w*|grab\w*|snapshot\w*)\b/i;
const MAX_FILES = 200;
const MAX_COMMANDS = 120;
const MAX_FAILURES = 40;
const MAX_TEXT = 4000;
const MAX_MEDIA = 20;
const MEDIA_EXT = /\.(?:png|jpe?g|webp|gif|avif|bmp|svg|mp4|webm|mov|mkv)$/i;
const MEDIA_IN_TEXT = /(?:~\/|\/|\.{1,2}\/)[^\s"'`;|&()<>,]*\.(?:png|jpe?g|webp|gif|avif|bmp|svg|mp4|webm|mov|mkv)\b/gi;
const MEDIA_SOURCE = { adjunto: 3, captura: 2, entregable: 1 };

function parseJson(value) {
	if (typeof value !== "string") return value && typeof value === "object" ? value : {};
	try {
		const parsed = JSON.parse(value);
		return parsed && typeof parsed === "object" ? parsed : {};
	} catch {
		return {};
	}
}

function textOf(message) {
	if (!message || !Array.isArray(message.content)) return "";
	return message.content
		.filter((part) => part && part.type === "text" && typeof part.text === "string")
		.map((part) => part.text)
		.join("\n")
		.trim();
}

function short(value, max) {
	const text = String(value ?? "").replace(/\s+/g, " ").trim();
	return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

function fileLike(token) {
	const last = token.split("/").pop() ?? "";
	return last.includes(".") && !last.endsWith(".");
}

/** Una imagen o video que el agente miró, capturó o entregó: prueba que se puede ver. */
function addMedia(media, path, source, turn) {
	const value = String(path ?? "").trim();
	if (!value || !MEDIA_EXT.test(value)) return;
	const known = media.get(value);
	const rank = MEDIA_SOURCE[source] ?? 0;
	if (known === undefined) {
		media.set(value, { path: value, kind: /\.(?:mp4|webm|mov|mkv)$/i.test(value) ? "video" : "imagen", source, turn });
	} else if (rank > (MEDIA_SOURCE[known.source] ?? 0)) {
		known.source = source;
	}
}

function collectMedia(media, text, source, turn) {
	for (const match of String(text ?? "").matchAll(MEDIA_IN_TEXT)) addMedia(media, match[0], source, turn);
}

/** Cruza las rutas que el agente nombró al cerrar contra lo que hizo de verdad. */
function checkClaims(declaration, touched) {
	const claims = [];
	if (!declaration) return claims;
	const seen = new Set();
	const paths = declaration.match(PATH_TOKEN) ?? [];
	for (const raw of paths) {
		const token = raw.replace(/[.,:;]+$/, "");
		if (!fileLike(token) || seen.has(token)) continue;
		seen.add(token);
		if (claims.length >= 12) break;
		const base = token.split("/").pop();
		const match = touched.find((item) => item.path === token || item.path.endsWith(token) || item.path.endsWith(`/${base}`));
		claims.push(
			match
				? {
						claim: token,
						verified: true,
						note: match.via === "entregable" ? "presentado como entregable" : match.path === token ? "tocado en esta conversación" : `coincide con ${match.path}`,
					}
				: { claim: token, verified: false, note: "nombrado, pero no aparece en las herramientas de archivos ni en los entregables" },
		);
	}
	return claims;
}

/** @returns evidencia lista para la UI, sin campos internos del log. */
export function summarizeEvidence(events, options = {}) {
	const calls = new Map();
	const files = new Map();
	const commands = [];
	const deliverables = [];
	const failures = [];
	const turns = [];
	const texts = new Map();
	const todos = [];
	const media = new Map();
	let tools = 0;

	for (const event of Array.isArray(events) ? events : []) {
		if (!event || typeof event.type !== "string") continue;
		if (event.type === "tool/call") {
			const callId = String(event.data?.callId ?? "");
			if (!callId) continue;
			tools += 1;
			calls.set(callId, {
				name: String(event.data?.name ?? ""),
				args: parseJson(event.data?.arguments),
				turn: Number(event.data?.turn ?? 0),
			});
			continue;
		}
		if (event.type === "tool/result") {
			const callId = String(event.data?.message?.source?.callId ?? event.data?.message?.toolCallId ?? "");
			const call = calls.get(callId);
			if (!call) continue;
			const message = event.data?.message;
			const output = textOf(message);
			const failed = message?.isError === true || event.data?.error != null;
			const exit = EXIT_MARK.exec(output);
			const exitCode = exit ? Number(exit[1]) : failed ? null : 0;
			const turn = call.turn || Number(event.data?.turn ?? 0);

			const fileAction = FILE_TOOLS.get(call.name);
			if (fileAction && !failed && typeof call.args.file_path === "string") {
				const path = call.args.file_path;
				const known = files.get(path);
				if (!known) files.set(path, { path, action: fileAction, turn });
				else if (fileAction === "creado") known.action = "creado";
			}
			if (call.name === "read_image" && typeof call.args.path === "string") {
				addMedia(media, call.args.path, "adjunto", turn);
			}
			for (const path of output.matchAll(/<path>([^<]+)<\/path>/g)) addMedia(media, path[1], "adjunto", turn);
			if (call.name === "bash" && typeof call.args.command === "string") {
				const command = short(call.args.command, 300);
				commands.push({ command, description: short(call.args.description ?? "", 120), exitCode, turn });
				if (CAPTURE_CMD.test(call.args.command)) collectMedia(media, call.args.command, "captura", turn);
				if (exitCode !== 0) failures.push({ kind: "comando", detail: command, code: exitCode, turn });
			}
			if (call.name === "present" && Array.isArray(call.args.files)) {
				for (const file of call.args.files) {
					if (!file || typeof file.path !== "string") continue;
					deliverables.push({ path: file.path, description: short(file.description ?? "", 160), turn });
					addMedia(media, file.path, "entregable", turn);
				}
			}
			if (call.name === "todo_write" && Array.isArray(call.args.todos)) {
				todos.length = 0;
				for (const todo of call.args.todos) {
					if (!todo || typeof todo.content !== "string") continue;
					todos.push({ content: short(todo.content, 160), status: String(todo.status ?? "") });
				}
			}
			if (failed && call.name !== "bash") {
				failures.push({ kind: call.name || "tool", detail: short(output || event.data?.error?.message || "error", 200), turn });
			}
			continue;
		}
		if (event.type === "turn/end") {
			const reason = event.data?.reason ?? {};
			turns.push({ turn: Number(event.data?.turn ?? turns.length + 1), reason: String(reason.kind ?? "?"), error: short(reason.error?.message ?? "", 200) || null });
			continue;
		}
		if (event.type === "assistant/message") {
			const turn = Number(event.data?.turn ?? 0);
			const text = textOf(event.data?.message);
			if (text) texts.set(turn, text);
		}
	}

	const lastTurn = [...texts.keys()].sort((a, b) => a - b).at(-1);
	const declaration = lastTurn === undefined ? "" : short(texts.get(lastTurn), MAX_TEXT);
	const fileList = [...files.values()].slice(0, MAX_FILES);
	const mediaList = [...media.values()].slice(0, MAX_MEDIA);
	const lastEnd = turns.at(-1) ?? null;

	return {
		stats: {
			turns: turns.length,
			tools,
			files: fileList.length,
			commands: commands.length,
			testsOk: commands.filter((item) => TEST_CMD.test(item.command) && item.exitCode === 0).length,
			testsFail: commands.filter((item) => TEST_CMD.test(item.command) && item.exitCode !== 0).length,
			deliverables: deliverables.length,
			failures: failures.length,
			media: mediaList.length,
		},
		end: lastEnd,
		media: mediaList.map((item) => ({ ...item, label: item.path.split("/").pop() })),
		files: fileList,
		commands: commands.slice(-MAX_COMMANDS),
		tests: commands.filter((item) => TEST_CMD.test(item.command)).slice(-20),
		deliverables,
		failures: failures.slice(0, MAX_FAILURES),
		todos,
		declaration: declaration ? { turn: lastTurn, text: declaration } : null,
		claims: checkClaims(declaration, [
			...fileList.map((file) => ({ path: file.path, via: "archivo" })),
			...deliverables.map((file) => ({ path: file.path, via: "entregable" })),
		]),
		cwd: options.cwd ?? null,
	};
}
