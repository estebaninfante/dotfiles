// Prueba de la mitad cliente sin navegador: loader falso, React falso con
// hooks, fetch falso y un ctx mínimo. Verifica el registro de la vista y el
// render del panel con un fixture que sale del mismo fold del host.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { foldSession } from "../lib/fold.js";

/* ---------- fixture: fold real sobre eventos conocidos ---------- */
const fixture = foldSession(
	{ id: "session-test", cwd: "/home/user/app", createdAt: 1, version: 4, isSeeded: false },
	[
		{ type: "turn/start", seq: 0, time: 0, data: { turn: 1 } },
		{ type: "step/start", seq: 1, time: 0, data: { turn: 1, step: 1 } },
		{ type: "request/header", seq: 2, time: 10, data: { header: { config: { provider: "opencode-go", model: "deepseek-v4.1-flash" } } } },
		{ type: "assistant/message", seq: 3, time: 1000, data: { turn: 1, step: 1, usage: { inputTokens: 100, cacheReadTokens: 1000, outputTokens: 50, totalTokens: 1150 } } },
		{ type: "tool/call", seq: 4, time: 1100, data: { turn: 1, step: 1, callId: "c1", name: "bash" } },
		{ type: "tool/result", seq: 5, time: 2100, data: { turn: 1, step: 1, message: { source: { callId: "c1" }, isError: false } } },
		{ type: "step/start", seq: 6, time: 2100, data: { turn: 1, step: 2 } },
		{ type: "llm/retry", seq: 7, time: 302100, data: { turn: 1, step: 2, failure: { code: "TIMEOUT" } } },
		{ type: "assistant/attempt", seq: 8, time: 302100, data: { turn: 1, step: 2, stream: [{ type: "chunk", time: 302100, chunk: { type: "finish", reason: { kind: "error", failure: { code: "TIMEOUT", message: "timeout" } } } }] } },
		{ type: "assistant/message", seq: 9, time: 304100, data: { turn: 1, step: 2, usage: { inputTokens: 200, cacheReadTokens: 2000, outputTokens: 80, totalTokens: 2280 } } },
		{ type: "turn/end", seq: 10, time: 305100, data: { turn: 1, reason: { kind: "completed" } } },
	],
);

/* ---------- React falso con hooks ---------- */
let hookState = [];
let hookCursor = 0;
let effects = [];
let dirty = false;
const React = {
	createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat(Infinity).filter((child) => child !== null && child !== undefined && child !== false) }),
	Fragment: "Fragment",
	useState(init) {
		const index = hookCursor++;
		if (!(index in hookState)) hookState[index] = typeof init === "function" ? init() : init;
		const set = (value) => {
			hookState[index] = typeof value === "function" ? value(hookState[index]) : value;
			dirty = true;
		};
		return [hookState[index], set];
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
		const index = 100000 + hookCursor++;
		if (!(index in hookState)) hookState[index] = { current: value };
		return hookState[index];
	},
	useLayoutEffect(fn) {
		effects.push({ fn, deps: undefined });
	},
};

/* ---------- entorno falso ---------- */
let captured = null;
globalThis.window = { __ModuleLoader__: { load: (entry) => { captured = entry; } } };
globalThis.document = {
	getElementById: () => null,
	createElement: () => ({ dataset: {}, setAttribute() {}, appendChild() {} }),
	head: { appendChild() {} },
};
globalThis.setInterval = () => 1;
globalThis.clearInterval = () => {};
let copied = null;
Object.defineProperty(globalThis, "navigator", { value: { clipboard: { writeText: async (text) => { copied = text; } } }, configurable: true });
let fetchedUrl = null;
globalThis.fetch = async (url) => {
	fetchedUrl = url;
	return { ok: true, status: 200, json: async () => ({ ok: true, ...fixture }) };
};

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(resolve(here, "../lib/client.js"), "utf8");
new Function("window", "document", source)(globalThis.window, globalThis.document);
const mod = captured.factory((name) => {
	if (name === "react") return React;
	throw new Error(`require inesperado: ${name}`);
});

/* ---------- ctx falso ---------- */
const registrations = [];
const definitions = [];
const fakeCtx = {
	effect: (fn) => {
		fn();
		return () => {};
	},
	slots: {
		inject: (slot, factory) => factory(),
		register: (options, component) => {
			registrations.push({ options, component });
			return () => {};
		},
	},
	uiConversation: {
		views: {
			register: (definition) => {
				definitions.push(definition);
				return () => {};
			},
		},
	},
};

mod.apply(fakeCtx);

assert.equal(registrations.length, 1);
const [registration] = registrations;
assert.equal(registration.options.name, "conversation.view");
assert.equal(registration.options.id, "metrics");
assert.equal(String(registration.options.label()), "Metrics");
assert.equal(typeof registration.component, "function");
assert.equal(definitions.length, 1);
assert.equal(definitions[0].target, "metrics");
const builder = definitions[0].create();
assert.deepEqual(builder.empty, {});
assert.deepEqual(builder.replace(), {});
assert.deepEqual(builder.apply(), {});

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

const props = registration.options.inject("session-test");
assert.deepEqual(props, { sessionId: "session-test" });

let tree = null;
const cleanups = [];
for (let pass = 0; pass < 8; pass += 1) {
	hookCursor = 0;
	dirty = false;
	effects = [];
	tree = registration.component(props);
	for (const effect of effects) {
		const out = effect.fn();
		if (typeof out === "function") cleanups.push(out);
	}
	await new Promise((resolvePromise) => setTimeout(resolvePromise, 0));
	await new Promise((resolvePromise) => setTimeout(resolvePromise, 0));
	if (!dirty) break;
}

assert.equal(fetchedUrl, "/metrics/session?session=session-test");
const text = textOf(tree);
for (const needle of ["Metrics", "Conversation", "Latency per request", "Tokens", "Gaps and extras", "Tools", "Failures by code", "bash", "TIMEOUT", "opencode-go/deepseek-v4.1-flash", "Copy JSON"]) {
	assert.ok(text.includes(needle), `falta "${needle}" en el render: ${text.slice(0, 300)}`);
}
assert.ok(text.includes("5m 0s"), "no muestra el gap de 5 min");
assert.ok(text.includes("91%"), "no muestra el cache hit");

const buttons = [];
walk(tree, (node) => {
	if (node.type === "button") buttons.push(node);
});
assert.equal(buttons.length, 1);
await buttons[0].props.onClick();
await new Promise((resolvePromise) => setTimeout(resolvePromise, 0));
assert.ok(copied !== null && copied.includes('"session"') && copied.includes('"latency"'), "Copy JSON no copió el payload");

for (const cleanup of cleanups) cleanup();
console.log("ok: client");
