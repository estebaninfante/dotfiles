// verify/web-search-rustxng.mjs — el web_search del harness sale por RustXNG.
//
// Carga el plugin real, captura el provider que registra contra un ctx falso y
// hace dos búsquedas de verdad: la primera levanta el servicio, la segunda lo
// reusa. Sin harness y sin sesión. Necesita red (RustXNG consulta sus motores).
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pluginPath = resolve(here, "../../linux/dsh/plugins/web-search-rustxng/lib/index.js");
const plugin = await import(pluginPath);

let provider;
const ctx = {
	web: {
		registerSearchProvider(registered) {
			provider = registered;
			return () => {};
		},
	},
};

plugin.apply(ctx, { idleSeconds: 60 });
if (provider === undefined) throw new Error("el plugin no registró ningún provider");
if (provider.id !== plugin.PROVIDER_ID) throw new Error(`id inesperado: ${provider.id}`);
if (!provider.available()) throw new Error("el provider se declara no disponible");

const checkSources = (label, result) => {
	if (!Array.isArray(result.sources)) throw new Error(`${label}: sources no es un array`);
	if (result.sources.length === 0) throw new Error(`${label}: no devolvió fuentes`);
	if (result.sources.length > 3) throw new Error(`${label}: devolvió más fuentes que maxResults`);
	for (const source of result.sources) {
		if (typeof source.url !== "string" || !source.url.startsWith("http")) {
			throw new Error(`${label}: fuente sin URL usable: ${JSON.stringify(source.url)}`);
		}
	}
	const withSnippet = result.sources.filter((source) => typeof source.snippet === "string");
	if (withSnippet.length === 0) throw new Error(`${label}: ninguna fuente trae snippet`);
	return result.sources.length;
};

const started = Date.now();
const first = await provider.search({ query: "tokio runtime documentation", maxResults: 3 });
const coldMs = Date.now() - started;
const warmStarted = Date.now();
const second = await provider.search({ query: "rust async book", maxResults: 3 });
const warmMs = Date.now() - warmStarted;

const firstCount = checkSources("primera búsqueda", first);
const secondCount = checkSources("segunda búsqueda", second);

console.log(
	`web-search-rustxng: ${firstCount}+${secondCount} fuentes · arranque ${coldMs} ms · reuso ${warmMs} ms`,
);
