// verify/bash-guard.mjs — el candado de python3 dentro de bash decide bien.
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
	["bash sin python", "git status --short && ls ~/dotfiles"],
	["python de lectura con -c", "python3 -c \"import json;print(json.load(open('package.json')))\""],
	["python leyendo por stdin", "python3 - <<'PY'\nprint(open('README.md').read())\nPY"],
	["nombre de archivo con w", "python3 -c \"print(open('notas-w.md').read())\""],
	["python3 --version", "python3 --version"],
	["otra ruta absoluta de lectura", "/usr/bin/python3 -c \"print(1)\""],
];

const denied = [
	["open con modo w", "python3 - <<'PY'\nopen('a.md','w').write('x')\nPY"],
	["open con modo a", "python3 -c \"open('log.txt','a').write('x')\""],
	["open con modo x", "python3 -c \"open('nuevo.txt', 'x')\""],
	["ruta absoluta del interprete", "/usr/bin/python3 -c \"open('a.md','w').write('x')\""],
	["write_text", "python3 -c \"from pathlib import Path; Path('a.md').write_text('x')\""],
	["shutil", "python3 -c \"import shutil; shutil.copy('a','b')\""],
	["os.remove", "cd /tmp && python3 -c \"import os; os.remove('x')\""],
	["json.dump", "python3 -c \"import json;json.dump({'a':1}, open('a.json','w'))\""],
	["heredoc con open", "python3 - <<'EOF'\nimport yaml\nwith open('conf.yml','w') as f:\n    yaml.dump({'a': 1}, f)\nEOF"],
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
if (guard({ name: "edit", arguments: { command: "python3 -c \"open('a','w')\"" } }) !== undefined) {
	problems.push("bloqueó una herramienta que no es bash");
}

if (problems.length > 0) {
	console.error(problems.join("\n"));
	process.exit(1);
}

console.log(`bash-guard: ${allowed.length} permitidos · ${denied.length} bloqueados`);
