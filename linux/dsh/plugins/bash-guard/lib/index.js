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
 * Es determinista: mira el texto del comando y devuelve un motivo; el harness
 * convierte la llamada en error antes de ejecutarla.
 *
 * @module dsh-local-bash-guard
 */

export const name = "dsh-local-bash-guard";
export const inject = ["tools"];

const DENIED =
	"Editar archivos desde bash está prohibido. " +
	"Usá la herramienta `edit` (cambios puntuales) o `write` (archivo completo): " +
	"el cambio queda visible (diff al final del turno) y protegido contra escrituras viejas. " +
	"Para datos de prueba generados, creá el archivo con `write`.";

/** Destinos de redirección que no escriben un archivo real. */
const HARMLESS_TARGET = /^\/(?:dev\/(?:null|stdout|stderr|zero|full)|proc\/self\/fd\/[0-9]+)$/;

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
 * Redirección que escribe un archivo (`>`, `>>`, `2>`, `&>`), salvo `/dev/*`.
 * @param {string} command
 * @returns {boolean}
 */
function redirectsToFile(command) {
	for (const match of command.matchAll(/(?:^|[^&<])>{1,2}(?!&)\s*([^\s|;&<>]+)/g)) {
		if (HARMLESS_TARGET.test(match[1])) continue;
		return true;
	}
	return false;
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
	if (redirectsToFile(command)) return DENIED;
	if (pythonWritesFiles(command)) return DENIED;
	if (WRITE_PATTERNS.some(([pattern]) => pattern.test(command))) return DENIED;
	return undefined;
}

/**
 * Registra el candado global.
 * @param {import("@deepseek-ai/cordis").Context} ctx
 */
export function apply(ctx) {
	ctx.effect(() => ctx.tools.guard((execution) => denialReason(execution)), "bash-guard: bash no edita archivos");
}
