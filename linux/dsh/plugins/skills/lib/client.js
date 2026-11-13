/**
 * dsh-local-skills — client half.
 *
 * Panel "Skills" en la barra lateral, justo debajo de Plugins. Muestra el
 * catálogo real del harness (lo que devuelve `ctx.skills`), no una carpeta
 * escaneada a mano: nombre, descripción, origen, ruta del SKILL.md y si la
 * puede usar el modelo, el usuario (comando) o ambas.
 *
 * Datos: GET /skills/list y GET /skills/read?name (mitad host de este plugin).
 * Solo lectura: no edita ni borra nada.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-skills",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const PANEL_ID = "skills";
		const STYLE_ID = "dsh-skills-style";

		/** Origen → grupo visible. Lo que no esté acá cae en "Otras". */
		const GROUP = {
			"user-agents": { key: "user", label: "Tuyas" },
			"user-dsh": { key: "user", label: "Tuyas" },
			"project-agents": { key: "project", label: "Del proyecto" },
			"project-dsh": { key: "project", label: "Del proyecto" },
			runtime: { key: "plugin", label: "De plugins" },
			bundled: { key: "plugin", label: "De plugins" },
			custom: { key: "custom", label: "Otras" },
		};
		const GROUP_ORDER = ["user", "project", "plugin", "custom"];
		const GROUP_TITLE = { user: "Tuyas", project: "Del proyecto", plugin: "De plugins", custom: "Otras" };

		const CSS = `
.sk{
  --sk-fg: var(--dsw-alias-label-primary, #eceef2);
  --sk-fg2: var(--dsw-alias-label-secondary, #a3a8b3);
  --sk-fg3: var(--dsw-alias-label-tertiary, #737985);
  --sk-cap: var(--dsw-alias-label-caption, #737985);
  --sk-l1: var(--dsw-alias-border-l1, #ffffff0f);
  --sk-l2: var(--dsw-alias-border-l2, #ffffff1f);
  --sk-l4: var(--dsw-alias-border-l4, #ffffff33);
  --sk-hover: var(--dsw-alias-interactive-bg-hover, #ffffff14);
  --sk-field: var(--dsw-alias-bg-layer-1, transparent);
  --sk-ok: var(--dsw-alias-state-success-primary, #2fb36b);
  --sk-info: var(--dsw-alias-state-business-primary, #4d6bfe);
  --sk-mono: var(--ds-font-family-code, ui-monospace, SFMono-Regular, Menlo, monospace);
  --sk-ring: var(--dsw-focus-ring-width, 2px) solid var(--dsw-focus-ring-color, var(--sk-info));
  box-sizing:border-box;height:100%;min-height:0;overflow:auto;color:var(--sk-fg);
  display:flex;flex-direction:column;align-items:center;gap:22px;
  padding:0 clamp(24px,4vw,48px) 48px;font-size:13px;line-height:20px;
}
.sk *{box-sizing:border-box}
.sk>*{width:100%;max-width:960px}
:where(.sk) button{font:inherit}
.sk :focus-visible{outline:var(--sk-ring);outline-offset:1px}

.sk-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding-top:28px}
.sk-h1{margin:0;font-size:20px;font-weight:500;line-height:28px}
.sk-intro{margin:4px 0 0;font-size:13px;line-height:20px;color:var(--sk-fg2);display:flex;flex-wrap:wrap;gap:0 6px}
.sk-intro b{font-weight:500;color:var(--sk-fg);font-variant-numeric:tabular-nums}
.sk-intro i{font-style:normal;color:var(--sk-cap)}
.sk-tools{display:flex;align-items:center;gap:8px;flex:none}
.sk-search{display:inline-flex;align-items:center;gap:6px;height:32px;width:240px;padding:0 10px;
  border:.5px solid var(--sk-l4);border-radius:var(--dsw-radius-md,12px);background:var(--sk-field)}
.sk-search:focus-within{border-color:var(--sk-info)}
.sk-search svg{flex:none;color:var(--sk-fg3)}
.sk-search input{flex:1;min-width:0;border:0;outline:0;background:transparent;color:var(--sk-fg);
  font:inherit;font-size:13px;line-height:20px}
.sk-search input::placeholder{color:var(--sk-fg3)}
.sk-ghost{display:inline-flex;align-items:center;gap:6px;height:32px;padding:0 10px;border:.5px solid transparent;
  border-radius:var(--dsw-radius-md,12px);background:transparent;color:var(--sk-fg2);cursor:pointer}
.sk-ghost:hover{background:var(--sk-hover);color:var(--sk-fg)}
.sk-ghost[disabled]{opacity:.5;cursor:default}

.sk-groups{display:flex;flex-direction:column;gap:26px;padding-bottom:8px}
.sk-group-head{margin:0 0 2px;font-size:12px;line-height:20px;font-weight:500;color:var(--sk-fg2);
  display:flex;align-items:center;gap:8px}
.sk-group-head .n{color:var(--sk-cap);font-weight:400;font-variant-numeric:tabular-nums}
.sk-rows{list-style:none;margin:0;padding:0;border-top:.5px solid var(--sk-l2)}
.sk-row{display:flex;align-items:flex-start;gap:14px;padding:11px 10px;margin:0 -10px;
  border-bottom:.5px solid var(--sk-l1);border-radius:var(--dsw-radius-sm,8px);cursor:pointer;
  text-align:left;width:calc(100% + 20px);background:transparent;border-left:0;border-right:0;border-top:0;color:inherit;font:inherit}
.sk-row:hover{background:var(--sk-hover)}
.sk-main{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.sk-name{font-size:13px;line-height:20px;color:var(--sk-fg);font-family:var(--sk-mono);font-weight:500;
  overflow-wrap:anywhere}
.sk-desc{font-size:12.5px;line-height:18px;color:var(--sk-fg2);
  display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.sk-path{margin-top:2px;font-size:11.5px;line-height:16px;color:var(--sk-cap);font-family:var(--sk-mono);
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;direction:rtl;text-align:left}
.sk-side{flex:none;display:flex;flex-direction:column;align-items:flex-end;gap:5px;padding-top:1px}
.sk-tags{display:flex;gap:5px;align-items:center}
.sk-tag{display:inline-flex;align-items:center;height:18px;padding:0 7px;border-radius:999px;
  border:.5px solid var(--sk-l4);font-size:11px;line-height:16px;color:var(--sk-fg2);white-space:nowrap}
.sk-tag.model{color:var(--sk-info);border-color:color-mix(in srgb, var(--sk-info) 45%, transparent)}
.sk-tag.cmd{color:var(--sk-ok);border-color:color-mix(in srgb, var(--sk-ok) 40%, transparent)}
.sk-src{font-size:11px;line-height:16px;color:var(--sk-cap)}

.sk-empty{margin:8px 0 0;font-size:13px;line-height:20px;color:var(--sk-fg2)}
.sk-ignored{font-size:12px;line-height:18px;color:var(--sk-fg3)}
.sk-ignored summary{cursor:pointer}
.sk-ignored-list{list-style:none;margin:6px 0 0;padding:0;display:flex;flex-direction:column;gap:2px}
.sk-ignored-list li{display:flex;gap:8px;flex-wrap:wrap}
.sk-ignored-list .n{font-family:var(--sk-mono);color:var(--sk-fg2)}
.sk-ignored-list .r{color:var(--sk-cap)}
.sk-note{margin:0;font-size:12px;line-height:18px;color:var(--sk-fg3)}
.sk-error{margin:0;font-size:13px;line-height:20px;color:var(--dsw-alias-state-error-primary,#f25a5a)}
.sk-skel{display:flex;flex-direction:column;gap:9px;padding:14px 10px 6px;border-top:.5px solid var(--sk-l2)}
.sk-sk{height:11px;border-radius:4px;background:var(--sk-l2);animation:sk-pulse 1.4s ease-in-out infinite}
@keyframes sk-pulse{0%,100%{opacity:.4}50%{opacity:.9}}
@media (prefers-reduced-motion:reduce){.sk-sk{animation:none;opacity:.6}}

.sk-detail{display:flex;flex-direction:column;gap:14px;padding-top:28px;padding-bottom:8px}
.sk-crumb{display:inline-flex;align-items:center;gap:6px;align-self:flex-start;height:28px;padding:0 8px;
  margin-left:-8px;border:0;border-radius:var(--dsw-radius-sm,8px);background:transparent;color:var(--sk-fg2);cursor:pointer}
.sk-crumb:hover{background:var(--sk-hover);color:var(--sk-fg)}
.sk-dtitle{margin:0;font-size:20px;font-weight:500;line-height:28px;font-family:var(--sk-mono);overflow-wrap:anywhere}
.sk-dmeta{display:flex;flex-wrap:wrap;align-items:center;gap:8px;font-size:12px;line-height:18px;color:var(--sk-cap)}
.sk-dmeta .p{font-family:var(--sk-mono);color:var(--sk-fg3);overflow-wrap:anywhere}
.sk-ddesc{margin:0;font-size:13px;line-height:20px;color:var(--sk-fg2)}
.sk-body{margin:0;padding:14px 16px;border:.5px solid var(--sk-l2);border-radius:var(--dsw-radius-md,12px);
  background:var(--sk-field);font-family:var(--sk-mono);font-size:12.5px;line-height:19px;color:var(--sk-fg);
  white-space:pre-wrap;overflow-wrap:anywhere;max-height:none}

/* Celular: una columna, sin ruta, campos de 16px (iOS no hace zoom) y
   objetivos táctiles de 36px. Breakpoint único del producto: 820px. */
@media (max-width:820px){
  .sk{padding:0 14px 32px;gap:16px}
  .sk-head{flex-direction:column;gap:10px;padding-top:18px}
  .sk-tools{width:100%}
  .sk-search{width:100%;height:36px}
  .sk-search input{font-size:16px}
  .sk-ghost{height:36px}
  .sk-row{padding:12px 8px;margin:0 -8px;width:calc(100% + 16px);gap:8px}
  .sk-name{font-size:14px;line-height:21px}
  .sk-path{display:none}
  .sk-side{flex-direction:row;align-items:center;gap:6px}
  .sk-src{display:none}
  .sk-crumb{height:36px}
  .sk-dtitle{font-size:18px;line-height:26px}
  .sk-body{font-size:12px;line-height:18px;padding:12px}
  .sk-detail{padding-top:18px}
}
`;

		const ICON_SEARCH = h(
			"svg",
			{ width: 14, height: 14, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
			h("circle", { cx: 7, cy: 7, r: 4.2, stroke: "currentColor", strokeWidth: 1.3 }),
			h("path", { d: "M10.2 10.2 14 14", stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "round" }),
		);
		const ICON_BACK = h(
			"svg",
			{ width: 14, height: 14, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
			h("path", {
				d: "M9.5 3.5 5 8l4.5 4.5",
				stroke: "currentColor",
				strokeWidth: 1.4,
				strokeLinecap: "round",
				strokeLinejoin: "round",
			}),
		);

		function ensureStyle() {
			if (document.getElementById(STYLE_ID) !== null) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = CSS;
			document.head.appendChild(style);
		}

		async function getJson(path) {
			const res = await fetch(path, { headers: { accept: "application/json" } });
			const body = await res.json().catch(() => null);
			if (!res.ok || body === null || body.ok !== true) {
				throw new Error((body && body.error) || `HTTP ${res.status}`);
			}
			return body;
		}

		function groupOf(source) {
			return GROUP[source]?.key ?? "custom";
		}

		function matches(skill, terms) {
			if (terms.length === 0) return true;
			const haystack = `${skill.name} ${skill.description} ${skill.whenToUse} ${skill.source}`.toLowerCase();
			return terms.every((term) => haystack.includes(term));
		}

		function tagsFor(skill) {
			const tags = [];
			if (skill.model) tags.push(h("span", { key: "m", className: "sk-tag model" }, "modelo"));
			if (skill.user) {
				tags.push(h("span", { key: "u", className: "sk-tag cmd" }, skill.model ? "comando" : "solo comando"));
			}
			if (tags.length === 0) tags.push(h("span", { key: "n", className: "sk-tag" }, "oculta"));
			return tags;
		}

		function SkillRow(props) {
			const skill = props.skill;
			return h(
				"li",
				null,
				h(
					"button",
					{
						type: "button",
						className: "sk-row",
						onClick: () => props.onOpen(skill.name),
						title: "Ver el SKILL.md",
					},
					h(
						"div",
						{ className: "sk-main" },
						h("span", { className: "sk-name" }, skill.name),
						skill.description ? h("span", { className: "sk-desc" }, skill.description) : null,
						skill.path ? h("span", { className: "sk-path" }, skill.path) : null,
					),
					h(
						"div",
						{ className: "sk-side" },
						h("div", { className: "sk-tags" }, tagsFor(skill)),
						h("span", { className: "sk-src" }, skill.source),
					),
				),
			);
		}

		function Detail(props) {
			const { skill, status, error, onBack, onRetry } = props;
			const [copied, setCopied] = React.useState(false);

			React.useEffect(() => {
				if (!copied) return undefined;
				const timer = setTimeout(() => setCopied(false), 1400);
				return () => clearTimeout(timer);
			}, [copied]);

			if (status === "loading") {
				return h(
					"div",
					{ className: "sk-detail", "aria-busy": "true" },
					h("button", { type: "button", className: "sk-crumb", onClick: onBack }, ICON_BACK, "Skills"),
					h("div", { className: "sk-skel" }, [0, 1, 2].map((i) => h("span", { key: i, className: "sk-sk" }))),
				);
			}
			if (status === "error") {
				return h(
					"div",
					{ className: "sk-detail" },
					h("button", { type: "button", className: "sk-crumb", onClick: onBack }, ICON_BACK, "Skills"),
					h("p", { className: "sk-error" }, `No pude leer la skill: ${error}`),
					h("button", { type: "button", className: "sk-ghost", onClick: onRetry }, "Reintentar"),
				);
			}
			return h(
				"div",
				{ className: "sk-detail" },
				h(
					"button",
					{ type: "button", className: "sk-crumb", onClick: onBack, title: "Volver (Esc)" },
					ICON_BACK,
					"Skills",
				),
				h("h1", { className: "sk-dtitle" }, skill.name),
				h(
					"div",
					{ className: "sk-dmeta" },
					h("div", { className: "sk-tags" }, tagsFor(skill)),
					h("span", null, skill.source),
					skill.path ? h("span", { className: "p" }, skill.path) : null,
					skill.path
						? h(
								"button",
								{
									type: "button",
									className: "sk-ghost",
									style: { height: 24, padding: "0 8px", fontSize: 12 },
									onClick: () => {
										navigator.clipboard?.writeText(skill.path).then(
											() => setCopied(true),
											() => setCopied(false),
										);
									},
								},
								copied ? "Copiada" : "Copiar ruta",
							)
						: null,
				),
				skill.description ? h("p", { className: "sk-ddesc" }, skill.description) : null,
				h("pre", { className: "sk-body" }, skill.content),
			);
		}

		function SkillsPanel() {
			const [state, setState] = React.useState({ status: "loading" });
			const [query, setQuery] = React.useState("");
			const [detail, setDetail] = React.useState(null);
			const searchRef = React.useRef(null);

			const load = React.useCallback(async () => {
				setState((prev) => (prev.status === "ready" ? { ...prev, refreshing: true } : { status: "loading" }));
				try {
					const data = await getJson("/skills/list");
					setState({ status: "ready", data });
				} catch (error) {
					setState({ status: "error", error: error instanceof Error ? error.message : String(error) });
				}
			}, []);

			React.useEffect(() => {
				ensureStyle();
				load();
			}, [load]);

			const openSkill = React.useCallback(async (name) => {
				setDetail({ status: "loading", name });
				try {
					const body = await getJson(`/skills/read?name=${encodeURIComponent(name)}`);
					setDetail({ status: "ready", name, skill: body.skill });
				} catch (error) {
					setDetail({ status: "error", name, error: error instanceof Error ? error.message : String(error) });
				}
			}, []);

			React.useEffect(() => {
				function onKey(event) {
					if (event.key === "Escape" && detail !== null) {
						event.preventDefault();
						setDetail(null);
						return;
					}
					const typing = event.target instanceof HTMLElement && /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
					if (event.key === "/" && !typing && detail === null) {
						event.preventDefault();
						searchRef.current?.focus();
					}
				}
				window.addEventListener("keydown", onKey);
				return () => window.removeEventListener("keydown", onKey);
			}, [detail]);

			if (detail !== null) {
				return h(
					"div",
					{ className: "sk" },
					h(Detail, {
						status: detail.status,
						skill: detail.skill,
						error: detail.error,
						onBack: () => setDetail(null),
						onRetry: () => openSkill(detail.name),
					}),
				);
			}

			const ready = state.status === "ready";
			const skills = ready ? state.data.skills : [];
			const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
			const visible = skills.filter((skill) => matches(skill, terms));

			const buckets = new Map();
			for (const skill of visible) {
				const key = groupOf(skill.source);
				if (!buckets.has(key)) buckets.set(key, []);
				buckets.get(key).push(skill);
			}

			return h(
				"div",
				{ className: "sk" },
				h(
					"header",
					{ className: "sk-head" },
					h(
						"div",
						null,
						h("h1", { className: "sk-h1" }, "Skills"),
						ready
							? h(
									"p",
									{ className: "sk-intro" },
									h("span", null, h("b", null, String(state.data.count)), "skills"),
									h("i", null, "·"),
									h("span", null, h("b", null, String(state.data.model)), "las ve el modelo"),
									h("i", null, "·"),
									h("span", null, h("b", null, String(state.data.command)), "solo por /comando"),
								)
							: h("p", { className: "sk-intro" }, h("span", null, "Leyendo el catálogo del harness…")),
					),
					h(
						"div",
						{ className: "sk-tools" },
						h(
							"label",
							{ className: "sk-search" },
							ICON_SEARCH,
							h("input", {
								ref: searchRef,
								type: "search",
								value: query,
								placeholder: "Buscar skill",
								"aria-label": "Buscar skill",
								onChange: (event) => setQuery(event.target.value),
								onKeyDown: (event) => {
									if (event.key === "Escape") setQuery("");
								},
							}),
						),
						h(
							"button",
							{
								type: "button",
								className: "sk-ghost",
								onClick: load,
								disabled: ready && state.refreshing === true,
							},
							ready && state.refreshing === true ? "Actualizando…" : "Actualizar",
						),
					),
				),
				state.status === "error"
					? h(
							"div",
							null,
							h("p", { className: "sk-error" }, `No pude leer las skills: ${state.error}`),
							h("p", { className: "sk-note" }, "El endpoint /skills/list no respondió. Revisá el log de dsh-web."),
						)
					: null,
				state.status === "loading"
					? h(
							"div",
							{ className: "sk-skel", "aria-busy": "true" },
							[0, 1, 2, 3, 4].map((i) => h("span", { key: i, className: "sk-sk" })),
						)
					: null,
				ready
					? h(
							"div",
							{ className: "sk-groups" },
							GROUP_ORDER.filter((key) => buckets.has(key)).map((key) =>
								h(
									"section",
									{ key },
									h(
										"h2",
										{ className: "sk-group-head" },
										GROUP_TITLE[key],
										h("span", { className: "n" }, String(buckets.get(key).length)),
									),
									h(
										"ul",
										{ className: "sk-rows" },
										buckets.get(key).map((skill) => h(SkillRow, { key: skill.name, skill, onOpen: openSkill })),
									),
								),
							),
						)
					: null,
				ready && visible.length === 0
					? h(
							"p",
							{ className: "sk-empty" },
							query ? `Nada coincide con “${query}”.` : "No hay skills cargadas en este perfil.",
						)
					: null,
				ready && state.data.ignored.length > 0
					? h(
							"details",
							{ className: "sk-ignored" },
							h(
								"summary",
								null,
								`${state.data.ignored.length} entrada(s) que el harness no carga`,
							),
							h(
								"ul",
								{ className: "sk-ignored-list" },
								state.data.ignored.map((item, index) =>
									h(
										"li",
										{ key: `${item.name}-${index}` },
										h("span", { className: "n" }, item.name),
										h("span", { className: "r" }, item.reason),
									),
								),
							),
						)
					: null,
				ready
					? h(
							"p",
							{ className: "sk-note" },
							`Solo lectura. Buscando en ${state.data.roots
								.filter((root) => root.exists)
								.map((root) => root.path)
								.join(" · ")}`,
						)
					: null,
			);
		}

		function SkillsIcon(props) {
			const size = props?.size ?? 16;
			return h(
				"svg",
				{ width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
				h("path", {
					d: "M7 1.8 8.35 5.1 11.7 6.45 8.35 7.8 7 11.1 5.65 7.8 2.3 6.45 5.65 5.1Z",
					fill: "currentColor",
				}),
				h("path", {
					d: "M11.9 9.4 12.55 10.9 14.1 11.55 12.55 12.2 11.9 13.7 11.25 12.2 9.7 11.55 11.25 10.9Z",
					fill: "currentColor",
					opacity: 0.7,
				}),
			);
		}

		function apply(ctx) {
			ctx.slots.inject("sidebar.panellist", () =>
				ctx.slots.register(
					{ name: "sidebar.panellist", id: PANEL_ID, order: 1, label: () => "Skills" },
					SkillsIcon,
				),
			);
			ctx.slots.inject("main", () =>
				ctx.slots.register({ name: "main", key: PANEL_ID, inject: () => ({}) }, SkillsPanel),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
