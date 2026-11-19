/**
 * dsh-local-evidence — client half.
 *
 * Dos piezas, las dos con evidencia real del log de la sesión:
 *   - Tarjeta sobre el compositor: la prueba visual del último pedido terminado,
 *     con un resumen corto de lo que hizo el agente y un selector para mirar
 *     la evidencia de cualquier otra tarea de la conversación.
 *   - Vista "Evidencia" al lado de Chat y Tareas: todas las tareas de la sesión,
 *     cada una con su resumen, sus capturas y sus entregables.
 *
 * El nombre de cada tarea es su objetivo (/tasks/* lo guarda en `goal`); el
 * título corto queda como respaldo cuando la tarea no declaró objetivo.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-evidence",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;
		const { useEffect, useState } = React;

		/** El menú real del harness da el estilo; si no está, la tarjeta sigue en texto. */
		let primitives = null;
		try {
			primitives = require("@deepseek-ai/dsh-client-ui-primitives");
		} catch (error) {
			primitives = null;
		}
		const Menu = primitives && typeof primitives.Menu === "function" ? primitives.Menu : null;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const STYLE_ID = "dsh-local-evidence-style";
		const CSS = [
			".evd-root{box-sizing:border-box;width:calc(100% - var(--dsh-composer-side-clearance,0px) - var(--dsh-composer-side-clearance,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px));max-width:calc(var(--dsh-composer-card-max-width,952px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px));border-radius:var(--dsw-radius-lg,16px);background:var(--dsw-specific-menu,#202226);box-shadow:var(--dsw-elevation-panel,0 10px 30px #0007);backdrop-filter:var(--dsw-menu-backdrop-filter,blur(20px));flex:none;margin:0 auto;overflow:hidden}",
			".evd-body{display:flex;flex-direction:column;padding:6px 12px}",
			".evd-head{display:flex;align-items:center;gap:8px;width:100%;min-width:0}",
			".evd-toggle{display:flex;align-items:center;gap:8px;flex:none;height:24px;margin-left:-4px;padding:0 4px;border:0;border-radius:6px;background:transparent;font:inherit;color:inherit;cursor:pointer}",
			".evd-toggle:hover{background:var(--dsw-alias-bg-layer-2,#1d2027)}",
			".evd-toggle:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".evd-lead{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-title{flex:none;font-size:13px;font-weight:500;line-height:24px;color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-chevron{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3);transition:transform .18s ease}.evd-chevron[data-open='true']{transform:rotate(180deg)}",
			".evd-pick{display:flex;align-items:center;gap:6px;flex:0 1 auto;min-width:0;max-width:min(520px,46ch);height:24px;padding:0 6px;margin-left:-2px;border:0;border-radius:6px;background:transparent;font:inherit;color:var(--dsw-alias-label-secondary,#b9b9c2);cursor:pointer}",
			".evd-pick:hover{background:var(--dsw-alias-bg-layer-2,#1d2027);color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-pick:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".evd-pick-name{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;line-height:20px}",
			".evd-caret{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-task{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:400;line-height:20px;color:var(--dsw-alias-label-secondary,#b9b9c2)}",
			".evd-progress{flex:1 1 auto;min-width:0;margin-left:auto;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-align:right;font-size:12px;font-weight:400;line-height:20px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-panel{max-height:320px;overflow-y:auto;margin-top:6px;padding-top:8px;border-top:1px solid var(--dsw-alias-border-l1,#2c2f36);--dsh-scrollbar-thumb:var(--dsw-alias-scrollbar-bg-l2)}",
			".evd-summary{margin:0 0 8px;font-size:12.5px;line-height:1.55;color:var(--dsw-alias-label-secondary,#b9b9c2);display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}",
			".evd-more{margin:6px 0 0;font:400 12px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-empty{margin:0;font-size:12.5px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-gallery{display:flex;flex-wrap:wrap;gap:6px}.evd-thumb{display:block;width:132px;height:82px;border-radius:6px;overflow:hidden;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:var(--dsw-alias-bg-layer-1,#16181c);cursor:zoom-in}.evd-thumb img{width:100%;height:100%;object-fit:cover;display:block}",
			".evd-thumb:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}.evd-video{width:212px;height:120px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:#000}",
			".evd-opt{display:flex;align-items:baseline;gap:10px;min-width:0;max-width:100%}",
			".evd-opt-name{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".evd-opt-state{flex:none;font-size:11.5px;line-height:16px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-menu{min-width:340px;max-width:min(620px,90vw)}",
			"@media (max-width:600px){.evd-pick{flex:1 1 auto;max-width:none}.evd-progress{display:none}}",
			".evd-group-h{margin:10px 0 4px;font-size:12px;font-weight:500;line-height:18px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-file{display:flex;align-items:center;gap:7px;margin:1px -6px;padding:5px 6px;border-radius:7px;text-decoration:none;color:var(--dsw-alias-label-primary,#e9e9ee)}",
			".evd-file:hover{background:var(--dsw-alias-bg-layer-2,#1d2027)}",
			".evd-file:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".evd-file-icon{flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-file-name{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:400 12.5px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif}",
			".evd-file-desc{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:400 12px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
		].join("\n");

		function useStyles() {
			useEffect(() => {
				let style = document.getElementById(STYLE_ID);
				if (!style) {
					style = document.createElement("style");
					style.id = STYLE_ID;
					document.head.appendChild(style);
				}
				if (style.textContent !== CSS) style.textContent = CSS;
			}, []);
		}

		function fileUrl(path) {
			return `/api/file?path=${encodeURIComponent(path)}`;
		}

		function getJson(path) {
			return fetch(path, { headers: { accept: "application/json" } }).then((response) => (response.ok ? response.json() : null));
		}

		/** El nombre de la tarea es su objetivo; el título corto solo si no hay objetivo. */
		function nameOf(task) {
			const goal = String(task?.goal ?? "").trim();
			if (goal) return goal;
			const title = String(task?.title ?? "").trim();
			return title || "Tarea sin título";
		}

		/** Un renglón de estado: lo que el host ya resolvió, sin inventar nada. */
		function stateOf(task) {
			const state = String(task?.state ?? "").trim();
			if (task?.outcome === "falló") return "falló";
			if (state === "resuelta") return "resuelta";
			if (state === "cancelada") return "cancelada";
			const status = String(task?.status ?? "").trim();
			if (status) return status;
			return state || "abierta";
		}

		/** Nombre del archivo, sin la ruta: el entregable se ve como archivo. */
		function fileName(file) {
			const name = String(file?.name ?? "").trim();
			if (name) return name;
			const path = String(file?.path ?? "");
			return path.split("/").filter(Boolean).pop() ?? "archivo";
		}

		function fileIcon() {
			return h(
				"svg",
				{ width: 14, height: 14, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none", className: "evd-file-icon" },
				h("path", {
					d: "M9 1.8H4.6A1.6 1.6 0 0 0 3 3.4v9.2a1.6 1.6 0 0 0 1.6 1.6h6.8a1.6 1.6 0 0 0 1.6-1.6V5.2L9 1.8Z",
					stroke: "currentColor",
					strokeWidth: 1.2,
					strokeLinejoin: "round",
				}),
				h("path", { d: "M9 1.9v3.4h3.9", stroke: "currentColor", strokeWidth: 1.2, strokeLinejoin: "round" }),
			);
		}

		function Gallery(props) {
			const media = (props.media ?? []).slice(0, props.max ?? 99);
			return h(
				"div",
				{ className: "evd-gallery", style: { marginTop: 8 } },
				media.map((item) =>
					item.kind === "video"
						? h("video", { key: item.path, className: "evd-video", controls: true, preload: "metadata", src: item.url })
						: h(
								"a",
								{ key: item.path, className: "evd-thumb", href: item.url, target: "_blank", rel: "noreferrer", title: item.label },
								h("img", { src: item.url, alt: item.label, loading: "lazy" }),
							),
				),
			);
		}

		function Deliverables(props) {
			const items = props.items ?? [];
			if (!items.length) return null;
			return h(
				"div",
				null,
				h("p", { className: "evd-group-h" }, `Entregables · ${items.length}`),
				items.map((file) =>
					h(
						"a",
						{ className: "evd-file", key: file.path, href: fileUrl(file.path), target: "_blank", rel: "noreferrer" },
						fileIcon(),
						h("span", { className: "evd-file-name" }, fileName(file)),
						file.description ? h("span", { className: "evd-file-desc" }, file.description) : null,
					),
				),
			);
		}

		/** El último pedido terminado con prueba visual; es lo que muestra la tarjeta sola. */
		function useTurnEvidence(sessionId) {
			const [turn, setTurn] = useState(null);
			useEffect(() => {
				if (!sessionId) {
					setTurn(null);
					return undefined;
				}
				let cancelled = false;
				const load = () => {
					getJson(`/tasks/turn?session=${encodeURIComponent(sessionId)}`)
						.then((payload) => {
							if (!cancelled) setTurn(payload);
						})
						.catch(() => {});
				};
				load();
				const timer = setInterval(load, 15000);
				return () => {
					cancelled = true;
					clearInterval(timer);
				};
			}, [sessionId]);
			return turn;
		}

		/** Todas las tareas de la conversación, cada una con su evidencia y su objetivo. */
		function useSessionTasks(sessionId) {
			const [tasks, setTasks] = useState([]);
			useEffect(() => {
				if (!sessionId) {
					setTasks([]);
					return undefined;
				}
				let cancelled = false;
				const load = () => {
					Promise.all([getJson(`/tasks/session?session=${encodeURIComponent(sessionId)}`), getJson("/tasks/all")])
						.then(([session, all]) => {
							if (cancelled) return;
							const goals = new Map(((all && all.tasks) || []).map((task) => [task.id, String(task.goal ?? "")]));
							const items = ((session && session.tasks) || []).map((item) => ({ ...item, goal: goals.get(item.id) ?? "" }));
							setTasks(items);
						})
						.catch(() => {});
				};
				load();
				const timer = setInterval(load, 15000);
				return () => {
					cancelled = true;
					clearInterval(timer);
				};
			}, [sessionId]);
			return tasks;
		}

		function EvidenceCard(props) {
			useStyles();
			const proof = useTurnEvidence(props.sessionId);
			const tasks = useSessionTasks(props.sessionId);
			const [open, setOpen] = useState(false);
			const [menuOpen, setMenuOpen] = useState(false);
			const [pickedId, setPickedId] = useState("auto");

			// Otra conversación = otra lista de tareas: el selector vuelve al último paso.
			useEffect(() => {
				setPickedId("auto");
				setMenuOpen(false);
			}, [props.sessionId]);

			const picked = pickedId === "auto" ? null : tasks.find((item) => item.id === pickedId) ?? null;
			// Con "auto" la tarjeta muestra el último pedido terminado; el menú marca ese renglón.
			const latestId = String(proof?.task?.id ?? "");
			const latest = latestId ? tasks.find((item) => item.id === latestId) ?? null : null;
			const selectedId = picked ? picked.id : latest?.id ?? "auto";
			const media = picked ? picked.media ?? [] : proof?.evidence?.media ?? [];
			const deliverables = picked ? picked.deliverables ?? [] : proof?.evidence?.deliverables ?? [];
			const summary = picked ? String(picked.summary ?? "").trim() : String(proof?.summary ?? "").trim();
			const status = picked ? stateOf(picked) : proof?.status ?? null;
			const task = picked ?? proof?.task ?? null;
			const name = task ? nameOf(task) : "Esta sesión";

			if (!proof && !picked) return null;
			if (!picked && !media.length && !deliverables.length) return null;

			const counts = [
				media.length ? `${media.length} ${media.length === 1 ? "prueba visual" : "pruebas visuales"}` : null,
				deliverables.length ? `${deliverables.length} ${deliverables.length === 1 ? "entregable" : "entregables"}` : null,
				status,
			].filter(Boolean);

			const items = tasks.map((item) => ({
				id: item.id,
				label: h(
					"span",
					{ className: "evd-opt" },
					h("span", { className: "evd-opt-name", title: nameOf(item) }, nameOf(item)),
					h("span", { className: "evd-opt-state" }, stateOf(item)),
				),
			}));

			const picker = h(
				"button",
				{
					type: "button",
					className: "evd-pick",
					"aria-haspopup": "menu",
					"aria-expanded": menuOpen,
					title: tasks.length > 1 ? `Ver la evidencia de otra tarea · ${name}` : name,
					onClick: () => {
						if (tasks.length > 1) setMenuOpen((value) => !value);
					},
				},
				h("span", { className: "evd-pick-name" }, name),
				h(
					"span",
					{ className: "evd-caret" },
					h(
						"svg",
						{ width: 12, height: 12, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
						h("path", { d: "M5 6.5L8 9.5l3-3", stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round" }),
					),
				),
			);

			return h(
				"div",
				{ className: "evd-root" },
				h(
					"div",
					{ className: "evd-body" },
					h(
						"div",
						{ className: "evd-head" },
						h(
							"button",
							{ type: "button", className: "evd-toggle", "aria-expanded": open, onClick: () => setOpen((value) => !value) },
							h(
								"span",
								{ className: "evd-lead" },
								h(
									"svg",
									{ width: 16, height: 16, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
									h("rect", { x: 2, y: 2, width: 12, height: 12, rx: 3, stroke: "currentColor", strokeWidth: 1.3 }),
									h("path", { d: "M5 8.2l2 2 4-4.2", stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "round", strokeLinejoin: "round" }),
								),
							),
							h("span", { className: "evd-title" }, "Evidencia"),
							h(
								"span",
								{ className: "evd-chevron", "data-open": open },
								h(
									"svg",
									{ width: 14, height: 14, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
									h("path", { d: "M4.5 6.5L8 10l3.5-3.5", stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round" }),
								),
							),
						),
						tasks.length > 1 && Menu
							? h(Menu, {
									open: menuOpen,
									anchor: picker,
									items,
									selectedId,
									side: "top",
									align: "start",
									dense: true,
									portal: true,
									listClassName: "evd-menu",
									onSelect: (id) => {
										setPickedId(id);
										setMenuOpen(false);
										setOpen(true);
									},
									onClose: () => setMenuOpen(false),
								})
							: h("span", { className: "evd-task", title: name }, name),
						counts.length ? h("span", { className: "evd-progress" }, counts.join(" · ")) : null,
					),
					open
						? h(
								"div",
								{ className: "evd-panel" },
								summary ? h("p", { className: "evd-summary" }, summary) : null,
								media.length ? h(Gallery, { media, max: 4 }) : null,
								media.length > 4 ? h("p", { className: "evd-more" }, `+${media.length - 4} más en la pestaña Tareas`) : null,
								deliverables.length ? h(Deliverables, { items: deliverables.slice(0, 3) }) : null,
								!media.length && !deliverables.length ? h("p", { className: "evd-empty" }, "Este paso no dejó prueba visual todavía.") : null,
							)
						: null,
				),
			);
		}

		function apply(ctx) {
			ctx.slots.inject("conversation.input.dock", () =>
				ctx.slots.register({ name: "conversation.input.dock", id: "local-evidence", order: 40 }, EvidenceCard),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
