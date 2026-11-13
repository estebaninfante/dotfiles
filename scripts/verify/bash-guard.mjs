// verify/bash-guard.mjs — el candado de bash decide bien: editar va por edit/write.
//
// Carga el plugin real, captura el guard que registra contra un ctx falso y
// prueba comandos permitidos y prohibidos. Sin servidor ni sesión.
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pluginPath = resolve(here, "../../linux/dsh/plugins/bash-guard/lib/index.js");
const plugin = await import(pluginPath);

let guard;
const ctx = {
	tools: {
		guard(registered) {
			guard = registered;
			return () => {};
		},
	},
	effect(fn) {
		fn();
		return () => {};
	},
};

plugin.apply(ctx);
if (typeof guard !== "function") throw new Error("el plugin no registró ningún guard");

const run = (command, name = "bash") => guard({ name, arguments: { command, description: "prueba" } });

const allowed = [
	["lectura normal", "git status --short && ls ~/dotfiles"],
	["redirección a /dev/null", "npm test >/dev/null 2>&1"],
	["redirección de fd", "cmd 2>&1 | tail -5"],
	["script existente", "~/dotfiles/scripts/publish.sh --yes"],
	["CLI del sistema", "machine scan"],
	["git", "git commit -m prueba && git push"],
	["descarga", "curl -o /tmp/x.json https://example.com/x.json"],
	["mover y borrar", "mv /tmp/a /tmp/b && rm -f /tmp/c"],
	["python de lectura", "python3 -c \"print(open('README.md').read())\""],
	["node de lectura", "node -e \"console.log(require('fs').readFileSync('p','utf8'))\""],
	["sed sin -i", "sed -n '1,10p' archivo.md"],
];

const denied = [
	["redirect con echo", "echo hola > notas.md"],
	["redirect append", "printf 'x\\n' >> notas.md"],
	["redirect con heredoc", "cat <<'EOF' > notas.md\nhola\nEOF"],
	["redirect de stderr a archivo", "cmd 2> errores.log"],
	["sed -i", "sed -i 's/a/b/' notas.md"],
	["tee", "echo hola | tee notas.md"],
	["awk inplace", "awk -i inplace '{print}' notas.md"],
	["truncate", "truncate -s 0 notas.md"],
	["dd", "dd if=/dev/zero of=notas.md bs=1 count=10"],
	["python open w", "python3 - <<'PY'\nopen('notas.md','w').write('x')\nPY"],
	["python write_text", "python3 -c \"from pathlib import Path; Path('a.md').write_text('x')\""],
	["python shutil", "python3 -c \"import shutil; shutil.copy('a','b')\""],
	["python os.remove", "cd /tmp && python3 -c \"import os; os.remove('x')\""],
	["node writeFileSync", "node -e \"require('fs').writeFileSync('a.md','x')\""],
	["ruby File.write", "ruby -e \"File.write('a.md','x')\""],
];

const problems = [];
for (const [label, command] of allowed) {
	const reason = run(command);
	if (reason !== undefined) problems.push(`permitido bloqueado: ${label} → ${reason}`);
}
for (const [label, command] of denied) {
	if (run(command) === undefined) problems.push(`prohibido que pasó: ${label}`);
}

// El guard no mira herramientas que no son bash.
if (guard({ name: "edit", arguments: { command: "echo hola > x" } }) !== undefined) {
	problems.push("bloqueó una herramienta que no es bash");
}
// Un `bash` vacío no se bloquea (el schema lo rechaza antes).
if (run("   ") !== undefined) problems.push("bloqueó un comando vacío");

if (problems.length > 0) {
	console.error(problems.join("\n"));
	process.exit(1);
}

console.log(`bash-guard: ${allowed.length} permitidos · ${denied.length} bloqueados`);
