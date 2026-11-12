/**
 * dsh-local-machine — client half.
 *
 * Panel propio del harness (no un overlay): se registra como entrada de la
 * barra lateral (`sidebar.panellist`) y como panel de contenido (`main`), así
 * que al hacer clic reemplaza el chat en el centro y la barra lateral sigue
 * siendo la de la app.
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
.mx{height:100%;min-height:0;display:flex;flex-direction:column;background:var(--dsw-alias-bg-base,#0d0e10);color:var(--dsw-alias-label-primary,#e9e9ec);font:400 13px/1.45 system-ui,-apple-system,sans-serif}
.mx-head{display:flex;align-items:center;gap:12px;padding:20px 24px 14px;flex:none}
.mx-head h1{margin:0;font-size:17px;font-weight:600;letter-spacing:-.01em}
.mx-counters{display:flex;gap:12px;font-size:11.5px;color:var(--dsw-alias-label-tertiary,#8b8f98)}
.mx-counters b{color:var(--dsw-alias-label-primary,#e9e9ec);font-weight:600}
.mx-spacer{flex:1}
.mx-btn{height:28px;padding:0 12px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:8px;background:transparent;color:inherit;font:inherit;font-size:12px;cursor:pointer}
.mx-btn:hover{background:var(--dsw-alias-interactive-bg-hover,#24262b)}
.mx-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;padding:0 24px 16px;flex:none}
.mx-card{padding:14px 16px;border:1px solid var(--dsw-alias-border-l1,#23252a);border-radius:12px;background:var(--dsw-alias-bg-overlay,#15171a)}
.mx-card .n{font-size:23px;font-weight:600;line-height:1.05}
.mx-card .l{margin-top:3px;font-size:11.5px;color:var(--dsw-alias-label-tertiary,#8b8f98)}
.mx-filters{display:flex;flex-wrap:wrap;gap:6px;padding:0 24px 14px;flex:none}
.mx-chip{height:26px;padding:0 12px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:999px;background:transparent;color:var(--dsw-alias-label-secondary,#b9bdc6);font:inherit;font-size:12px;cursor:pointer}
.mx-chip[data-on="1"]{background:var(--dsw-alias-label-primary,#e9e9ec);color:var(--dsw-alias-label-primary-foreground,#141518);border-color:transparent}
.mx-body{flex:1;min-height:0;display:flex;border-top:1px solid var(--dsw-alias-border-l1,#1c1e21)}
.mx-table-wrap{flex:1;min-width:0;overflow:auto}
.mx table{width:100%;border-collapse:collapse;font-size:12.5px}
.mx thead th{position:sticky;top:0;z-index:1;background:var(--dsw-alias-bg-base,#0d0e10);text-align:left;padding:10px 14px;font-size:10.5px;letter-spacing:.06em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#8b8f98);border-bottom:1px solid var(--dsw-alias-border-l1,#23252a);font-weight:600;white-space:nowrap}
.mx tbody td{padding:9px 14px;border-bottom:1px solid var(--dsw-alias-border-l1,#1a1c1f);vertical-align:middle}
.mx tbody tr{cursor:pointer}
.mx tbody tr:hover td{background:var(--dsw-alias-interactive-bg-hover,#17191c)}
.mx tbody tr[data-sel="1"] td{background:var(--dsw-alias-interactive-bg-hover,#1b1e22)}
.mx .name b{font-weight:600}
.mx .name span{display:block;margin-top:1px;font-size:11px;color:var(--dsw-alias-label-tertiary,#8b8f98);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:34ch}
.mx select{height:26px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:7px;background:var(--dsw-alias-bg-overlay,#15171a);color:inherit;font:inherit;font-size:12px;padding:0 6px;cursor:pointer}
.mx .num{text-align:right;font-variant-numeric:tabular-nums;color:var(--dsw-alias-label-secondary,#b9bdc6);white-space:nowrap}
.mx .tag{display:inline-block;padding:1px 8px;border-radius:999px;font-size:10.5px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);color:var(--dsw-alias-label-secondary,#b9bdc6);white-space:nowrap}
.mx .tag[data-warn="1"]{border-color:var(--dsw-alias-state-warning-primary,#c08a2e);color:var(--dsw-alias-state-warning-primary,#c08a2e)}
.mx .tag[data-ok="1"]{border-color:var(--dsw-alias-state-success-primary,#3f9f63);color:var(--dsw-alias-state-success-primary,#3f9f63)}
.mx-detail{width:390px;min-width:340px;flex:none;border-left:1px solid var(--dsw-alias-border-l1,#23252a);padding:18px 20px 28px;overflow:auto;background:var(--dsw-alias-bg-overlay,#111214)}
.mx-detail h2{margin:0;font-size:15px;font-weight:600}
.mx-detail .sub{margin:2px 0 0;font-size:11.5px;color:var(--dsw-alias-label-tertiary,#8b8f98)}
.mx-detail .close{float:right}
.mx-kv{display:grid;grid-template-columns:104px 1fr;gap:6px 12px;margin:16px 0 0;font-size:12px}
.mx-kv dt{color:var(--dsw-alias-label-tertiary,#8b8f98)}
.mx-kv dd{margin:0;word-break:break-all}
.mx-label{margin:20px 0 7px;font-size:10.5px;letter-spacing:.06em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#8b8f98)}
.mx textarea{width:100%;box-sizing:border-box;min-height:70px;resize:vertical;padding:9px 10px;border:1px solid var(--dsw-alias-border-l2,#33363c);border-radius:9px;background:transparent;color:inherit;font:inherit;font-size:12.5px;outline:none}
.mx textarea:focus{border-color:var(--dsw-alias-state-business-primary,#4c8dff)}
.mx-tasks{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:6px}
.mx-tasks li{display:flex;align-items:flex-start;gap:9px;font-size:12.5px}
.mx-tasks li[data-done="1"] span{text-decoration:line-through;color:var(--dsw-alias-label-tertiary,#8b8f98)}
.mx-tasks input{margin:3px 0 0}
.mx-add{display:flex;gap:8px;margin-top:10px}
.mx-add input{flex:1;min-width:0;height:30px;padding:0 10px;border:1px solid var(--dsw-alias-border-l2,#33363c);border-radius:8px;background:transparent;color:inherit;font:inherit;font-size:12.5px;outline:none}
.mx-empty{padding:44px 24px;color:var(--dsw-alias-label-tertiary,#8b8f98)}
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

		function MachinePanel() {
			useStyles();
			const [projects, setProjects] = React.useState([]);
			const [filter, setFilter] = React.useState("all");
			const [selected, setSelected] = React.useState(null);
			const [detail, setDetail] = React.useState(null);
			const [error, setError] = React.useState("");
			const [loading, setLoading] = React.useState(true);

			const load = React.useCallback(async () => {
				setLoading(true);
				try {
					const data = await api("/machine/projects");
					const list = (data.projects || []).slice();
					list.sort((a, b) => {
						const rank = (p) => STATES.indexOf(p.state);
						if (rank(a) !== rank(b)) return rank(a) - rank(b);
						return (a.age_days ?? 9999) - (b.age_days ?? 9999);
					});
					setProjects(list);
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
						setProjects((prev) =>
							prev.map((p) => (p.slug === slug ? { ...p, state: before } : p)),
						);
					}
				},
				[projects],
			);

			const counts = React.useMemo(() => {
				const by = { unclassified: 0, active: 0, paused: 0, done: 0, archived: 0 };
				for (const p of projects) by[p.state] = (by[p.state] || 0) + 1;
				return {
					by,
					stale: projects.filter(
						(p) => p.state !== "archived" && p.age_days != null && p.age_days >= 30,
					).length,
					dirty: projects.filter((p) => Number(p.facts?.dirty || 0) > 0).length,
					remotes: projects.filter((p) =>
						["github", "gitlab"].includes(p.facts?.remote_host || ""),
					).length,
				};
			}, [projects]);

			const rows = projects.filter((p) => (filter === "all" ? true : p.state === filter));

			const head = h(
				"div",
				{ className: "mx-head" },
				h("h1", null, "Proyectos"),
				h(
					"div",
					{ className: "mx-counters" },
					h("span", null, h("b", null, String(projects.length)), " total"),
					h("span", null, h("b", null, String(counts.by.active || 0)), " activos"),
					h("span", null, h("b", null, String(counts.by.unclassified || 0)), " sin decidir"),
					h("span", null, h("b", null, String(counts.remotes)), " con remoto"),
				),
				h("div", { className: "mx-spacer" }),
				error
					? h(
							"span",
							{ style: { color: "var(--dsw-alias-state-error-primary,#ff6b6b)", fontSize: 11.5 } },
							error,
						)
					: null,
				h("button", { className: "mx-btn", onClick: load, disabled: loading }, loading ? "…" : "Actualizar"),
			);

			const cards = h(
				"div",
				{ className: "mx-cards" },
				[
					[counts.by.unclassified || 0, "sin decisión", "primero de la lista"],
					[counts.by.active || 0, "activos", "tope recomendado: 3"],
					[counts.stale, "sin tocar +30 días", "candidatos a archivar"],
					[counts.dirty, "con cambios sin guardar", "riesgo de perder trabajo"],
				].map(([n, label, hint]) =>
					h(
						"div",
						{ className: "mx-card", key: label },
						h("div", { className: "n" }, String(n)),
						h("div", { className: "l" }, `${label} · ${hint}`),
					),
				),
			);

			const filters = h(
				"div",
				{ className: "mx-filters" },
				["all", ...STATES].map((s) =>
					h(
						"button",
						{
							key: s,
							className: "mx-chip",
							"data-on": filter === s ? 1 : 0,
							onClick: () => setFilter(s),
						},
						s === "all" ? "todos" : LABEL[s],
					),
				),
			);

			const table = h(
				"div",
				{ className: "mx-table-wrap" },
				h(
					"table",
					null,
					h(
						"thead",
						null,
						h(
							"tr",
							null,
							["proyecto", "tipo", "estado", "últ. cambio", "remoto", "sin guardar", "tareas"].map(
								(t) => h("th", { key: t }, t),
							),
						),
					),
					h(
						"tbody",
						null,
						rows.length === 0
							? h("tr", null, h("td", { className: "mx-empty", colSpan: 7 }, "Nada con ese filtro."))
							: rows.map((p) => {
									const f = p.facts || {};
									const dirty = Number(f.dirty || 0);
									const remote = ["github", "gitlab"].includes(f.remote_host || "");
									return h(
										"tr",
										{
											key: p.slug,
											"data-sel": selected === p.slug ? 1 : 0,
											onClick: () => open(p.slug),
										},
										h(
											"td",
											{ className: "name" },
											h("b", null, p.slug),
											h("span", null, p.title || ""),
										),
										h("td", null, KIND_LABEL[p.kind] || p.kind),
										h(
											"td",
											{ onClick: (event) => event.stopPropagation() },
											h(
												"select",
												{
													value: p.state,
													onChange: (event) => changeState(p.slug, event.target.value),
												},
												STATES.map((s) => h("option", { key: s, value: s }, LABEL[s])),
											),
										),
										h("td", { className: "num" }, p.age_days == null ? "—" : `${p.age_days}d`),
										h(
											"td",
											null,
											h(
												"span",
												{ className: "tag", "data-ok": remote ? 1 : 0 },
												remote ? f.remote_host : "sin remoto",
											),
										),
										h(
											"td",
											null,
											dirty > 0
												? h("span", { className: "tag", "data-warn": 1 }, `${dirty} sin guardar`)
												: "—",
										),
										h("td", { className: "num" }, String(f.tickets_open ?? 0)),
									);
								}),
					),
				),
			);

			function detailPane() {
				if (!selected) {
					return h(
						"div",
						{ className: "mx-detail" },
						h("div", { className: "sub" }, "Elegí un proyecto de la lista."),
					);
				}
				if (!detail) {
					return h("div", { className: "mx-detail" }, h("div", { className: "sub" }, "cargando…"));
				}
				const f = detail.facts || {};
				const tasks = detail.tasks || [];
				return h(
					"div",
					{ className: "mx-detail" },
					h(
						"button",
						{
							className: "mx-btn close",
							onClick: () => {
								setSelected(null);
								setDetail(null);
							},
						},
						"Cerrar",
					),
					h("h2", null, detail.slug),
					h("p", { className: "sub" }, detail.title || ""),
					h(
						"dl",
						{ className: "mx-kv" },
						[
							["estado", LABEL[detail.state] || detail.state],
							["tipo", KIND_LABEL[detail.kind] || detail.kind],
							["ruta", f.path || "—"],
							["rama", f.branch || "—"],
							["último commit", f.last_commit || "—"],
							["remoto", f.remote_url || "sin remoto"],
							["sin guardar", `${f.dirty || 0} archivo(s)`],
							["sin subir", `${f.ahead || "—"} commit(s)`],
						].map(([k, v]) =>
							h(React.Fragment, { key: k }, h("dt", null, k), h("dd", null, String(v))),
						),
					),
					h("div", { className: "mx-label" }, "descripción / nota"),
					h("textarea", {
						key: `${detail.slug}-${detail.updated_at}`,
						defaultValue: detail.note || "",
						placeholder: "Para qué es, en qué quedó, qué falta…",
						onBlur: async (event) => {
							await api("/machine/entity", { slug: detail.slug, note: event.target.value }).catch(
								(err) => setError(err.message),
							);
						},
					}),
					h("div", { className: "mx-label" }, "tareas"),
					h(
						"ul",
						{ className: "mx-tasks" },
						tasks.length === 0
							? h("li", null, h("span", { style: { opacity: 0.6 } }, "sin tareas"))
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
						{ className: "mx-add" },
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
								className: "mx-btn",
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
				);
			}

			return h("div", { className: "mx" }, head, cards, filters, h("div", { className: "mx-body" }, table, detailPane()));
		}

		function MachineIcon(props) {
			const size = props?.size ?? 16;
			return h(
				"svg",
				{ width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
				h("rect", { x: 1.5, y: 1.5, width: 5.5, height: 5.5, rx: 1.2, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 9, y: 1.5, width: 5.5, height: 5.5, rx: 1.2, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 1.5, y: 9, width: 5.5, height: 5.5, rx: 1.2, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 9, y: 9, width: 5.5, height: 5.5, rx: 1.2, stroke: "currentColor", strokeWidth: 1.3 }),
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
				ctx.slots.register(
					{ name: "main", key: PANEL_ID, inject: () => ({}) },
					MachinePanel,
				),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
