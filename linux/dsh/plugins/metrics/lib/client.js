/**
 * dsh-local-metrics — client half.
 *
 * Vista "Metrics" dentro de la conversación: lee `/metrics/session?session=<id>`
 * (mitad host de este plugin) y muestra el resumen denso de la sesión: tiempos,
 * latencias, tokens, tools, reintentos, huecos y contexto.
 *
 * Sin adorno: tablas y filas de números; la única acción es copiar el JSON para
 * poder comparar conversaciones sin abrir el log.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-metrics",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const STYLE_ID = "dsh-metrics-style";
		const STYLE_REV = "2026-11-17.1";
		const REFRESH_MS = 5000;
		const CSS = `
.mt-root{height:100%;overflow:auto;padding:18px 22px 32px;color:var(--dsw-alias-label-primary);font:13px/1.5 var(--ds-font-family,system-ui,sans-serif);box-sizing:border-box}
.mt-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;border-bottom:.5px solid var(--dsw-alias-border-l2);padding-bottom:10px;margin-bottom:16px}
.mt-headText{min-width:0;display:flex;flex-direction:column;gap:2px}
.mt-title{margin:0;font-size:15px;font-weight:600;line-height:20px}
.mt-sub{color:var(--dsw-alias-label-tertiary);font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mt-headActions{display:flex;align-items:center;gap:12px;flex:none}
.mt-stamp{color:var(--dsw-alias-label-caption);font-size:11px;font-variant-numeric:tabular-nums;white-space:nowrap}
.mt-action{font:inherit;font-size:12px;line-height:16px;min-height:24px;padding:3px 10px;border:.5px solid var(--dsw-alias-border-l3);border-radius:4px;background:0 0;color:var(--dsw-alias-label-secondary);cursor:pointer}
.mt-action:hover{background:var(--dsw-alias-interactive-bg-hover);color:var(--dsw-alias-label-primary)}
.mt-action:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary);outline-offset:1px}
.mt-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px 32px;align-items:start}
.mt-section{min-width:0}
.mt-wide{grid-column:1/-1;margin-top:20px}
.mt-h3{margin:0 0 5px;font-size:12px;font-weight:600;line-height:16px;color:var(--dsw-alias-label-secondary)}
.mt-row{display:flex;justify-content:space-between;gap:12px;padding:3px 0;border-top:.5px solid var(--dsw-alias-border-l1);font-variant-numeric:tabular-nums}
.mt-row:first-child{border-top:0}
.mt-label{color:var(--dsw-alias-label-tertiary);white-space:nowrap}
.mt-value{color:var(--dsw-alias-label-primary);font-family:var(--ds-font-family-code,ui-monospace,monospace);font-size:12px;text-align:right;white-space:nowrap}
.mt-table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}
.mt-table th{text-align:left;font-size:12px;font-weight:600;color:var(--dsw-alias-label-tertiary);border-bottom:.5px solid var(--dsw-alias-border-l2);padding:4px 10px 4px 0;white-space:nowrap}
.mt-table td{border-bottom:.5px solid var(--dsw-alias-border-l1);padding:3px 10px 3px 0;font-size:12px;white-space:nowrap}
.mt-table th:not(:first-child),.mt-table td:not(:first-child){text-align:right}
.mt-table .num{font-family:var(--ds-font-family-code,ui-monospace,monospace)}
.mt-empty{margin:28px 0;color:var(--dsw-alias-label-tertiary);font-size:13px}
.mt-note{margin:22px 0 0;color:var(--dsw-alias-label-caption);font-size:11px}
@media (max-width:760px){.mt-grid{grid-template-columns:1fr}.mt-root{padding:14px 14px 28px}}
`;

		function ensureStyle() {
			const current = document.getElementById(STYLE_ID);
			if (current !== null && current.dataset.rev === STYLE_REV && current.textContent === CSS) return;
			if (current !== null) current.remove();
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.dataset.rev = STYLE_REV;
			style.textContent = CSS;
			document.head.appendChild(style);
		}

		const group = new Intl.NumberFormat("en-US");

		function fmtInt(value) {
			return typeof value === "number" && Number.isFinite(value) ? group.format(value) : "—";
		}

		function fmtTok(value) {
			if (typeof value !== "number" || !Number.isFinite(value)) return "—";
			if (value >= 1e6) return `${(value / 1e6).toFixed(2)}M`;
			if (value >= 1e4) return `${(value / 1e3).toFixed(0)}k`;
			return group.format(value);
		}

		function fmtMs(value) {
			if (typeof value !== "number" || !Number.isFinite(value)) return "—";
			if (value < 1000) return `${Math.round(value)} ms`;
			if (value < 60_000) return `${(value / 1000).toFixed(1)} s`;
			const minutes = Math.floor(value / 60_000);
			const seconds = Math.round((value % 60_000) / 1000);
			return `${minutes}m ${seconds}s`;
		}

		function fmtPct(value) {
			return typeof value === "number" && Number.isFinite(value) ? `${value.toFixed(0)}%` : "—";
		}

		function fmtSpeed(value) {
			return typeof value === "number" && Number.isFinite(value) ? `${value.toFixed(1)} tok/s` : "—";
		}

		function fmtClock(value) {
			if (typeof value !== "number" || !Number.isFinite(value)) return "—";
			return new Date(value).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
		}

		function rows(title, entries) {
			return h(
				"section",
				{ className: "mt-section" },
				h("h3", { className: "mt-h3" }, title),
				h(
					"div",
					null,
					entries.map(([label, value]) => h("div", { className: "mt-row", key: label }, h("span", { className: "mt-label" }, label), h("span", { className: "mt-value" }, value))),
				),
			);
		}

		function table(title, head, body) {
			if (body.length === 0) return null;
			return h(
				"section",
				{ className: "mt-section mt-wide" },
				h("h3", { className: "mt-h3" }, title),
				h(
					"table",
					{ className: "mt-table" },
					h("thead", null, h("tr", null, head.map((cell) => h("th", { key: cell }, cell)))),
					h("tbody", null, body),
				),
			);
		}

		function toolsTable(tools) {
			if (!Array.isArray(tools) || tools.length === 0) return null;
			return table(
				"Tools",
				["Tool", "Calls", "Time", "p50", "Max", "Errors"],
				tools.map((tool) =>
					h(
						"tr",
						{ key: tool.name },
						h("td", null, tool.name),
						h("td", { className: "num" }, fmtInt(tool.calls)),
						h("td", { className: "num" }, fmtMs(tool.ms)),
						h("td", { className: "num" }, fmtMs(tool.p50)),
						h("td", { className: "num" }, fmtMs(tool.max)),
						h("td", { className: "num" }, fmtInt(tool.errors)),
					),
				),
			);
		}

		function failuresTable(failures) {
			if (!Array.isArray(failures) || failures.length === 0) return null;
			return table(
				"Failures by code",
				["Code", "Count"],
				failures.map((failure) => h("tr", { key: failure.code }, h("td", null, failure.code), h("td", { className: "num" }, fmtInt(failure.count)))),
			);
		}

		function MetricsPanel({ sessionId }) {
			const [state, setState] = React.useState({ data: null, error: null, at: 0 });
			const [copied, setCopied] = React.useState(false);
			const alive = React.useRef(true);

			const load = React.useCallback(async () => {
				try {
					const response = await fetch(`/metrics/session?session=${encodeURIComponent(sessionId)}`, { headers: { accept: "application/json" } });
					const body = await response.json().catch(() => null);
					if (!response.ok || body === null || body.ok !== true) throw new Error(body?.message ?? body?.error ?? `HTTP ${response.status}`);
					if (alive.current) setState({ data: body, error: null, at: Date.now() });
				} catch (error) {
					if (alive.current) setState((current) => ({ ...current, error: String(error?.message ?? error) }));
				}
			}, [sessionId]);

			React.useEffect(() => {
				alive.current = true;
				load();
				const timer = setInterval(load, REFRESH_MS);
				return () => {
					alive.current = false;
					clearInterval(timer);
				};
			}, [load]);

			const copy = React.useCallback(() => {
				if (state.data === null) return;
				const text = JSON.stringify(state.data, null, 2);
				Promise.resolve(navigator.clipboard?.writeText(text))
					.then(() => {
						setCopied(true);
						setTimeout(() => setCopied(false), 1500);
					})
					.catch(() => {});
			}, [state.data]);

			const data = state.data;
			if (data === null) {
				return h("div", { className: "mt-root" }, h("p", { className: "mt-empty" }, state.error === null ? "Loading metrics…" : `No metrics: ${state.error}`));
			}

			const counts = data.counts ?? {};
			const time = data.time ?? {};
			const latency = data.latency ?? {};
			const tokens = data.tokens ?? {};
			const context = data.context ?? {};
			const gaps = data.gaps ?? {};
			const outcomes = Object.entries(data.outcomes ?? {})
				.map(([kind, count]) => `${kind} ${count}`)
				.join(" · ");
			const subtitle = [data.session?.title ?? data.session?.id ?? sessionId, data.model === null || data.model === undefined ? null : `${data.model.provider}/${data.model.model}`, data.session?.cwd]
				.filter(Boolean)
				.join(" · ");

			return h(
				"div",
				{ className: "mt-root" },
				h(
					"header",
					{ className: "mt-head" },
					h("div", { className: "mt-headText" }, h("h2", { className: "mt-title" }, "Metrics"), h("span", { className: "mt-sub" }, subtitle)),
					h(
						"div",
						{ className: "mt-headActions" },
						h("span", { className: "mt-stamp" }, state.error === null ? `updated ${fmtClock(state.at)}` : `stale ${fmtClock(state.at)} · ${state.error}`),
						h("button", { type: "button", className: "mt-action", onClick: copy }, copied ? "Copied" : "Copy JSON"),
					),
				),
				h(
					"div",
					{ className: "mt-grid" },
					rows("Conversation", [
						["Turns", outcomes === "" ? fmtInt(counts.turns) : `${fmtInt(counts.turns)} · ${outcomes}`],
						["Steps", fmtInt(counts.steps)],
						["Requests", fmtInt(counts.requests)],
						["Tool calls", fmtInt(counts.toolCalls)],
						["User messages", fmtInt(counts.userMessages)],
						["Wall time", fmtMs(data.session?.wallMs)],
					]),
					rows("Time", [
						["Model", fmtMs(time.modelMs)],
						["Tools", fmtMs(time.toolMs)],
						["Unaccounted", fmtMs(time.waitMs)],
						["Turn avg", fmtMs(time.turnAvgMs)],
						["Turn max", fmtMs(time.turnMaxMs)],
					]),
					rows("Latency per request", [
						["p50", fmtMs(latency.p50)],
						["p90", fmtMs(latency.p90)],
						["p95", fmtMs(latency.p95)],
						["Max", fmtMs(latency.max)],
						["p50 clean", fmtMs(latency.cleanP50)],
						["Slow > 2 min", fmtInt(latency.slow)],
						["Retries", fmtInt(counts.retries)],
						["Failures", fmtInt(counts.failures)],
					]),
					rows("Tokens", [
						["Uncached input", fmtTok(tokens.input)],
						["Cache read", fmtTok(tokens.cacheRead)],
						["Output", fmtTok(tokens.output)],
						["Cache hit", fmtPct(tokens.cacheHitPct)],
						["Speed", fmtSpeed(tokens.speed)],
						["Context first", fmtTok(context.first)],
						["Context last", fmtTok(context.last)],
						["Context max", fmtTok(context.max)],
					]),
					rows("Gaps and extras", [
						["Gaps > 2 min", fmtInt(gaps.count)],
						["Gap total", fmtMs(gaps.ms)],
						["Longest gap", fmtMs(gaps.longest)],
						["Images", fmtInt(data.images)],
						["Samples", fmtInt(latency.samples)],
					]),
					toolsTable(data.tools),
				),
				failuresTable(data.failures),
				h("p", { className: "mt-note" }, "TTFT is not in the durable log. Context = totalTokens − output."),
			);
		}

		const EMPTY = Object.freeze({});
		const VIEW = {
			target: "metrics",
			create: () => ({ empty: EMPTY, replace: () => EMPTY, apply: () => EMPTY }),
		};

		function apply(ctx) {
			ensureStyle();
			ctx.effect(() => ctx.uiConversation.views.register(VIEW), "metrics: definición de vista");
			ctx.slots.inject("conversation.view", () =>
				ctx.slots.register(
					{ name: "conversation.view", id: "metrics", order: 20, label: () => "Metrics", inject: (sessionId) => ({ sessionId }) },
					MetricsPanel,
				),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots", "uiConversation"];
		// Solo para pruebas sin navegador (no lo usa la UI).
		exports.__test = { MetricsPanel, fmtInt, fmtMs, fmtTok, fmtPct, fmtSpeed };
		return module.exports;
	},
});
