/**
 * dsh-local-evidence — client half.
 *
 * Dos piezas, las dos con evidencia real del log de la sesión:
 *   - Tarjeta sobre el compositor: la prueba visual del último pedido terminado,
 *     con un resumen corto de lo que hizo el agente.
 *   - Vista "Evidencia" al lado de Chat y Tareas: todas las tareas de la sesión,
 *     cada una con su resumen, sus capturas y sus entregables.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-evidence",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;
		const { useEffect, useState } = React;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const STYLE_ID = "dsh-local-evidence-style";
		const CSS = [
			".evd-root{box-sizing:border-box;width:calc(100% - var(--dsh-composer-side-clearance,0px) - var(--dsh-composer-side-clearance,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px));max-width:calc(var(--dsh-composer-card-max-width,952px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px));border-radius:var(--dsw-radius-lg,16px);background:var(--dsw-specific-menu,#202226);box-shadow:var(--dsw-elevation-panel,0 10px 30px #0007);backdrop-filter:var(--dsw-menu-backdrop-filter,blur(20px));flex:none;margin:0 auto;overflow:hidden}",
			".evd-body{display:flex;flex-direction:column;padding:6px 12px}",
			".evd-head{display:flex;align-items:center;gap:10px;width:100%;padding:0;border:0;border-radius:6px;background:transparent;font:inherit;color:inherit;text-align:left;cursor:pointer}",
			".evd-head:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:2px}",
			".evd-lead{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-title{flex:none;font-size:13px;font-weight:500;line-height:24px;color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-task{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:400;line-height:20px;color:var(--dsw-alias-label-secondary,#b9b9c2)}",
			".evd-progress{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12px;font-weight:400;line-height:20px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-chevron{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3);transition:transform .18s ease}.evd-chevron[data-open='true']{transform:rotate(180deg)}",
			".evd-panel{max-height:320px;overflow-y:auto;margin-top:6px;padding-top:8px;border-top:1px solid var(--dsw-alias-border-l1,#2c2f36);--dsh-scrollbar-thumb:var(--dsw-alias-scrollbar-bg-l2)}",
			".evd-summary{margin:0 0 8px;font-size:12.5px;line-height:1.55;color:var(--dsw-alias-label-secondary,#b9b9c2);display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}",
			".evd-more{margin:6px 0 0;font:400 12px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-gallery{display:flex;flex-wrap:wrap;gap:6px}.evd-thumb{display:block;width:132px;height:82px;border-radius:6px;overflow:hidden;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:var(--dsw-alias-bg-layer-1,#16181c);cursor:zoom-in}.evd-thumb img{width:100%;height:100%;object-fit:cover;display:block}",
			".evd-thumb:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}.evd-video{width:212px;height:120px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:#000}",
			".evd-group-h{margin:10px 0 4px;font-size:12px;font-weight:500;line-height:18px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-item{display:flex;align-items:baseline;gap:6px;margin:0;font:400 12px/1.6 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-secondary,#b9b9c2);overflow-wrap:anywhere}",
			".evd-item a{color:var(--dsw-alias-label-primary,#e9e9ee);text-decoration:none;border-bottom:1px solid var(--dsw-alias-border-l2,#3b3e46)}",
			".evs-root{height:100%;overflow:auto;box-sizing:border-box}",
			".evs-wrap{max-width:820px;margin:0 auto;padding:30px 32px 80px}",
			".evs-h1{margin:0;font-size:18px;font-weight:550;letter-spacing:-.01em;color:var(--dsw-alias-label-primary,#ececf1)}",
			".evs-line{margin:6px 0 0;font:400 12px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evs-item{padding:14px 2px;border-bottom:1px solid var(--dsw-alias-border-l1,#2c2f36)}.evs-item:first-of-type{border-top:1px solid var(--dsw-alias-border-l1,#2c2f36)}",
			".evs-row{display:flex;align-items:baseline;gap:14px;justify-content:space-between}",
			".evs-title{margin:0;font-size:13.5px;font-weight:500;line-height:1.45;color:var(--dsw-alias-label-primary,#ececf1);overflow-wrap:anywhere}",
			".evs-status{flex:none;font:400 11px/1.4 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap}",
			".evs-summary{margin:3px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-secondary,#b9b9c2);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}",
			".evs-note{margin:12px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			"@media (max-width:640px){.evs-wrap{padding:20px 18px 88px}.evs-row{flex-direction:column;gap:2px}}",
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

		/** Título con nombre; si quedó el pedido crudo (tareas viejas), turno. */
		function shortTitle(task) {
			const title = String(task?.title ?? "").trim();
			if (title && title.length <= 64) return title;
			return task?.turn ? `Pedido del turno ${task.turn}` : "Pedido sin nombre";
		}

		/** Estados: solo se muestran tal cual vienen del host. */
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
								{ key: item.path, className: "evd-thumb", href: item.url, target: "_blank", rel: "noreferrer", title: item.path },
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
						"p",
						{ className: "evd-item", key: file.path },
						h("a", { href: fileUrl(file.path), target: "_blank", rel: "noreferrer" }, file.label ?? file.path),
						file.description ? ` — ${file.description}` : "",
					),
				),
			);
		}

		/** Solo se pide cuando la sesión cambia; la tarjeta se actualiza cada 15s. */
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

		function useSessionEvidence(sessionId) {
			const [data, setData] = useState(null);
			useEffect(() => {
				if (!sessionId) {
					setData(null);
					return undefined;
				}
				let cancelled = false;
				const load = () => {
					getJson(`/tasks/session?session=${encodeURIComponent(sessionId)}`)
						.then((payload) => {
							if (!cancelled) setData(payload);
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
			return data;
		}

		function EvidenceCard(props) {
			useStyles();
			const proof = useTurnEvidence(props.sessionId);
			const [open, setOpen] = useState(false);
			if (!proof) return null;
			const evidence = proof.evidence;
			const media = evidence.media ?? [];
			const deliverables = evidence.deliverables ?? [];
			if (!media.length && !deliverables.length) return null;
			const summary = [`${media.length} ${media.length === 1 ? "prueba visual" : "pruebas visuales"}`, deliverables.length ? `${deliverables.length} ${deliverables.length === 1 ? "entregable" : "entregables"}` : null, proof.status]
				.filter(Boolean)
				.join(" · ");
			return h(
				"div",
				{ className: "evd-root" },
				h(
					"div",
					{ className: "evd-body" },
					h(
						"button",
						{ type: "button", className: "evd-head", "aria-expanded": open, onClick: () => setOpen((value) => !value) },
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
						proof.task ? h("span", { className: "evd-task", title: proof.task.title }, shortTitle(proof.task)) : null,
						h("span", { className: "evd-progress" }, summary),
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
					open
						? h(
								"div",
								{ className: "evd-panel" },
								proof.summary ? h("p", { className: "evd-summary" }, proof.summary) : null,
								h(Gallery, { media, max: 4 }),
								media.length > 4 ? h("p", { className: "evd-more" }, `+${media.length - 4} más en la pestaña Evidencia`) : null,
								h(Deliverables, { items: deliverables.slice(0, 3) }),
							)
						: null,
				),
			);
		}

		function EvidenceView(props) {
			useStyles();
			const data = useSessionEvidence(props.sessionId);
			if (!data) return h("div", { className: "evs-root" });
			const stats = data.stats ?? { tasks: 0, media: 0, deliverables: 0 };
			const statsLine = [
				`${stats.tasks} ${stats.tasks === 1 ? "pedido" : "pedidos"}`,
				stats.media ? `${stats.media} ${stats.media === 1 ? "prueba visual" : "pruebas visuales"}` : null,
				stats.deliverables ? `${stats.deliverables} ${stats.deliverables === 1 ? "entregable" : "entregables"}` : null,
			]
				.filter(Boolean)
				.join(" · ");
			return h(
				"div",
				{ className: "evs-root" },
				h(
					"div",
					{ className: "evs-wrap" },
					h("h1", { className: "evs-h1" }, "Evidencia"),
					h("p", { className: "evs-line" }, statsLine),
					!data.tasks.length ? h("p", { className: "evs-note" }, "Todavía no hay evidencia registrada en esta conversación. Cada pedido deja acá su resumen y su prueba visual.") : null,
					data.tasks.map((task) =>
						h(
							"section",
							{ className: "evs-item", key: task.id },
							h(
								"div",
								{ className: "evs-row" },
								h("h2", { className: "evs-title", title: task.title }, shortTitle(task)),
								h("span", { className: "evs-status" }, task.status),
							),
							task.summary ? h("p", { className: "evs-summary" }, task.summary) : null,
							task.media.length ? h(Gallery, { media: task.media, max: 8 }) : null,
							h(Deliverables, { items: task.deliverables }),
						),
					),
				),
			);
		}

		function apply(ctx) {
			ctx.slots.inject("conversation.input.dock", () =>
				ctx.slots.register({ name: "conversation.input.dock", id: "local-evidence", order: 40 }, EvidenceCard),
			);
			ctx.slots.inject("conversation.view", () =>
				ctx.slots.register({ name: "conversation.view", id: "evidence", order: 30, label: () => "Evidencia" }, EvidenceView),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
