/**
 * dsh-local-machine — client half.
 *
 * Panel del harness (barra lateral + contenido del centro, no overlay).
 * Inventario de proyectos con jerarquía: cabecera, KPIs, filtros, buscador
 * y tabla densa; la ficha aparece solo cuando elegís un proyecto.
 *
 * Datos: /machine/* (el plugin host invoca el CLI `machine`).
 */
window.__ModuleLoader__.load({
	id: "dsh-local-machine",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const PANEL_ID = "machine";
		const STYLE_ID = "dsh-machine-style";
		const STATES = ["unclassified", "active", "paused", "done", "archived"];
		const LABEL = {
			unclassified: "sin decidir",
			active: "activo",
			paused: "pausado",
			done: "terminado",
			archived: "archivado",
		};
		const DOT = {
			unclassified: "#d8a33a",
			active: "#3f9f63",
			paused: "#8b8f98",
			done: "#4c8dff",
			archived: "#4b5058",
		};
		const KIND_LABEL = {
			project: "proyecto",
			product: "producto",
			experiment: "experimento",
			service: "servicio",
			app: "app",
			idea: "idea",
			task: "tarea",
		};

		const CSS = `
.mr{
  --line: var(--dsw-alias-border-l1, #1e2026);
  --line2: var(--dsw-alias-border-l2, #2c2f36);
  --fg: var(--dsw-alias-label-primary, #ecedef);
  --fg2: var(--dsw-alias-label-secondary, #a8adb6);
  --fg3: var(--dsw-alias-label-tertiary, #767b85);
  --bg: var(--dsw-alias-bg-base, #0c0d0f);
  --card: var(--dsw-alias-bg-overlay, #141619);
  --hover: var(--dsw-alias-interactive-bg-hover, #191b1f);
  --accent: #4c8dff;
  --warn: #d8a33a;
  --bad: #e5484d;
  height: 100%; min-height: 0; display: flex; flex-direction: column;
  background: var(--bg); color: var(--fg);
  font: 400 13px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
}
.mr *{box-sizing:border-box}
.mr-head{display:flex;align-items:flex-start;gap:16px;padding:22px 26px 18px;flex:none}
.mr-title{min-width:0}
.mr-title h1{margin:0;font-size:19px;line-height:1.2;font-weight:600;letter-spacing:-.015em}
.mr-title p{margin:4px 0 0;font-size:11.5px;color:var(--fg3)}
.mr-tools{margin-left:auto;display:flex;align-items:center;gap:8px}
.mr-search{position:relative}
.mr-search input{
  width:220px;height:30px;padding:0 10px 0 28px;border:1px solid var(--line2);border-radius:8px;
  background:transparent;color:var(--fg);font:inherit;font-size:12.5px;outline:none;transition:border-color .12s}
.mr-search input:focus{border-color:#3b4048}
.mr-search svg{position:absolute;left:9px;top:8px;color:var(--fg3)}
.mr-btn{
  height:30px;padding:0 11px;display:inline-flex;align-items:center;gap:6px;
  border:1px solid var(--line2);border-radius:8px;background:transparent;color:var(--fg2);
  font:inherit;font-size:12.5px;cursor:pointer;transition:background .12s,color .12s}
.mr-btn:hover{background:var(--hover);color:var(--fg)}
.mr-btn[disabled]{opacity:.5;cursor:default}
.mr-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;padding:0 26px 18px;flex:none}
.mr-kpi{
  position:relative;padding:13px 15px 12px;border:1px solid var(--line);border-radius:11px;
  background:linear-gradient(180deg,rgba(255,255,255,.022),rgba(255,255,255,0));overflow:hidden}
.mr-kpi .k{display:flex;align-items:center;gap:6px;font-size:10.5px;letter-spacing:.05em;
  text-transform:uppercase;color:var(--fg3);font-weight:600}
.mr-kpi .v{margin-top:7px;font-size:26px;line-height:1;font-weight:600;letter-spacing:-.02em;
  font-variant-numeric:tabular-nums}
.mr-kpi .h{margin-top:3px;font-size:11px;color:var(--fg3);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mr-kpi .bar{position:absolute;left:0;right:0;bottom:0;height:2px;background:var(--line)}
.mr-kpi .bar i{display:block;height:100%;border-radius:0 2px 2px 0}
.mr-dot{width:6px;height:6px;border-radius:50%;flex:none}
.mr-filters{display:flex;align-items:center;gap:6px;padding:0 26px 14px;flex:none;flex-wrap:wrap}
.mr-chip{
  height:27px;padding:0 11px;display:inline-flex;align-items:center;gap:7px;
  border:1px solid transparent;border-radius:7px;background:transparent;color:var(--fg2);
  font:inherit;font-size:12.5px;cursor:pointer;transition:background .12s,color .12s}
.mr-chip:hover{background:var(--hover);color:var(--fg)}
.mr-chip[data-on="1"]{background:var(--hover);border-color:var(--line2);color:var(--fg);font-weight:500}
.mr-chip .n{font-size:11px;color:var(--fg3);font-variant-numeric:tabular-nums}
.mr-chip[data-on="1"] .n{color:var(--fg2)}
.mr-sort{margin-left:auto;display:flex;align-items:center;gap:6px;font-size:11.5px;color:var(--fg3)}
.mr-sort select{
  height:26px;border:1px solid transparent;border-radius:7px;background:transparent;
  color:var(--fg2);font:inherit;font-size:12px;padding:0 4px;cursor:pointer}
.mr-sort select:hover{background:var(--hover);color:var(--fg)}
.mr-main{flex:1;min-height:0;display:flex;border-top:1px solid var(--line)}
.mr-list{flex:1;min-width:0;overflow:auto}
.mr table{width:100%;border-collapse:separate;border-spacing:0;font-size:12.5px;table-layout:fixed}
.mr thead th{
  position:sticky;top:0;z-index:2;background:var(--bg);text-align:left;
  padding:9px 12px;font-size:10.5px;letter-spacing:.055em;text-transform:uppercase;
  color:var(--fg3);font-weight:600;border-bottom:1px solid var(--line);white-space:nowrap}
.mr thead th:first-child{padding-left:26px}
.mr thead th:last-child{padding-right:26px;text-align:right}
.mr tbody td{
  padding:10px 12px;border-bottom:1px solid var(--line);vertical-align:middle;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mr tbody td:first-child{padding-left:26px}
.mr tbody td:last-child{padding-right:26px;text-align:right}
.mr tbody tr{cursor:pointer;transition:background .1s}
.mr tbody tr:hover td{background:var(--hover)}
.mr tbody tr[data-sel="1"] td{background:var(--hover)}
.mr tbody tr[data-sel="1"] td:first-child{box-shadow:inset 2px 0 0 var(--accent)}
.mr .name{display:flex;align-items:baseline;gap:8px;min-width:0}
.mr .name b{font-weight:550;font-size:13px;letter-spacing:-.005em}
.mr .name em{font-style:normal;font-size:11px;color:var(--fg3);overflow:hidden;text-overflow:ellipsis}
.mr-pill{
  display:inline-flex;align-items:center;gap:6px;height:24px;padding:0 7px;
  border:1px solid transparent;border-radius:6px;background:transparent;
  color:var(--fg2);font:inherit;font-size:12px;cursor:pointer;max-width:100%}
.mr-pill:hover{background:var(--hover);border-color:var(--line2);color:var(--fg)}
.mr-pill select{
  appearance:none;-webkit-appearance:none;border:0;background:transparent;color:inherit;
  font:inherit;font-size:12px;cursor:pointer;outline:none;padding:0;margin:0;max-width:120px}
.mr-pill select option{background:#17191d;color:#ecedef}
.mr-age{font-variant-numeric:tabular-nums;color:var(--fg2)}
.mr-age[data-stale="1"]{color:var(--warn)}
.mr-remote{display:inline-flex;align-items:center;gap:6px;color:var(--fg2);font-size:12px}
.mr-remote[data-none="1"]{color:var(--fg3)}
.mr-warn{display:inline-flex;align-items:center;gap:5px;color:var(--warn);font-size:12px;
  font-variant-numeric:tabular-nums}
.mr-muted{color:var(--fg3)}
.mr-num{font-variant-numeric:tabular-nums;color:var(--fg2)}
.mr-empty{padding:56px 26px;text-align:center;color:var(--fg3);font-size:12.5px}
.mr-sheet{
  width:420px;flex:none;border-left:1px solid var(--line);display:flex;flex-direction:column;
  min-height:0;background:var(--card);animation:mr-in .14s ease-out}
@keyframes mr-in{from{opacity:0;transform:translateX(6px)}to{opacity:1;transform:none}}
.mr-sheet-head{display:flex;align-items:flex-start;gap:10px;padding:18px 18px 12px;flex:none}
.mr-sheet-head h2{margin:0;font-size:15px;font-weight:600;letter-spacing:-.01em;word-break:break-word}
.mr-sheet-head p{margin:3px 0 0;font-size:11.5px;color:var(--fg3);word-break:break-all}
.mr-x{
  margin-left:auto;width:26px;height:26px;flex:none;display:grid;place-items:center;
  border:0;border-radius:6px;background:transparent;color:var(--fg3);cursor:pointer;font-size:15px;line-height:1}
.mr-x:hover{background:var(--hover);color:var(--fg)}
.mr-sheet-body{flex:1;min-height:0;overflow:auto;padding:0 18px 22px}
.mr-facts{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--line);
  border:1px solid var(--line);border-radius:10px;overflow:hidden}
.mr-facts div{background:var(--card);padding:9px 11px;min-width:0}
.mr-facts dt{font-size:10px;letter-spacing:.05em;text-transform:uppercase;color:var(--fg3);font-weight:600}
.mr-facts dd{margin:3px 0 0;font-size:12px;color:var(--fg);word-break:break-all;line-height:1.35}
.mr-facts div[data-wide="1"]{grid-column:1 / -1}
.mr-label{margin:18px 0 7px;font-size:10px;letter-spacing:.055em;text-transform:uppercase;
  color:var(--fg3);font-weight:600;display:flex;align-items:center;gap:8px}
.mr-label::after{content:"";flex:1;height:1px;background:var(--line)}
.mr textarea{
  width:100%;min-height:74px;resize:vertical;padding:9px 10px;border:1px solid var(--line2);
  border-radius:9px;background:rgba(255,255,255,.015);color:var(--fg);font:inherit;font-size:12.5px;
  line-height:1.45;outline:none;transition:border-color .12s}
.mr textarea:focus{border-color:#3b4048}
.mr textarea::placeholder{color:var(--fg3)}
.mr-tasks{list-style:none;margin:0;padding:0;display:flex;flex-direction:column}
.mr-tasks li{display:flex;align-items:flex-start;gap:9px;padding:7px 0;border-bottom:1px solid var(--line);
  font-size:12.5px;line-height:1.3}
.mr-tasks li:last-child{border-bottom:0}
.mr-tasks li[data-done="1"] span{text-decoration:line-through;color:var(--fg3)}
.mr-tasks input{margin:2px 0 0;accent-color:var(--accent)}
.mr-add{display:flex;gap:7px;margin-top:9px}
.mr-add input{
  flex:1;min-width:0;height:30px;padding:0 10px;border:1px solid var(--line2);border-radius:8px;
  background:transparent;color:var(--fg);font:inherit;font-size:12.5px;outline:none}
.mr-add input:focus{border-color:#3b4048}
.mr-add input::placeholder{color:var(--fg3)}
`;

		async function api(path, body) {
			const options = body
				? {
						method: "POST",
						headers: { "content-type": "application/json", "x-dsh-machine": "1" },
						body: JSON.stringify(body),
					}
				: { method: "GET" };
			const res = await fetch(path, options);
			const data = await res.json().catch(() => ({}));
			if (!res.ok) throw new Error(data.message || data.error || `HTTP ${res.status}`);
			return data;
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

		function ageLabel(days) {
			if (days == null) return "—";
			if (days === 0) return "hoy";
			if (days === 1) return "ayer";
			if (days < 30) return `hace ${days} d`;
			const months = Math.floor(days / 30);
			return months === 1 ? "hace 1 mes" : `hace ${months} meses`;
		}

		function shortTitle(p) {
			const t = (p.title || "").trim();
			if (!t) return "";
			if (t.toLowerCase() === p.slug.toLowerCase()) return "";
			return t.replace(/^AGENTS\.md\s*—\s*/i, "").replace(/^#\s*/, "");
		}

		function IconSearch() {
			return h(
				"svg",
				{ width: 13, height: 13, viewBox: "0 0 16 16", fill: "none" },
				h("circle", { cx: 7, cy: 7, r: 4.6, stroke: "currentColor", strokeWidth: 1.4 }),
				h("path", {
					d: "M10.4 10.4 14 14",
					stroke: "currentColor",
					strokeWidth: 1.4,
					strokeLinecap: "round",
				}),
			);
		}

		function IconGithub() {
			return h(
				"svg",
				{ width: 12, height: 12, viewBox: "0 0 16 16", fill: "currentColor", "aria-hidden": "true" },
				h("path", {
					d:
						"M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38v-1.34c-2.22.48-2.69-1.07-2.69-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.05-.49.05-.49.81.06 1.23.83 1.23.83.72 1.23 1.88.87 2.34.67.07-.52.28-.87.5-1.07-1.77-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.03 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.28.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 0 0 8 0Z",
				}),
			);
		}

		function MachinePanel() {
			useStyles();
			const [projects, setProjects] = React.useState([]);
			const [filter, setFilter] = React.useState("all");
			const [sort, setSort] = React.useState("attention");
			const [query, setQuery] = React.useState("");
			const [selected, setSelected] = React.useState(null);
			const [detail, setDetail] = React.useState(null);
			const [error, setError] = React.useState("");
			const [loading, setLoading] = React.useState(true);
			const [updated, setUpdated] = React.useState(null);

			const load = React.useCallback(async () => {
				setLoading(true);
				try {
					const data = await api("/machine/projects");
					setProjects(data.projects || []);
					setUpdated(new Date());
					setError("");
				} catch (err) {
					setError(err.message);
				} finally {
					setLoading(false);
				}
			}, []);

			React.useEffect(() => {
				load();
			}, [load]);

			const open = React.useCallback(async (slug) => {
				setSelected(slug);
				setDetail(null);
				try {
					setDetail(await api(`/machine/project?slug=${encodeURIComponent(slug)}`));
				} catch (err) {
					setError(err.message);
				}
			}, []);

			const changeState = React.useCallback(
				async (slug, state) => {
					const before = projects.find((p) => p.slug === slug)?.state;
					setProjects((prev) => prev.map((p) => (p.slug === slug ? { ...p, state } : p)));
					try {
						await api("/machine/entity", { slug, state });
					} catch (err) {
						setError(err.message);
						setProjects((prev) => prev.map((p) => (p.slug === slug ? { ...p, state: before } : p)));
					}
				},
				[projects],
			);

			React.useEffect(() => {
				const onKey = (event) => {
					if (event.key === "Escape" && selected) {
						setSelected(null);
						setDetail(null);
					}
				};
				document.addEventListener("keydown", onKey);
				return () => document.removeEventListener("keydown", onKey);
			}, [selected]);

			const counts = React.useMemo(() => {
				const by = { unclassified: 0, active: 0, paused: 0, done: 0, archived: 0 };
				for (const p of projects) by[p.state] = (by[p.state] || 0) + 1;
				return {
					by,
					total: projects.length,
					stale: projects.filter(
						(p) => p.state !== "archived" && p.age_days != null && p.age_days >= 30,
					).length,
					dirty: projects.filter((p) => Number(p.facts?.dirty || 0) > 0).length,
					remotes: projects.filter((p) =>
						["github", "gitlab"].includes(p.facts?.remote_host || ""),
					).length,
				};
			}, [projects]);

			const rows = React.useMemo(() => {
				const q = query.trim().toLowerCase();
				let list = projects.filter((p) => (filter === "all" ? true : p.state === filter));
				if (q) {
					list = list.filter(
						(p) =>
							p.slug.toLowerCase().includes(q) ||
							(p.title || "").toLowerCase().includes(q) ||
							(p.note || "").toLowerCase().includes(q),
					);
				}
				const rank = (p) => STATES.indexOf(p.state);
				return list.slice().sort((a, b) => {
					if (sort === "name") return a.slug.localeCompare(b.slug);
					if (sort === "recent") return (a.age_days ?? 9999) - (b.age_days ?? 9999);
					if (rank(a) !== rank(b)) return rank(a) - rank(b);
					return (b.age_days ?? -1) - (a.age_days ?? -1);
				});
			}, [projects, filter, query, sort]);

			const pct = (n, of) => (of > 0 ? Math.min(100, Math.round((n / of) * 100)) : 0);

			const head = h(
				"div",
				{ className: "mr-head" },
				h(
					"div",
					{ className: "mr-title" },
					h("h1", null, "Proyectos"),
					h(
						"p",
						null,
						`${counts.total} proyectos · ${counts.remotes} con remoto · ` +
							(updated
								? `actualizado ${updated.toLocaleTimeString("es", {
										hour: "2-digit",
										minute: "2-digit",
									})}`
								: "cargando…"),
					),
				),
				h(
					"div",
					{ className: "mr-tools" },
					h(
						"div",
						{ className: "mr-search" },
						h(IconSearch),
						h("input", {
							placeholder: "Buscar proyecto…",
							value: query,
							onChange: (event) => setQuery(event.target.value),
							spellCheck: false,
						}),
					),
					h(
						"button",
						{ className: "mr-btn", onClick: load, disabled: loading, title: "Volver a leer el disco" },
						loading ? "…" : "Actualizar",
					),
				),
			);

			const kpi = (label, value, hint, color, fill) =>
				h(
					"div",
					{ className: "mr-kpi", key: label },
					h(
						"div",
						{ className: "k" },
						h("span", { className: "mr-dot", style: { background: color } }),
						label,
					),
					h("div", { className: "v" }, String(value)),
					h("div", { className: "h" }, hint),
					h(
						"div",
						{ className: "bar" },
						h("i", { style: { width: `${fill}%`, background: color } }),
					),
				);

			const kpis = h(
				"div",
				{ className: "mr-kpis" },
				kpi(
					"sin decidir",
					counts.by.unclassified || 0,
					"nadie eligió todavía",
					DOT.unclassified,
					pct(counts.by.unclassified || 0, counts.total),
				),
				kpi("activos", counts.by.active || 0, "tope recomendado: 3", DOT.active, pct(counts.by.active || 0, 3)),
				kpi("sin tocar +30 d", counts.stale, "candidatos a archivar", DOT.paused, pct(counts.stale, counts.total)),
				kpi("sin guardar", counts.dirty, "riesgo de perder trabajo", "#e5484d", pct(counts.dirty, counts.total)),
			);

			const filters = h(
				"div",
				{ className: "mr-filters" },
				["all", ...STATES].map((s) =>
					h(
						"button",
						{
							key: s,
							className: "mr-chip",
							"data-on": filter === s ? 1 : 0,
							onClick: () => setFilter(s),
						},
						s !== "all" ? h("span", { className: "mr-dot", style: { background: DOT[s] } }) : null,
						s === "all" ? "todos" : LABEL[s],
						h("span", { className: "n" }, String(s === "all" ? counts.total : counts.by[s] || 0)),
					),
				),
				h(
					"div",
					{ className: "mr-sort" },
					"orden",
					h(
						"select",
						{ value: sort, onChange: (event) => setSort(event.target.value) },
						h("option", { value: "attention" }, "atención"),
						h("option", { value: "recent" }, "más reciente"),
						h("option", { value: "name" }, "nombre"),
					),
				),
			);

			const table = h(
				"div",
				{ className: "mr-list" },
				h(
					"table",
					null,
					h(
						"colgroup",
						null,
						h("col", { style: { width: "34%" } }),
						h("col", { style: { width: "14%" } }),
						h("col", { style: { width: "13%" } }),
						h("col", { style: { width: "15%" } }),
						h("col", { style: { width: "12%" } }),
						h("col", { style: { width: "12%" } }),
					),
					h(
						"thead",
						null,
						h(
							"tr",
							null,
							["proyecto", "estado", "últ. cambio", "remoto", "sin guardar", "tareas"].map((t) =>
								h("th", { key: t }, t),
							),
						),
					),
					h(
						"tbody",
						null,
						rows.length === 0
							? h(
									"tr",
									null,
									h("td", { colSpan: 6, className: "mr-empty" }, "Ningún proyecto con ese filtro."),
								)
							: rows.map((p) => {
									const f = p.facts || {};
									const dirty = Number(f.dirty || 0);
									const remote = f.remote_host || "";
									const isRemote = remote === "github" || remote === "gitlab";
									const stale = p.age_days != null && p.age_days >= 30;
									return h(
										"tr",
										{
											key: p.slug,
											"data-sel": selected === p.slug ? 1 : 0,
											onClick: () => open(p.slug),
										},
										h(
											"td",
											null,
											h(
												"div",
												{ className: "name" },
												h("b", null, p.slug),
												shortTitle(p) ? h("em", null, shortTitle(p)) : null,
											),
										),
										h(
											"td",
											{ onClick: (event) => event.stopPropagation() },
											h(
												"span",
												{ className: "mr-pill" },
												h("span", { className: "mr-dot", style: { background: DOT[p.state] } }),
												h(
													"select",
													{
														value: p.state,
														onChange: (event) => changeState(p.slug, event.target.value),
														title: "Cambiar estado",
													},
													STATES.map((s) => h("option", { key: s, value: s }, LABEL[s])),
												),
											),
										),
										h("td", { className: "mr-age", "data-stale": stale ? 1 : 0 }, ageLabel(p.age_days)),
										h(
											"td",
											null,
											h(
												"span",
												{ className: "mr-remote", "data-none": isRemote ? 0 : 1 },
												isRemote ? h(IconGithub) : null,
												isRemote ? remote : "sin remoto",
											),
										),
										h(
											"td",
											null,
											dirty > 0
												? h("span", { className: "mr-warn" }, "●", `${dirty}`)
												: h("span", { className: "mr-muted" }, "—"),
										),
										h("td", { className: "mr-num" }, String(f.tickets_open ?? 0)),
									);
								}),
					),
				),
			);

			function sheet() {
				if (!selected) return null;
				const close = () => {
					setSelected(null);
					setDetail(null);
				};
				if (!detail) {
					return h(
						"div",
						{ className: "mr-sheet" },
						h(
							"div",
							{ className: "mr-sheet-head" },
							h("h2", null, selected),
							h("button", { className: "mr-x", onClick: close }, "×"),
						),
						h("div", { className: "mr-sheet-body" }, h("p", { className: "mr-muted" }, "cargando…")),
					);
				}
				const f = detail.facts || {};
				const tasks = detail.tasks || [];
				const fact = (k, v, wide) =>
					h("div", { key: k, "data-wide": wide ? 1 : 0 }, h("dt", null, k), h("dd", null, String(v)));

				return h(
					"div",
					{ className: "mr-sheet" },
					h(
						"div",
						{ className: "mr-sheet-head" },
						h(
							"div",
							{ style: { minWidth: 0 } },
							h("h2", null, detail.slug),
							h("p", null, shortTitle(detail) || KIND_LABEL[detail.kind] || detail.kind),
						),
						h("button", { className: "mr-x", onClick: close, title: "Cerrar (Esc)" }, "×"),
					),
					h(
						"div",
						{ className: "mr-sheet-body" },
						h(
							"div",
							{ className: "mr-facts" },
							fact("estado", LABEL[detail.state] || detail.state),
							fact("tipo", KIND_LABEL[detail.kind] || detail.kind),
							fact("rama", f.branch || "—"),
							fact("último commit", f.last_commit || "—"),
							fact("sin guardar", `${f.dirty || 0} archivo(s)`),
							fact("sin subir", `${f.ahead ?? "—"} commit(s)`),
							fact("ruta", f.path || "—", true),
							fact("remoto", f.remote_url || "sin remoto", true),
						),
						h("div", { className: "mr-label" }, "nota"),
						h("textarea", {
							key: `${detail.slug}-${detail.updated_at}`,
							defaultValue: detail.note || "",
							placeholder: "Para qué es, en qué quedó, qué falta…",
							onBlur: async (event) => {
								const note = event.target.value;
								await api("/machine/entity", { slug: detail.slug, note }).catch((err) =>
									setError(err.message),
								);
								setProjects((prev) => prev.map((p) => (p.slug === detail.slug ? { ...p, note } : p)));
							},
						}),
						h("div", { className: "mr-label" }, `tareas · ${tasks.filter((t) => t.state !== "done").length}`),
						h(
							"ul",
							{ className: "mr-tasks" },
							tasks.length === 0
								? h("li", null, h("span", { className: "mr-muted" }, "sin tareas"))
								: tasks.map((t) =>
										h(
											"li",
											{ key: t.slug, "data-done": t.state === "done" ? 1 : 0 },
											h("input", {
												type: "checkbox",
												checked: t.state === "done",
												onChange: async (event) => {
													if (!event.target.checked) return;
													await api("/machine/task-done", { task: t.slug }).catch((err) =>
														setError(err.message),
													);
													open(detail.slug);
												},
											}),
											h("span", null, t.title),
										),
									),
						),
						h(
							"div",
							{ className: "mr-add" },
							h("input", {
								placeholder: "Nueva tarea…",
								onKeyDown: async (event) => {
									if (event.key !== "Enter") return;
									const title = event.target.value.trim();
									if (!title) return;
									event.target.value = "";
									await api("/machine/task", { slug: detail.slug, title }).catch((err) =>
										setError(err.message),
									);
									open(detail.slug);
								},
							}),
							h(
								"button",
								{
									className: "mr-btn",
									onClick: async (event) => {
										const input = event.currentTarget.previousSibling;
										const title = input?.value?.trim();
										if (!title) return;
										input.value = "";
										await api("/machine/task", { slug: detail.slug, title }).catch((err) =>
											setError(err.message),
										);
										open(detail.slug);
									},
								},
								"Agregar",
							),
						),
					),
				);
			}

			return h(
				"div",
				{ className: "mr" },
				head,
				error
					? h("div", { style: { padding: "0 26px 12px", fontSize: 11.5, color: "#e5484d" } }, error)
					: null,
				kpis,
				filters,
				h("div", { className: "mr-main" }, table, sheet()),
			);
		}

		function MachineIcon(props) {
			const size = props?.size ?? 16;
			return h(
				"svg",
				{ width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
				h("rect", { x: 1.6, y: 1.6, width: 5.4, height: 5.4, rx: 1.3, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 9, y: 1.6, width: 5.4, height: 5.4, rx: 1.3, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 1.6, y: 9, width: 5.4, height: 5.4, rx: 1.3, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 9, y: 9, width: 5.4, height: 5.4, rx: 1.3, stroke: "currentColor", strokeWidth: 1.3 }),
			);
		}

		function apply(ctx) {
			ctx.slots.inject("sidebar.panellist", () =>
				ctx.slots.register(
					{ name: "sidebar.panellist", id: PANEL_ID, order: 10, label: () => "Proyectos" },
					MachineIcon,
				),
			);
			ctx.slots.inject("main", () =>
				ctx.slots.register({ name: "main", key: PANEL_ID, inject: () => ({}) }, MachinePanel),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
