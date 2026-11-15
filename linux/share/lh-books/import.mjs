// Importa a la biblioteca de LearnHarness los libros de la carpeta que todavía
// no están, con el MISMO importador de la app (src/server/library.ts). Lo corre
// `lh-books import` con tsx desde la copia de la fuente en LH_IMPORTER_APP.
//
// La API de la app solo responde a su propia ventana; esto no la toca: escribe
// en LH_DATA_DIR como lo haría la app, y la biblioteca lee del disco sin caché,
// así que el libro aparece al volver a abrir la página.
const app = process.env.LH_IMPORTER_APP;
const { scanBooksFolder, importBookFromPath } = await import(`${app}/src/server/library.ts`);

const { files } = scanBooksFolder();
if (process.argv.includes("--list")) {
	for (const file of files) if (!file.imported) console.log(file.name);
	process.exit(0);
}
let failed = 0;
for (const file of files) {
	if (file.imported) continue;
	try {
		const result = await importBookFromPath(file.path);
		console.log(`importado: ${result.book?.title ?? file.name}`);
	} catch (error) {
		failed++;
		console.error(`no se pudo importar ${file.name}: ${error instanceof Error ? error.message : error}`);
	}
}
process.exit(failed ? 1 : 0);
