// Prueba de humo del cliente `machine` sin navegador: React falso con hooks
// con estado, fetch falso y un ctx mínimo. Renderiza la ficha del proyecto y
// comprueba que los botones de conversación existen y que el clic crea sesión,
// manda el contexto y navega al chat.
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/* ---------- React falso con estado ---------- */
let hookState = [];
let hookCursor = 0;
let effects = [];
let dirty = false;

const React = {
	createElement: (type, props, ...children) => ({
		type,
		props: props || {},
		children: children.flat(Infinity).filter((c) => c !== null && c !== undefined && c !== false),
	}),
	Fragment: "Fragment",
	useState(init) {
		const i = hookCursor++;
		if (!(i in hookState)) hookState[i] = typeof init === "function" ? init() : init;
		const set = (value) => {
			hookState[i] = typeof value === "function" ? value(hookState[i]) : value;
			dirty = true;
		};
		return [hookState[i], set];
	},
	useEffect(fn, deps) {
		effects.push({ fn, deps });
	},
	useMemo(fn) {
		return fn();
	},
	useCallback(fn) {
		return fn;
	},
	useRef(value) {
		const i = 100000 + hookCursor++;
		if (!(i in hookState)) hookState[i] = { current: value };
		return hookState[i];
	},
	useLayoutEffect(fn) {
		effects.push({ fn, deps: undefined });
	},
};

/* ---------- datos falsos ---------- */
const ENTITIES = [
	{
		slug: "mejorar-ui-que-genera-el-modelo",
		kind: "project",
		state: "active",
		title: "Mejorar la UI que genera el modelo",
		note: "Catálogo de los 9 vicios",
		facts: { goal: "Mejorar el harness para que Flash haga buenas interfaces", check: "Pedir una UI nueva: los vicios no vuelven", path: "/home/eztvn/Proyectos/x" },
		age_days: 1,
	},
	{ slug: "idea-1", kind: "idea", state: "unclassified", title: "Estándar de apps", note: "Todas vinculadas a Tailscale", facts: {}, age_days: null },
];

const DETAIL = {
	...ENTITIES[0],
	tasks: [
		{ slug: "t1", title: "Fase 1: cerrar el catálogo", state: "active" },
		{ slug: "t2", title: "Fase 2: probar métodos", state: "active" },
	],
};

const calls = [];
globalThis.fetch = async (url, options) => {
	calls.push({ url, options });
	const ideaDetail = { ...ENTITIES[1], tasks: [] };
	const body = url.includes("/machine/project") ? (url.includes("idea-1") ? ideaDetail : DETAIL) : url.includes("/machine/entities") ? { entities: ENTITIES } : url.includes("/machine/trash") ? { entries: [] } : {};
	return { ok: true, json: async () => body };
};

/* ---------- loader falso ---------- */
let captured = null;
globalThis.window = {
	__ModuleLoader__: {
		load: (entry) => {
			captured = entry;
		},
	},
};
globalThis.document = {
	getElementById: () => null,
	createElement: () => ({ setAttribute() {}, appendChild() {} }),
	head: { appendChild() {} },
	addEventListener() {},
	removeEventListener() {},
};
globalThis.requestAnimationFrame = (fn) => setTimeout(fn, 0);

const here = dirname(fileURLToPath(import.meta.url));
const target = resolve(process.argv[2] ?? resolve(here, "../../linux/dsh/plugins/machine/lib/client.js"));
const source = readFileSync(target, "utf8");
new Function("window", "document", source)(globalThis.window, globalThis.document);
const mod = captured.factory((name) => {
	if (name === "react") return React;
	throw new Error(`require inesperado: ${name}`);
});

/* ---------- ctx falso ---------- */
const created = [];
const prompted = [];
const navigated = [];
const panels = [];
const services = {
	sessions: {
		async create(opts) {
			created.push(opts);
			return { ok: true, value: { sessionId: "sess-123" } };
		},
		async using(id, opts, cb) {
			await cb({
				ready: Promise.resolve({}),
				binding: {
					session: {
						async prompt(content, mode) {
							prompted.push({ id, content, mode });
							return { ok: true, value: {} };
						},
					},
				},
			});
			return undefined;
		},
	},
	layout: {
		selectPanel: (id) => panels.push(id),
	},
	uiWorkspace: {
		openSession: (id) => navigated.push(id),
	},
};

const registrations = [];
const fakeCtx = {
	get: (name) => services[name],
	slots: {
		inject: (slot, factory) => factory(),
		register: (options, component) => {
			registrations.push({ options, component });
			return () => {};
		},
		subscribe: () => () => {},
	},
	effect: () => {},
};

mod.apply(fakeCtx);

const main = registrations.find((r) => r.options.name === "main");
if (!main) throw new Error("no registró el slot main");
const props = main.options.inject();

/* ---------- mini renderer ---------- */
function textOf(node) {
	if (node === null || node === undefined || node === false) return "";
	if (typeof node === "string" || typeof node === "number") return String(node);
	if (Array.isArray(node)) return node.map(textOf).join(" ");
	if (node.children) return node.children.map(textOf).join(" ");
	return "";
}

function walk(node, visit) {
	if (!node || typeof node !== "object") return;
	visit(node);
	(node.children || []).forEach((child) => walk(child, visit));
}

function findClicks(node, needle) {
	const found = [];
	walk(node, (n) => {
		if (n.props && typeof n.props.onClick === "function" && textOf(n).includes(needle)) found.push(n);
	});
	return found;
}

async function flush() {
	for (const effect of effects) {
		const out = effect.fn();
		if (typeof out === "function") out();
	}
	effects = [];
	await new Promise((r) => setTimeout(r, 0));
	await new Promise((r) => setTimeout(r, 0));
}

let tree;
for (let pass = 0; pass < 6; pass += 1) {
	hookCursor = 0;
	dirty = false;
	tree = main.component(props);
	await flush();
	if (!dirty) break;
}

const listText = textOf(tree);
if (!listText.includes("Mejorar la UI")) throw new Error("la lista no renderizó el proyecto");

/* ---------- abrir la ficha ---------- */
const rowClick = findClicks(tree, "Mejorar la UI")[0];
if (!rowClick) throw new Error("no encontré la fila para abrir la ficha");
await rowClick.props.onClick();
for (let pass = 0; pass < 6; pass += 1) {
	hookCursor = 0;
	dirty = false;
	tree = main.component(props);
	await flush();
	if (!dirty) break;
}

const detailText = textOf(tree);
for (const label of ["Trabajar", "Ajustar", "Objetivo"]) {
	if (!detailText.includes(label)) throw new Error(`la ficha no muestra "${label}": ${detailText.slice(0, 200)}`);
}

/* ---------- clic en Trabajar ---------- */
const workClick = findClicks(tree, "Trabajar")[0];
if (!workClick) throw new Error("no encontré el botón Trabajar");
await workClick.props.onClick();
await new Promise((r) => setTimeout(r, 0));

if (created.length !== 1) throw new Error(`esperaba 1 sesión creada, hubo ${created.length}`);
if (created[0].cwd !== "/home/eztvn/Proyectos/x") throw new Error(`cwd incorrecto: ${JSON.stringify(created[0])}`);
if (prompted.length !== 1) throw new Error(`esperaba 1 prompt, hubo ${prompted.length}`);
const message = prompted[0].content[0].text;
for (const needle of ["Objetivo:", "Fase 1: cerrar el catálogo", "La prueba:", "primera tarea pendiente"]) {
	if (!message.includes(needle)) throw new Error(`el mensaje no incluye "${needle}":\n${message}`);
}
if (prompted[0].mode !== "queue") throw new Error(`modo inesperado: ${prompted[0].mode}`);
if (panels[0] !== null) throw new Error("no salió del panel hacia el chat");
if (navigated[0] !== "sess-123") throw new Error(`no navegó a la sesión: ${JSON.stringify(navigated)}`);

/* ---------- ficha de una idea ---------- */
hookState = [];
hookCursor = 0;
effects = [];
dirty = false;
for (let pass = 0; pass < 6; pass += 1) {
	hookCursor = 0;
	dirty = false;
	tree = main.component(props);
	await flush();
	if (!dirty) break;
}
const ideaClick = findClicks(tree, "Estándar de apps")[0];
await ideaClick.props.onClick();
for (let pass = 0; pass < 6; pass += 1) {
	hookCursor = 0;
	dirty = false;
	tree = main.component(props);
	await flush();
	if (!dirty) break;
}
const ideaText = textOf(tree);
if (!ideaText.includes("Abrir conversación")) throw new Error("la idea no ofrece abrir conversación");
const ideaBtn = findClicks(tree, "Abrir conversación")[0];
created.length = 0;
prompted.length = 0;
navigated.length = 0;
await ideaBtn.props.onClick();
await new Promise((r) => setTimeout(r, 0));
if (created[0].cwd !== undefined) throw new Error("una idea no debería fijar carpeta");
if (!prompted[0].content[0].text.includes("Idea: Estándar de apps")) throw new Error("el mensaje de la idea no la nombra");

console.log("render OK · botones OK · sesión creada · contexto enviado · navegación OK");
console.log("--- mensaje de Trabajar ---");
console.log(message);
