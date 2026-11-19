#!/usr/bin/env node
/**
 * lint-ui-fonts — prohíbe tipografía monoespaciada en la UI de tareas, evidencia
 * y carpeta. La UI usa la tipografía del sistema; el usuario rechazó la mono en
 * estados, rutas y metadatos. Falla con archivo:línea.
 *
 * Uso: node ~/dotfiles/scripts/lint-ui-fonts.mjs
 */
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const ROOT = join(process.env.HOME ?? "", "dotfiles/linux/dsh/plugins");
const PLUGINS = ["tasks", "evidence", "folder"];
const BANNED = /\bmonospace\b/i;

let problems = 0;
for (const plugin of PLUGINS) {
	const dir = join(ROOT, plugin, "lib");
	const files = await readdir(dir).catch(() => []);
	for (const file of files) {
		if (!file.endsWith(".js")) continue;
		const lines = (await readFile(join(dir, file), "utf8")).split("\n");
		lines.forEach((line, index) => {
			if (!BANNED.test(line)) return;
			problems += 1;
			console.error(`${plugin}/lib/${file}:${index + 1}: tipografía monoespaciada prohibida en la UI`);
		});
	}
}

if (problems > 0) {
	console.error(`\nlint-ui-fonts: ${problems} problema(s). Usá la tipografía del sistema.`);
	process.exit(1);
}
console.log("lint-ui-fonts: sin tipografía monoespaciada en la UI");
