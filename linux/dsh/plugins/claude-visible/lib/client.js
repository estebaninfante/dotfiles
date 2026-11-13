/**
 * dsh-local-claude-visible — client half.
 *
 * Panel "Delegaciones": muestra en vivo lo que Claude Code está haciendo en
 * cada delegación lanzada con `delegar-claude`. Ese proceso es headless y no
 * abre sesión en el harness, así que su estado solo existe en
 * ~/.local/state/delegar-claude/<nombre>/ (brief, out.log, pid). Este panel lo
 * lee por las rutas del host y lo refresca cada 2 segundos.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-claude-visible",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const PANEL_ID = "claude-visible";
		const STYLE_ID = "dsh-claude-visible-style";
		const REFRESH_MS = 2000;

		const CSS = `
.cv{height:100%;min-height:0;display:flex;flex-direction:column;background:var(--dsw-alias-bg-base,#0c0d0f);
  color:var(--dsw-alias-label-primary,#ecedef);font:400 13px/1.45 system-ui,-apple-system,sans-serif}
.cv-head{display:flex;align-items:center;gap:10px;padding:20px 24px 14px;flex:none}
.cv-head h1{margin:0;font-size:17px;font-weight:600;letter-spacing:-.01em}
.cv-head .sub{font-size:11.5px;color:var(--dsw-alias-label-tertiary,#8b9099)}
.cv-spacer{flex:1}
.cv-btn{height:28px;padding:0 11px;border:1px solid #2c2f36;border-radius:8px;background:transparent;
  color:#b9bdc6;font:inherit;font-size:12.5px;cursor:pointer}
.cv-btn:hover{background:#1f2228;color:#ecedef}
.cv-body{flex:1;min-height:0;display:flex;border-top:1px solid #1e2026}
.cv-list{width:320px;flex:none;overflow:auto;border-right:1px solid #1e2026;padding:8px}
.cv-item{display:flex;flex-direction:column;gap:3px;padding:9px 10px;border-radius:9px;cursor:pointer}
.cv-item:hover{background:#17191d}
.cv-item[data-sel="1"]{background:#1b1e23;box-shadow:inset 2px 0 0 #4c8dff}
.cv-item .row{display:flex;align-items:center;gap:7px}
.cv-item .nm{font-weight:550;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cv-item .meta{font-size:11px;color:#767b85;font-variant-numeric:tabular-nums}
.cv-item .last{font-size:11.5px;color:#8b9099;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cv-dot{width:7px;height:7px;border-radius:50%;flex:none;background:#4b5058}
.cv-dot[data-run="1"]{background:#3f9f63;box-shadow:0 0 0 3px rgba(63,159,99,.18);animation:cv-pulse 1.6s ease-in-out infinite}
@keyframes cv-pulse{0%,100%{opacity:1}50%{opacity:.45}}
.cv-log{flex:1;min-width:0;display:flex;flex-direction:column}
.cv-log-head{display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid #1e2026;flex:none}
.cv-log-head .nm{font-weight:600}
.cv-log pre{margin:0;padding:14px 16px;overflow:auto;flex:1;min-height:0;
  font:11.5px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace;color:#c9ced6;white-space:pre-wrap;word-break:break-word}
.cv-empty{padding:28px 24px;color:#8b9099;font-size:12.5px}
@media (max-width:820px){
  .cv-body{flex-direction:column}
  .cv-list{width:auto;border-right:0;border-bottom:1px solid #1e2026;max-height:38vh}
}
`;

		async function api(path) {
			const res = await fetch(path, { headers: { accept: "application/json" } });
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			return res.json();
		}

		function useStyles() {
			React.useEffect(() => {
				if (document.getElementById(STYLE_ID)) return;
				const style = document.createElement("style");
				style.id = STYLE_ID;
				style.textContent = CSS;
				document.head.appendChild(style);
			}, []);
		}

		const ago = (iso) => {
			const started = Date.parse(iso);
			if (!Number.isFinite(started)) return "";
			const seconds = Math.max(0, Math.round((Date.now() - started) / 1000));
			if (seconds < 60) return `hace ${seconds}s`;
			const minutes = Math.round(seconds / 60);
			if (minutes < 60) return `hace ${minutes}m`;
			return `hace ${Math.round(minutes / 60)}h`;
		};

		function DelegationsPanel() {
			useStyles();
			const [items, setItems] = React.useState([]);
			const [selected, setSelected] = React.useState(null);
			const [log, setLog] = React.useState(null);
			const [error, setError] = React.useState("");
			const [tick, setTick] = React.useState(0);

			const loadList = React.useCallback(async () => {
				try {
					const data = await api("/claude-visible/list");
					const list = data.delegations || [];
					setItems(list);
					setError("");
					setSelected((prev) => {
						if (prev && list.some((item) => item.name === prev)) return prev;
						const running = list.find((item) => item.running);
						return (running || list[0] || {}).name || null;
					});
				} catch (err) {
					setError(err.message);
				}
			}, []);

			React.useEffect(() => {
				loadList();
				const id = setInterval(() => {
					setTick((n) => n + 1);
					loadList();
				}, REFRESH_MS);
				return () => clearInterval(id);
			}, [loadList]);

			React.useEffect(() => {
				if (!selected) {
					setLog(null);
					return;
				}
				let alive = true;
				api(`/claude-visible/log?name=${encodeURIComponent(selected)}&lines=150`)
					.then((data) => alive && setLog(data))
					.catch(() => alive && setLog({ text: "(no se pudo leer el log)", total: 0 }));
				return () => {
					alive = false;
				};
			}, [selected, tick]);

			const running = items.filter((item) => item.running).length;

			return h(
				"div",
				{ className: "cv" },
				h(
					"div",
					{ className: "cv-head" },
					h("h1", null, "Delegaciones"),
					h(
						"span",
						{ className: "sub" },
						`${items.length} total · ${running} corriendo · refresco cada ${REFRESH_MS / 1000}s`,
					),
					h("div", { className: "cv-spacer" }),
					error ? h("span", { className: "sub", style: { color: "#e5484d" } }, error) : null,
					h("button", { className: "cv-btn", onClick: loadList }, "Actualizar"),
				),
				h(
					"div",
					{ className: "cv-body" },
					h(
						"div",
						{ className: "cv-list" },
						items.length === 0
							? h("div", { className: "cv-empty" }, "No hay delegaciones. Se lanzan con: delegar-claude start <brief.md>")
							: items.map((item) =>
									h(
										"div",
										{
											key: item.name,
											className: "cv-item",
											"data-sel": selected === item.name ? 1 : 0,
											onClick: () => setSelected(item.name),
										},
										h(
											"span",
											{ className: "row" },
											h("span", { className: "cv-dot", "data-run": item.running ? 1 : 0 }),
											h("span", { className: "nm" }, item.name),
										),
										h(
											"span",
											{ className: "meta" },
											`${item.running ? "corriendo" : "terminada"} · ${ago(item.startedAt)} · ${Math.max(1, Math.round(item.sizeBytes / 1024))} KB`,
										),
										item.last ? h("span", { className: "last" }, item.last) : null,
									),
								),
					),
					h(
						"div",
						{ className: "cv-log" },
						log
							? h(
									React.Fragment,
									null,
									h(
										"div",
										{ className: "cv-log-head" },
										h("span", { className: "nm" }, log.name),
										h("span", { className: "sub" }, log.running ? "corriendo" : "terminada"),
										h("div", { className: "cv-spacer" }),
										h(
											"span",
											{ className: "sub" },
											log.source === "transcript"
												? `${log.total} pasos en vivo`
												: `${log.total} líneas · últimas ${Math.min(log.total, 150)}`,
										),
									),
									h("pre", null, log.text || "(el log todavía está vacío)"),
								)
							: h("div", { className: "cv-empty" }, "Elegí una delegación para ver su salida."),
					),
				),
			);
		}

		function DelegationsIcon(props) {
			const size = props?.size ?? 16;
			return h(
				"svg",
				{ width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
				h("path", {
					d: "M8 1.8 14 5v6L8 14.2 2 11V5z",
					stroke: "currentColor",
					strokeWidth: 1.3,
					strokeLinejoin: "round",
				}),
				h("path", { d: "M2.2 5.1 8 8.2l5.8-3.1M8 8.2v5.8", stroke: "currentColor", strokeWidth: 1.1 }),
			);
		}

		function apply(ctx) {
			ctx.slots.inject("sidebar.panellist", () =>
				ctx.slots.register(
					{ name: "sidebar.panellist", id: PANEL_ID, order: 20, label: () => "Delegaciones" },
					DelegationsIcon,
				),
			);
			ctx.slots.inject("main", () =>
				ctx.slots.register({ name: "main", key: PANEL_ID, inject: () => ({}) }, DelegationsPanel),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
