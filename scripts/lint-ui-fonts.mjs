#!/usr/bin/env node
/**
 * lint-ui-fonts — reglas de estética de la UI del harness (tareas, evidencia,
 * carpeta y panel de tareas):
 *   - prohíbe tipografía monoespaciada: la UI usa la del sistema;
 *   - prohíbe el gris de `bg-layer-3` como fondo: el usuario rechazó ese color.
 * Falla con archivo:línea.
 *
 * Uso: node ~/dotfiles/scripts/lint-ui-fonts.mjs
 */
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const ROOT = join(process.env.HOME ?? "", "dotfiles/linux/dsh/plugins");
const PLUGINS = ["tasks", "evidence", "folder", "board"];
const RULES = [
	{ pattern: /\bmonospace\b/i, message: "tipografía monoespaciada prohibida; usá la del sistema" },
	{ pattern: /\bbg-layer-3\b/, message: "fondo gris prohibido (bg-layer-3); usá layer-1 o layer-2" },
];

let problems = 0;
for (const plugin of PLUGINS) {
	const dir = join(ROOT, plugin, "lib");
	const files = await readdir(dir).catch(() => []);
	for (const file of files) {
		if (!file.endsWith(".js")) continue;
		const lines = (await readFile(join(dir, file), "utf8")).split("\n");
		lines.forEach((line, index) => {
			for (const rule of RULES) {
				if (!rule.pattern.test(line)) continue;
				problems += 1;
				console.error(`${plugin}/lib/${file}:${index + 1}: ${rule.message}`);
			}
		});
	}
}

if (problems > 0) {
	console.error(`\nlint-ui-fonts: ${problems} problema(s).`);
	process.exit(1);
}
console.log("lint-ui-fonts: sin monoespaciada ni bg-layer-3 en la UI");
