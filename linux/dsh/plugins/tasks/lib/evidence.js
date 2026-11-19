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
const MAX_FILES = 200;
const MAX_COMMANDS = 120;
const MAX_FAILURES = 40;
const MAX_TEXT = 4000;

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

/** Cruza las rutas que el agente nombró al cerrar contra los archivos que tocó de verdad. */
function checkClaims(declaration, files) {
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
		const match = files.find((file) => file.path === token || file.path.endsWith(token) || file.path.endsWith(`/${base}`));
		claims.push(
			match
				? { claim: token, verified: true, note: match.path === token ? "tocado en esta conversación" : `coincide con ${match.path}` }
				: { claim: token, verified: false, note: "nombrado, pero no aparece en las herramientas de archivos" },
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
			if (call.name === "bash" && typeof call.args.command === "string") {
				const command = short(call.args.command, 300);
				commands.push({ command, description: short(call.args.description ?? "", 120), exitCode, turn });
				if (exitCode !== null && exitCode !== 0) failures.push({ kind: "comando", detail: command, code: exitCode, turn });
			}
			if (call.name === "present" && Array.isArray(call.args.files)) {
				for (const file of call.args.files) {
					if (!file || typeof file.path !== "string") continue;
					deliverables.push({ path: file.path, description: short(file.description ?? "", 160), turn });
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
	const lastEnd = turns.at(-1) ?? null;

	return {
		stats: {
			turns: turns.length,
			tools,
			files: fileList.length,
			commands: commands.length,
			testsOk: commands.filter((item) => TEST_CMD.test(item.command) && item.exitCode === 0).length,
			testsFail: commands.filter((item) => TEST_CMD.test(item.command) && item.exitCode !== null && item.exitCode !== 0).length,
			deliverables: deliverables.length,
			failures: failures.length,
		},
		end: lastEnd,
		files: fileList,
		commands: commands.slice(-MAX_COMMANDS),
		tests: commands.filter((item) => TEST_CMD.test(item.command)).slice(-20),
		deliverables,
		failures: failures.slice(0, MAX_FAILURES),
		todos,
		declaration: declaration ? { turn: lastTurn, text: declaration } : null,
		claims: checkClaims(declaration, fileList),
		cwd: options.cwd ?? null,
	};
}
