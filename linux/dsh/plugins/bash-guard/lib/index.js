/**
 * dsh-local-bash-guard — candado del tool `bash`.
 *
 * Los archivos se editan con las herramientas `edit`/`write` del harness, no
 * desde bash. Así el usuario ve el diff al final del turno y la escritura pasa
 * por el guard de versión del archivo.
 *
 * Bloquea las ediciones "ad-hoc" escritas dentro del comando: redirecciones a
 * archivo, `sed -i`, `tee`, `awk` en sitio, `truncate`, `dd of=`, y los
 * intérpretes con escritura inline (python, node, ruby, perl).
 *
 * No bloquea operaciones ni automatización: `cp`, `mv`, `rm`, `ln`, `git`,
 * `npm`, `curl -o`, ni correr scripts existentes (`scripts/publish.sh`,
 * `machine scan`) — lo que un script hace por dentro no lo ve este guard.
 *
 * Además cuida la sesión del usuario: bloquea input sintético (`ydotool`,
 * `wtype`, `xdotool`, `wmctrl`), capturas de sus pantallas (`grim`, `slurp`,
 * `wf-recorder` salvo sobre la salida virtual), `hyprctl` que le mueve el
 * workspace o el monitor, abrir apps con `pantalla-agente abrir` y lanzar GUI
 * fuera del asiento. El camino sancionado es `agent-seat` (GUI) y
 * `pantalla-agente montar/capturar` (sólo capturas).
 *
 * Es determinista: mira el texto del comando y devuelve un motivo; el harness
 * convierte la llamada en error antes de ejecutarla.
 *
 * El motivo se explica solo: nombra el guard, dice qué regla se disparó y da la
 * salida para el caso que no era una edición (el agente le pide permiso al
 * usuario y reintenta con `DSH_GUARD_ALLOW=1` adelante).
 *
 * @module dsh-local-bash-guard
 */

export const name = "dsh-local-bash-guard";
export const inject = ["tools"];

/** Prefijo de escape: el usuario autoriza la escritura. Va primero en el comando. */
const OVERRIDE = /^\s*DSH_GUARD_ALLOW=1\s+/;

const DENIED =
	"bash-guard bloqueó el comando: escribiría un archivo desde bash. " +
	"Las ediciones van por `edit`/`write` para que el usuario vea el diff y la escritura pase por el guard de versión. " +
	"Si NO ibas a editar un archivo (captura, diagnóstico, temporal, prueba), decíselo al usuario y pedile permiso: " +
	"con su OK reintentá el mismo comando con `DSH_GUARD_ALLOW=1` adelante. No lo uses por tu cuenta. " +
	"El tool bash ya devuelve stdout y stderr: para diagnosticar no hace falta redirigir a un archivo.";

/** Destinos de redirección que no escriben un archivo real. */
const HARMLESS_TARGET = /^\/(?:dev\/(?:null|stdout|stderr|zero|full|fd\/[0-9]+)|proc\/self\/fd\/[0-9]+)$/;

/** Caracteres que cortan un destino de redirección (`2>/dev/null)` corta en `)`). */
const TARGET_END = /[\s|;&<>()]/;

/** Intérpretes y comandos que escriben archivos en el mismo comando. */
const WRITE_PATTERNS = [
	[/\bsed\b[^\n|;&]*\s(?:-i|--in-place)/, "sed -i"],
	[/\bperl\b[^\n|;&]*\s(?:-[a-zA-Z]*i|--in-place)/, "perl -i"],
	[/\bawk\b[^\n|;&]*\binplace\b/, "awk -i inplace"],
	[/\btee\b(?:\s+-[a-zA-Z]+)*\s+\S/, "tee"],
	[/\bsponge\b/, "sponge"],
	[/\btruncate\b[^\n|;&]*\s-s\b/, "truncate -s"],
	[/\bdd\b[^\n|;&]*\bof=/, "dd of="],
	[/\bmkfifo\b/, "mkfifo"],
	[/\bnode\b[^\n]*\b(?:writeFileSync|writeFile|appendFileSync|appendFile|createWriteStream|copyFileSync|renameSync|rmSync|unlinkSync)\b/, "node fs"],
	[/\bruby\b[^\n]*\b(?:File\.write|File\.open|IO\.write|FileUtils)\b/, "ruby File"],
];

/** `python`/`python3`, con o sin ruta (`/usr/bin/python3`, `.venv/bin/python`). */
const PYTHON = /(?:^|[\s;|&(`/])python3?(?:\.[0-9]+)?(?=$|[\s;|&)`])/;

const PY_WRITE_CALLS = [
	/\.write_text\s*\(/,
	/\.write_bytes\s*\(/,
	/\.writelines\s*\(/,
	/\bos\.(?:replace|rename|remove|unlink|makedirs|mkdir|rmdir|symlink|link)\s*\(/,
	/\bshutil\.(?:copy|copy2|copyfile|copyfileobj|move|rmtree)\s*\(/,
	/\bjson\.dump\s*\(/,
	/\byaml\.dump\s*\(/,
	/\btoml\.dump\s*\(/,
	/\bPath\s*\([^()]*\)\.(?:write_text|write_bytes|touch|mkdir|unlink|rename|replace)\s*\(/,
];

/**
 * Lee el destino de una redirección, respetando comillas y escapes.
 * `2>"/dev/null"` da `/dev/null`; `2>/dev/null)` corta en `)`.
 * @param {string} command
 * @param {number} start
 * @returns {{ target: string, next: number }}
 */
function readTarget(command, start) {
	let target = "";
	let quote = null;
	let i = start;
	for (; i < command.length; i++) {
		const ch = command[i];
		if (ch === "\\" && quote !== "'") {
			i++;
			if (i < command.length) target += command[i];
			continue;
		}
		if (quote) {
			if (ch === quote) quote = null;
			else target += ch;
			continue;
		}
		if (ch === "'" || ch === '"') {
			quote = ch;
			continue;
		}
		if (TARGET_END.test(ch)) break;
		target += ch;
	}
	return { target, next: i };
}

/**
 * Destino de la primera redirección que escribe un archivo (`>`, `>>`, `&>`,
 * `2>`), salvo `/dev/*`, o `null` si no hay.
 *
 * Mira el comando fuera de comillas: `echo "a > b"` no redirige y
 * `ps -p $(cat x.pid 2>/dev/null)` no escribe. No confunde flechas (`->`) ni
 * comparaciones (`>=`).
 * @param {string} command
 * @returns {string | null} destino, para nombrarlo en el motivo
 */
function redirectTarget(command) {
	let quote = null;
	for (let i = 0; i < command.length; i++) {
		const ch = command[i];
		if (ch === "\\" && quote !== "'") {
			i++;
			continue;
		}
		if (quote) {
			if (ch === quote) quote = null;
			continue;
		}
		if (ch === "'" || ch === '"') {
			quote = ch;
			continue;
		}
		if (ch !== ">") continue;
		if (command[i + 1] === "&" || command[i + 1] === "=") {
			i++;
			continue;
		}
		const prev = command[i - 1] ?? "";
		if (prev === "-" || prev === "<" || prev === "=") continue;
		let j = i + 1;
		if (command[j] === ">") j++;
		while (command[j] === " " || command[j] === "\t") j++;
		const { target, next } = readTarget(command, j);
		if (!HARMLESS_TARGET.test(target)) return target;
		i = Math.max(i, next - 1);
	}
	return null;
}

/**
 * ¿El comando abre un archivo en modo escritura? Se mira el segundo argumento
 * de `open(...)`, no el nombre: `open("a-w.txt")` es lectura.
 * @param {string} command
 * @returns {boolean}
 */
function opensForWriting(command) {
	for (const match of command.matchAll(/\bopen\s*\(([^()]*)\)/g)) {
		const mode = match[1].match(/,\s*(['"])([^'"]*)\1/);
		if (mode && /[wax]/.test(mode[2])) return true;
	}
	return false;
}

/**
 * ¿El comando invoca python y además escribe archivos?
 * @param {string} command
 * @returns {boolean}
 */
export function pythonWritesFiles(command) {
	if (!PYTHON.test(command)) return false;
	if (opensForWriting(command)) return true;
	return PY_WRITE_CALLS.some((pattern) => pattern.test(command));
}

/** Motivo para comandos que invaden la sesión del usuario. */
const SESSION_DENIED =
	"bash-guard bloqueó el comando: tocaría la sesión del usuario (cursor, foco, workspace o sus ventanas). " +
	"Para GUI usá `agent-seat` (skill `agent-seat`): apps sandboxeadas en su workspace, con puntero y teclado propios. " +
	"Para capturas usá `pantalla-agente montar/capturar` o `evidencia`. " +
	"Si de verdad necesitás esto, pedile permiso al usuario y reintentá con `DSH_GUARD_ALLOW=1` adelante.";

/** Reglas de sesión: [patrón, qué dispara]. */
const SESSION_PATTERNS = [
	[/\b(?:ydotool|wtype|xdotool|wmctrl)\b/, "input sintético en el seat del usuario"],
	[/\bgrim\b(?![^\n]*\b(?:AGENTE-1|HEADLESS))/,
		"captura de las pantallas del usuario (usá `agent-seat screenshot` o `pantalla-agente capturar`)"],
	[/\b(?:slurp|wf-recorder)\b(?![^\n]*\b(?:AGENTE-1|HEADLESS))/,
		"captura/grabación de las pantallas del usuario (usá `evidencia`)"],
	[/\bhyprctl\s+(?:dispatch|keyword)\b[^\n]*\b(?:workspace|movetoworkspace|focusmonitor|focusworkspace|swapactiveworkspaces|renameworkspace)\b/,
		"mover el workspace o el monitor del usuario"],
	[/\bpantalla-agente\b/,
		"pantalla-agente está retirado: capturá con `agent-seat screenshot` o `evidencia`"],
];

/**
 * Lanzamiento de una GUI en el seat del usuario: el binario al principio de un
 * segmento, con wrappers habituales delante. Las apariciones dentro de scripts
 * o en un `node -e` no cuentan; tampoco los chequeos (`command -v`).
 */
const GUI_LAUNCH =
	/(?:^|[;&|]\s*)(?:(?:setsid|env|nohup|uwsm-app)\s+|timeout\s+\d+\s+)*(?:chromium|chromium-browser|google-chrome(?:-stable)?|brave|brave-browser|firefox|foot|kitty|alacritty|xdg-open)\b/;

/** Excusas válidas: no abren una ventana en la sesión del usuario. */
const GUI_EXCUSAS = /(?:--headless|agent-seat\b|command\s+-v|which\s|type\s+-p|pacman\s+-Q)/;

/**
 * Regla de sesión que se dispara, o `undefined` si el comando es seguro.
 * @param {string} command
 * @returns {string | undefined}
 */
export function sessionDenial(command) {
	for (const [pattern, why] of SESSION_PATTERNS) {
		if (pattern.test(command)) return why;
	}
	if (GUI_LAUNCH.test(command) && !GUI_EXCUSAS.test(command)) {
		return "abrir una GUI en las pantallas del usuario (usá `agent-seat run`)";
	}
	return undefined;
}

/**
 * Regla que se dispara, para nombrarla en el motivo: `redirección a archivo
 * (/tmp/x)`, `python escribe un archivo`, `sed -i`, … O `undefined` si pasa.
 * @param {string} command
 * @returns {string | undefined}
 */
function findDenial(command) {
	const target = redirectTarget(command);
	if (target !== null) return `redirección a archivo (${target})`;
	if (pythonWritesFiles(command)) return "python escribe un archivo";
	const rule = WRITE_PATTERNS.find(([pattern]) => pattern.test(command));
	if (rule) return rule[1];
	return undefined;
}

/**
 * Motivo de denegación para una ejecución del harness, o `undefined` si pasa.
 * @param {{ name?: string, arguments?: unknown }} execution
 * @returns {string | undefined}
 */
export function denialReason(execution) {
	const tool = execution && typeof execution.name === "string" ? execution.name : "";
	if (tool !== "bash" && !tool.startsWith("bash")) return undefined;
	const args = execution && typeof execution.arguments === "object" && execution.arguments !== null
		? execution.arguments
		: {};
	const command = typeof args.command === "string" ? args.command : "";
	if (command.trim() === "") return undefined;
	if (OVERRIDE.test(command)) return undefined;
	const sesion = sessionDenial(command);
	if (sesion !== undefined) return `${SESSION_DENIED}\nMotivo: ${sesion}.`;
	const rule = findDenial(command);
	if (rule === undefined) return undefined;
	return `${DENIED}\nMotivo: ${rule}.`;
}

/**
 * Registra el candado global.
 * @param {import("@deepseek-ai/cordis").Context} ctx
 */
export function apply(ctx) {
	ctx.effect(() => ctx.tools.guard((execution) => denialReason(execution)), "bash-guard: bash no edita archivos");
}
