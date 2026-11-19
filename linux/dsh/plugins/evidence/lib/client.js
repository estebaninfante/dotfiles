/**
 * dsh-local-evidence — client half.
 *
 * Tarjeta sobre el compositor, SOLO cuando el pedido terminó y dejó prueba:
 * capturas y videos que el agente miró, capturó o entregó en ese turno, más los
 * entregables. Nada de comandos ni proceso: eso ya está en Chat y Trajectory.
 * Dice a qué tarea del proyecto corresponde y cómo cerró.
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
			".evd-chevron{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3);transition:transform .18s ease}",
			".evd-chevron[data-open='true']{transform:rotate(180deg)}",
			".evd-panel{max-height:300px;overflow-y:auto;margin-top:6px;padding-top:8px;border-top:1px solid var(--dsw-alias-border-l1,#2c2f36);--dsh-scrollbar-thumb:var(--dsw-alias-scrollbar-bg-l2)}",
			".evd-gallery{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 10px}",
			".evd-thumb{display:block;width:132px;height:82px;border-radius:6px;overflow:hidden;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:var(--dsw-alias-bg-layer-3,#2a2d35);cursor:zoom-in}",
			".evd-thumb img{width:100%;height:100%;object-fit:cover;display:block}",
			".evd-thumb:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".evd-video{width:212px;height:120px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:#000}",
			".evd-group-h{margin:0 0 4px;font-size:12px;font-weight:500;line-height:18px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-item{display:flex;align-items:baseline;gap:6px;margin:0;font:400 12px/1.6 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-secondary,#b9b9c2);overflow-wrap:anywhere}",
			".evd-item a{color:var(--dsw-alias-label-primary,#e9e9ee);text-decoration:none;border-bottom:1px solid var(--dsw-alias-border-l2,#3b3e46)}",
			".evd-item a:hover{border-bottom-color:currentColor}",
			"@media (prefers-reduced-motion:reduce){.evd-chevron{transition:none}}",
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

		/** Solo se pide cuando el turno ya terminó: mientras corre no hay evidencia. */
		function useTurnEvidence(sessionId, running) {
			const [turn, setTurn] = useState(null);
			useEffect(() => {
				if (!sessionId || running) {
					setTurn(null);
					return undefined;
				}
				let cancelled = false;
				const load = () => {
					fetch(`/tasks/turn?session=${encodeURIComponent(sessionId)}`, { headers: { accept: "application/json" } })
						.then((response) => (response.ok ? response.json() : null))
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
			}, [sessionId, running]);
			return turn;
		}

		function Gallery(props) {
			const media = props.media;
			return h(
				"div",
				{ className: "evd-gallery" },
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

		function Panel(props) {
			const { proof } = props;
			return h(
				"div",
				{ className: "evd-panel" },
				proof.evidence.media.length ? h(Gallery, { media: proof.evidence.media }) : null,
				proof.evidence.deliverables.length
					? h(
							"div",
							null,
							h("p", { className: "evd-group-h" }, `Entregables · ${proof.evidence.deliverables.length}`),
							proof.evidence.deliverables.map((file) =>
								h("p", { className: "evd-item", key: file.path }, h("a", { href: fileUrl(file.path), target: "_blank", rel: "noreferrer" }, file.label ?? file.path), file.description ? ` — ${file.description}` : ""),
							),
						)
					: null,
			);
		}

		function EvidenceCard(props) {
			useStyles();
			const sessionId = props.sessionId;
			const running = props.useSession((state) => state.running);
			const proof = useTurnEvidence(sessionId, running);
			const [open, setOpen] = useState(false);
			if (!proof || proof.running) return null;
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
						proof.task ? h("span", { className: "evd-task", title: proof.task.title }, proof.task.title) : null,
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
					open ? h(Panel, { proof }) : null,
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
