/**
 * dsh-local-evidence — client half.
 *
 * Tarjeta sobre el compositor, al final de la conversación, con la evidencia
 * real de lo que hizo el agente: archivos, comandos, tests y entregables. Sale
 * del log de la sesión (lo sirve /tasks/evidence), no de lo que el agente dice.
 * Copia el lenguaje de la tarjeta de To-dos del harness: mismo ancho, misma
 * elevación, mismo header colapsable.
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
		const POLL_MS = 6000;
		const CSS = [
			".evd-root{box-sizing:border-box;width:calc(100% - var(--dsh-composer-side-clearance,0px) - var(--dsh-composer-side-clearance,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px));max-width:calc(var(--dsh-composer-card-max-width,952px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px));border-radius:var(--dsw-radius-lg,16px);background:var(--dsw-specific-menu,#202226);box-shadow:var(--dsw-elevation-panel,0 10px 30px #0007);backdrop-filter:var(--dsw-menu-backdrop-filter,blur(20px));flex:none;margin:0 auto;overflow:hidden}",
			".evd-body{display:flex;flex-direction:column;padding:6px 12px}",
			".evd-head{display:flex;align-items:center;gap:10px;width:100%;padding:0;border:0;border-radius:6px;background:transparent;font:inherit;color:inherit;text-align:left;cursor:pointer}",
			".evd-head:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:2px}",
			".evd-lead{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-title{flex:none;font-size:13px;font-weight:500;line-height:24px;color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-progress{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:400;line-height:20px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-chevron{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3);transition:transform .18s ease}",
			".evd-chevron[data-open='true']{transform:rotate(180deg)}",
			".evd-panel{max-height:264px;overflow-y:auto;margin-top:6px;padding-top:8px;border-top:1px solid var(--dsw-alias-border-l1,#2c2f36);--dsh-scrollbar-thumb:var(--dsw-alias-scrollbar-bg-l2)}",
			".evd-group{margin:0 0 10px}",
			".evd-group:last-child{margin-bottom:2px}",
			".evd-group-h{margin:0 0 3px;font-size:12px;font-weight:500;line-height:18px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-item{display:flex;align-items:baseline;gap:6px;margin:0;font-size:12.5px;line-height:19px;color:var(--dsw-alias-label-secondary,#b9b9c2)}",
			".evd-flag{flex:none;font-weight:500;color:var(--dsw-alias-label-primary,#e9e9ee)}",
			".evd-code{min-width:0;font-family:ui-monospace,SFMono-Regular,monospace;font-size:11.5px;overflow-wrap:anywhere}",
			".evd-decl{margin:0;font-size:12.5px;line-height:1.55;color:var(--dsw-alias-label-secondary,#b9b9c2);white-space:pre-wrap}",
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

		function short(text, max) {
			const value = String(text ?? "").replace(/\s+/g, " ").trim();
			return value.length > max ? `${value.slice(0, max - 1)}…` : value;
		}

		function outcome(code) {
			if (code === null || code === undefined) return "falló";
			return code === 0 ? "ok" : `salió ${code}`;
		}

		function useEvidence(sessionId) {
			const [evidence, setEvidence] = useState(null);
			useEffect(() => {
				if (!sessionId) return undefined;
				let cancelled = false;
				const load = () => {
					fetch(`/tasks/evidence?session=${encodeURIComponent(sessionId)}`, { headers: { accept: "application/json" } })
						.then((response) => (response.ok ? response.json() : null))
						.then((payload) => {
							if (!cancelled && payload) setEvidence(payload.evidence ?? null);
						})
						.catch(() => {});
				};
				load();
				const timer = setInterval(load, POLL_MS);
				return () => {
					cancelled = true;
					clearInterval(timer);
				};
			}, [sessionId]);
			return evidence;
		}

		function Group(props) {
			if (!props.items.length) return null;
			return h(
				"div",
				{ className: "evd-group" },
				h("p", { className: "evd-group-h" }, props.title),
				props.items.map((item, index) =>
					h("p", { className: "evd-item", key: index }, h("span", { className: "evd-flag" }, item.flag), h("code", { className: "evd-code" }, item.code)),
				),
			);
		}

		function EvidencePanel(props) {
			const { evidence } = props;
			return h(
				"div",
				{ className: "evd-panel" },
				h(Group, { title: `Archivos · ${evidence.files.length}`, items: evidence.files.slice(0, 16).map((file) => ({ flag: file.action, code: file.path })) }),
				h(Group, {
					title: `Comandos · ${evidence.commands.length}`,
					items: evidence.commands
						.slice(-10)
						.reverse()
						.map((command) => ({ flag: outcome(command.exitCode), code: short(command.command, 110) })),
				}),
				h(Group, {
					title: `Fallos · ${evidence.failures.length}`,
					items: evidence.failures.slice(0, 8).map((failure) => ({ flag: failure.kind, code: short(failure.detail, 130) })),
				}),
				h(Group, {
					title: `Entregables · ${evidence.deliverables.length}`,
					items: evidence.deliverables.map((file) => ({ flag: "presentó", code: `${file.path}${file.description ? ` — ${file.description}` : ""}` })),
				}),
				h(Group, {
					title: "Lo que dijo el agente",
					items: evidence.claims.map((claim) => ({ flag: claim.verified ? "verificado" : "sin verificar", code: `${claim.claim} — ${claim.note}` })),
				}),
				evidence.declaration ? h("p", { className: "evd-decl" }, evidence.declaration.text) : null,
			);
		}

		function EvidenceCard(props) {
			useStyles();
			const sessionId = props.sessionId;
			const running = props.useSession((state) => state.running);
			const evidence = useEvidence(sessionId);
			const [open, setOpen] = useState(false);
			if (!evidence) return null;
			const { stats } = evidence;
			if (!stats.files && !stats.commands && !stats.deliverables) return null;
			const summary = [
				`${stats.files} ${stats.files === 1 ? "archivo" : "archivos"}`,
				`${stats.commands} ${stats.commands === 1 ? "comando" : "comandos"}`,
				stats.testsOk || stats.testsFail ? `tests ${stats.testsOk} ok${stats.testsFail ? ` · ${stats.testsFail} fallaron` : ""}` : null,
				stats.failures ? `${stats.failures} ${stats.failures === 1 ? "fallo" : "fallos"}` : null,
				running ? "en curso" : evidence.end ? (evidence.end.reason === "completed" ? "cerró bien" : `cerró: ${evidence.end.reason}`) : null,
			]
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
					open ? h(EvidencePanel, { evidence }) : null,
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
