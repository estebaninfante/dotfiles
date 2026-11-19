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

		/** El título lo elige el agente; si no lo nombró, se dice. */
		function shortTitle(task) {
			const title = String(task?.title ?? "").trim();
			return title || "Tarea sin título";
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
								media.length > 4 ? h("p", { className: "evd-more" }, `+${media.length - 4} más en la pestaña Tareas`) : null,
								h(Deliverables, { items: deliverables.slice(0, 3) }),
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
