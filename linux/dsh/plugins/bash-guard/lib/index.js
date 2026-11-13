/**
 * dsh-local-bash-guard — candado del tool `bash`.
 *
 * Prohibe editar archivos con `python3` desde bash. El cambio tiene que ir por
 * las herramientas `edit`/`write`: así el usuario ve el diff al final del turno
 * y el archivo se escribe con el guard de versión del harness.
 *
 * Es determinista: no consulta al modelo ni al usuario. `ctx.tools.guard`
 * devuelve un motivo y el harness convierte la llamada en error antes de
 * ejecutarla.
 *
 * Límite conocido: solo mira el comando que se manda. Un `python3 script.py`
 * que por dentro escribe no se puede detectar sin ejecutarlo; para eso está la
 * regla escrita en `reglas-harness.md`.
 *
 * @module dsh-local-bash-guard
 */

export const name = "dsh-local-bash-guard";
export const inject = ["tools"];

/** `python`, `python3`, `python3.12`, con o sin ruta (`/usr/bin/python3`, `.venv/bin/python`). */
const PYTHON = /(?:^|[\s;|&(`/])python3?(?:\.[0-9]+)?(?=$|[\s;|&)`])/;

/** Escrituras por método directo o por módulo. */
const WRITE_CALLS = [
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

const DENIED =
	"Prohibido editar archivos con python3 dentro de bash. " +
	"Usá la herramienta `edit` o `write`: el cambio queda visible (diff al final del turno) y protegido contra escrituras viejas. " +
	"Si necesitás generar datos, escribí el archivo con `write` o dejá un script y corrélo sin tocar archivos del repo.";

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
	if (typeof command !== "string" || !PYTHON.test(command)) return false;
	if (opensForWriting(command)) return true;
	return WRITE_CALLS.some((pattern) => pattern.test(command));
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
	return pythonWritesFiles(command) ? DENIED : undefined;
}

/**
 * Registra el candado global.
 * @param {import("@deepseek-ai/cordis").Context} ctx
 */
export function apply(ctx) {
	ctx.effect(() => ctx.tools.guard((execution) => denialReason(execution)), "bash-guard: python3 no edita archivos");
}
