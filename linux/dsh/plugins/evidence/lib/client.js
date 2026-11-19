/**
 * dsh-local-evidence — client half.
 *
 * Una línea sobre el compositor, al final de la conversación, con la evidencia
 * real de lo que hizo el agente: archivos, comandos, tests y entregables. Sale
 * del log de la sesión (lo sirve /tasks/evidence), no de lo que el agente dice.
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
			".evd-root{padding:2px 0 6px}",
			".evd-line{display:flex;align-items:center;gap:10px;min-height:22px}",
			".evd-label{font:500 11px/1.4 ui-monospace,SFMono-Regular,monospace;letter-spacing:.05em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap}",
			".evd-summary{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:400 11.5px/1.4 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-secondary,#b9b9c2)}",
			".evd-btn{box-sizing:border-box;height:22px;padding:0 8px;margin-left:auto;border:1px solid transparent;border-radius:6px;background:transparent;color:var(--dsw-alias-label-tertiary,#9a9aa3);font:inherit;font-size:11px;line-height:1;cursor:pointer}",
			".evd-btn:hover{background:var(--dsw-alias-bg-layer-3,#2a2d35);color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-btn:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".evd-body{margin:6px 0 0;padding:10px 12px;max-height:270px;overflow:auto;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:8px;background:var(--dsw-alias-bg-layer-2,#1d2027)}",
			".evd-group{margin:0 0 8px}",
			".evd-group:last-child{margin-bottom:0}",
			".evd-group-h{margin:0 0 4px;font:500 10.5px/1.3 ui-monospace,SFMono-Regular,monospace;letter-spacing:.07em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-item{margin:0;padding:1px 0;font:400 11.5px/1.5 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-secondary,#b9b9c2);overflow-wrap:anywhere}",
			".evd-item b{font-weight:500;color:var(--dsw-alias-label-primary,#e9e9ee)}",
			".evd-decl{margin:0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-secondary,#b9b9c2);white-space:pre-wrap}",
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
				props.items.map((item, index) => h("p", { className: "evd-item", key: index }, item)),
			);
		}

		function EvidenceBody(props) {
			const { evidence } = props;
			return h(
				"div",
				{ className: "evd-body" },
				h(Group, {
					title: `Archivos · ${evidence.files.length}`,
					items: evidence.files.slice(0, 16).map((file) => [h("b", { key: "k" }, file.action), ` ${file.path}`]),
				}),
				h(Group, {
					title: `Comandos · ${evidence.commands.length}`,
					items: evidence.commands.slice(-10).reverse().map((command) => [h("b", { key: "k" }, outcome(command.exitCode)), ` ${short(command.command, 110)}`]),
				}),
				h(Group, {
					title: `Fallos · ${evidence.failures.length}`,
					items: evidence.failures.slice(0, 8).map((failure) => [h("b", { key: "k" }, failure.kind), ` ${short(failure.detail, 130)}`]),
				}),
				h(Group, {
					title: `Entregables · ${evidence.deliverables.length}`,
					items: evidence.deliverables.map((file) => [h("b", { key: "k" }, "presentó"), ` ${file.path}${file.description ? ` — ${file.description}` : ""}`]),
				}),
				h(Group, {
					title: "Lo que dijo el agente",
					items: evidence.claims.map((claim) => [h("b", { key: "k" }, claim.verified ? "verificado" : "sin verificar"), ` ${claim.claim} — ${claim.note}`]),
				}),
				evidence.declaration ? h("p", { className: "evd-decl" }, evidence.declaration.text) : null,
			);
		}

		function EvidenceStrip(props) {
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
				evidence.end ? (evidence.end.reason === "completed" ? "cerró bien" : `cerró: ${evidence.end.reason}`) : null,
			]
				.filter(Boolean)
				.join(" · ");
			return h(
				"div",
				{ className: "evd-root" },
				h(
					"div",
					{ className: "evd-line" },
					h("span", { className: "evd-label" }, running ? "Evidencia en curso" : "Evidencia"),
					h("span", { className: "evd-summary" }, summary),
					h("button", { type: "button", className: "evd-btn", onClick: () => setOpen((value) => !value) }, open ? "Ocultar" : "Ver"),
				),
				open ? h(EvidenceBody, { evidence }) : null,
			);
		}

		function apply(ctx) {
			ctx.slots.inject("conversation.input.dock", () =>
				ctx.slots.register({ name: "conversation.input.dock", id: "local-evidence", order: 40 }, EvidenceStrip),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
