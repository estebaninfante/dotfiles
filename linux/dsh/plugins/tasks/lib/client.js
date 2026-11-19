/**
 * dsh-local-tasks — client half.
 *
 * La pestaña "Tareas" de la conversación: los pedidos de esta sesión con su
 * estado (abierta, en curso, ok, falló, resuelta), un resumen corto de lo que
 * hizo el agente y su prueba visual. Los datos salen de /tasks/session; la
 * tarjeta flotante del final la pone dsh-local-evidence.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-tasks",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;
		const { useEffect, useState } = React;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const STYLE_ID = "dsh-local-tasks-style";
		const CSS = [
			".tsk-root{height:100%;overflow:auto;box-sizing:border-box}",
			".tsk-wrap{max-width:820px;margin:0 auto;padding:30px 32px 80px}",
			".tsk-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding-bottom:12px}",
			".tsk-h1{margin:0;font-size:18px;font-weight:550;letter-spacing:-.01em;color:var(--dsw-alias-label-primary,#ececf1)}",
			".tsk-path{margin:4px 0 0;padding:0;border:0;background:transparent;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:400 12px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3);cursor:pointer;text-align:left}",
			".tsk-path:hover{color:var(--dsw-alias-label-secondary,#b9b9c2)}.tsk-path:focus-visible,.tsk-btn:focus-visible,.tsk-input:focus-visible,.tsk-icon:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".tsk-btn{box-sizing:border-box;height:26px;padding:0 10px;display:inline-flex;align-items:center;justify-content:center;border:1px solid transparent;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);font:inherit;font-size:12px;line-height:1;cursor:pointer;white-space:nowrap}",
			".tsk-btn:hover{color:var(--dsw-alias-label-primary,#ececf1);border-color:var(--dsw-alias-border-l2,#3b3e46)}.tsk-btn[disabled]{opacity:.5;cursor:default}.tsk-btn--primary{border-color:transparent;background:var(--dsw-alias-state-business-primary,#6ea8fe);color:#0e1116;font-weight:600}",
			".tsk-line{margin:4px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-list{display:flex;flex-direction:column;gap:8px;padding-top:10px}",
			".tsk-card{display:flex;flex-direction:column;gap:6px;padding:13px 15px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:12px;background:var(--dsw-alias-bg-layer-2,#1d2027);transition:border-color .12s ease}.tsk-card:hover{border-color:var(--dsw-alias-border-l2,#3b3e46)}",
			".tsk-row{display:flex;align-items:center;gap:14px;justify-content:space-between}",
			".tsk-title{margin:0;font-size:13.5px;font-weight:500;line-height:1.45;color:var(--dsw-alias-label-primary,#ececf1);overflow-wrap:anywhere}",
			".tsk-side{display:flex;align-items:center;gap:2px;flex:none}",
			".tsk-state{font-size:11.5px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap;margin-right:6px}.tsk-state[data-tone='bad']{color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".tsk-summary{margin:0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-secondary,#b9b9c2);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}",
			".tsk-gallery{display:flex;flex-wrap:wrap;gap:6px;margin:2px 0 0}.tsk-thumb{display:block;width:118px;height:74px;border-radius:6px;overflow:hidden;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:var(--dsw-alias-bg-layer-1,#16181c)}.tsk-thumb img{width:100%;height:100%;object-fit:cover;display:block}.tsk-thumb:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".tsk-video{width:198px;height:112px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:#000}",
			".tsk-icon{width:28px;height:28px;border:0;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);display:grid;place-items:center;cursor:pointer}.tsk-icon:hover{color:var(--dsw-alias-label-primary,#ececf1)}.tsk-icon[disabled]{opacity:.45;cursor:default}",
			".tsk-deliv{margin:2px 0 0;font-size:12px;line-height:1.6;color:var(--dsw-alias-label-secondary,#b9b9c2);overflow-wrap:anywhere}.tsk-deliv a{color:var(--dsw-alias-label-primary,#e9e9ee);text-decoration:none;border-bottom:1px solid var(--dsw-alias-border-l2,#3b3e46)}",
			".tsk-form{margin:6px 0 8px;padding:14px 0 16px;border-top:1px solid var(--dsw-alias-border-l1,#2c2f36)}",
			".tsk-input{box-sizing:border-box;width:100%;margin:0 0 10px;padding:7px 9px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-primary,#ececf1);font:inherit;font-size:13px}",
			".tsk-note{margin:12px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}.tsk-error{margin:10px 0 0;font-size:12px;color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			"@media (max-width:640px){.tsk-wrap{padding:20px 18px 88px}.tsk-head{flex-direction:column;gap:10px}.tsk-row{flex-direction:column;align-items:flex-start;gap:4px}}",
		].join("\n");

		async function api(path, body) {
			const init = body
				? { method: "POST", headers: { "content-type": "application/json", "x-dsh-tasks": "1", accept: "application/json" }, body: JSON.stringify(body) }
				: { headers: { accept: "application/json" } };
			const response = await fetch(`/tasks${path}`, init);
			const payload = await response.json().catch(() => ({}));
			if (response.status === 404) throw new Error("El servidor todavía no tiene las tareas cargadas. Reiniciá el harness: dsh-web --restart.");
			if (!response.ok) throw new Error(payload?.message || payload?.error || `HTTP ${response.status}`);
			return payload;
		}

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

		function statusOf(task) {
			if (task.state === "resuelta") return { text: "resuelta", bad: false };
			if (task.outcome === "falló") return { text: "falló", bad: true };
			if (task.outcome === "parcial") return { text: "parcial", bad: false };
			if (task.outcome === "ok") return { text: "ok", bad: false };
			if (task.outcome === "abierta") return { text: "abierta", bad: false };
			if (task.closeReason) return { text: "sin revisar", bad: false };
			return { text: task.status ?? task.state ?? "abierta", bad: false };
		}

		function Gallery(props) {
			return h(
				"div",
				{ className: "tsk-gallery" },
				(props.items ?? []).slice(0, props.max ?? 8).map((item) =>
					item.kind === "video"
						? h("video", { key: item.path, className: "tsk-video", controls: true, preload: "metadata", src: item.url })
						: h(
								"a",
								{ key: item.path, className: "tsk-thumb", href: item.url, target: "_blank", rel: "noreferrer", title: item.path },
								h("img", { src: item.url, alt: item.label, loading: "lazy" }),
							),
				),
			);
		}

		function Deliverables(props) {
			return h(
				React.Fragment,
				null,
				(props.items ?? []).map((file) =>
					h(
						"p",
						{ className: "tsk-deliv", key: file.path },
						h("a", { href: `/api/file?path=${encodeURIComponent(file.path)}`, target: "_blank", rel: "noreferrer" }, file.label ?? file.path),
						file.description ? ` — ${file.description}` : "",
					),
				),
			);
		}

		function Action(props) {
			return h(
				"button",
				{ type: "button", className: "tsk-icon", title: props.label, "aria-label": props.label, onClick: props.onClick, disabled: props.disabled },
				h(
					"svg",
					{ width: 15, height: 15, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
					h("path", {
						d: props.icon === "check" ? "M3.5 8.2l3 3 6-6.4" : "M4 8a4 4 0 1 0 1.2-2.9M4 3.2v2.6h2.6",
						stroke: "currentColor",
						strokeWidth: 1.4,
						strokeLinecap: "round",
						strokeLinejoin: "round",
					}),
				),
			);
		}

		function TaskCard(props) {
			const { task, onChange, busy } = props;
			const status = statusOf(task);
			return h(
				"div",
				{ className: "tsk-card" },
				h(
					"div",
					{ className: "tsk-row" },
					h("p", { className: "tsk-title", title: task.title }, task.title),
					h(
						"div",
						{ className: "tsk-side" },
						h("span", { className: "tsk-state", "data-tone": status.bad ? "bad" : undefined }, status.text),
						task.state === "abierta"
							? h(Action, { icon: "check", label: "Resolver tarea", onClick: () => onChange(task, "resuelta"), disabled: busy })
							: h(Action, { icon: "undo", label: "Reabrir tarea", onClick: () => onChange(task, "abierta"), disabled: busy }),
					),
				),
				task.summary ? h("p", { className: "tsk-summary" }, task.summary) : null,
				task.note ? h("p", { className: "tsk-note" }, task.note) : null,
				task.media?.length ? h(Gallery, { items: task.media }) : null,
				h(Deliverables, { items: task.deliverables ?? [] }),
			);
		}

		function TasksView(props) {
			useStyles();
			const { sessionId, getCwd, openFolder, createConversation, navigate } = props;
			const [data, setData] = useState(null);
			const [error, setError] = useState(null);
			const [busy, setBusy] = useState(false);
			const [formOpen, setFormOpen] = useState(false);
			const [draft, setDraft] = useState("");

			const load = React.useCallback(async () => {
				try {
					setData(await api(`/session?session=${encodeURIComponent(sessionId)}`));
					setError(null);
				} catch (cause) {
					setError(cause);
				}
			}, [sessionId]);

			useEffect(() => {
				load();
				const timer = setInterval(load, 8000);
				return () => clearInterval(timer);
			}, [load]);

			const cwd = data?.workspace ?? (sessionId ? getCwd(sessionId) : "");
			const tasks = data?.tasks ?? [];
			const abiertas = tasks.filter((task) => task.state === "abierta" && task.outcome !== "ok").length;
			const fallos = tasks.filter((task) => task.outcome === "falló").length;
			const cerradas = tasks.filter((task) => task.state === "resuelta" || task.outcome === "ok").length;

			const change = async (task, state) => {
				setBusy(true);
				try {
					await api("/update", { id: task.id, state });
					await load();
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const create = async () => {
				if (!cwd || !draft.trim()) return;
				setBusy(true);
				try {
					const created = await api("/create", { workspace: cwd, title: draft });
					setDraft("");
					setFormOpen(false);
					navigate(await createConversation(created.task, cwd));
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const backfill = async () => {
				if (!sessionId) return;
				setBusy(true);
				try {
					await api("/backfill", { session: sessionId });
					await load();
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			return h(
				"div",
				{ className: "tsk-root" },
				h(
					"div",
					{ className: "tsk-wrap" },
					h(
						"div",
						{ className: "tsk-head" },
						h(
							"div",
							{ style: { minWidth: 0 } },
							h("h1", { className: "tsk-h1" }, "Tareas"),
							cwd ? h("button", { type: "button", className: "tsk-path", title: `Abrir ${cwd}`, onClick: () => openFolder(cwd) }, cwd) : null,
							h("p", { className: "tsk-line" }, `${abiertas} abiertas · ${fallos} con fallos · ${cerradas} cerradas`),
						),
						cwd ? h("button", { type: "button", className: "tsk-btn tsk-btn--primary", onClick: () => setFormOpen((open) => !open) }, "Nueva tarea") : null,
					),
					cwd && formOpen
						? h(
								"div",
								{ className: "tsk-form" },
								h("input", {
									className: "tsk-input",
									value: draft,
									autoFocus: true,
									placeholder: "Qué hay que resolver",
									onChange: (event) => setDraft(event.target.value),
									onKeyDown: (event) => {
										if (event.key === "Enter") create();
									},
								}),
								h("div", { style: { display: "flex", gap: 8 } },
									h("button", { type: "button", className: "tsk-btn tsk-btn--primary", onClick: create, disabled: busy || !draft.trim() }, "Crear y abrir"),
									h("button", { type: "button", className: "tsk-btn", onClick: () => { setFormOpen(false); setDraft(""); } }, "Cancelar"),
								),
							)
						: null,
					error ? h("p", { className: "tsk-error" }, error.message) : null,
					tasks.length ? h("div", { className: "tsk-list" }, tasks.map((task) => h(TaskCard, { key: task.id, task, onChange: change, busy }))) : null,
					!tasks.length && data ? h("p", { className: "tsk-note" }, "Todavía no hay tareas en esta conversación. Los pedidos nuevos se registran solos.") : null,
					!tasks.length && data && sessionId ? h("button", { type: "button", className: "tsk-btn", style: { marginTop: 10 }, onClick: backfill, disabled: busy }, "Traer los pedidos de esta conversación") : null,
				),
			);
		}

		function apply(ctx) {
			const get = (name) => (typeof ctx.get === "function" ? ctx.get(name) : ctx[name]);
			const getCwd = (sessionId) => {
				try {
					return get("sessions")?.list?.getSnapshot()?.byId?.[sessionId]?.cwd ?? "";
				} catch {
					return "";
				}
			};
			const openFolder = (path) => api("/open", { path }).catch(() => {});
			const navigate = (sessionId) => {
				const uiWorkspace = get("uiWorkspace");
				if (uiWorkspace && typeof uiWorkspace.openSession === "function") uiWorkspace.openSession(sessionId);
			};
			const createConversation = async (task, cwd) => {
				const sessions = get("sessions");
				if (!sessions || typeof sessions.create !== "function") throw new Error("el harness no expone `sessions`");
				const created = await sessions.create(cwd ? { cwd } : {});
				if (!created || created.ok !== true) throw new Error(created?.error?.message || "no se pudo crear la sesión");
				const sessionId = created.value.sessionId;
				await api("/update", { id: task.id, sessionId, state: "abierta" }).catch(() => {});
				const text = `Tarea del proyecto: ${task.title}\nCarpeta: ${cwd}\n\nAl terminar, cerrá con la prueba visual real: captura de la app o video, rutas de archivos y resultado de los tests. Sin captura no hay evidencia visible.`;
				await sessions.using(sessionId, { source: "gateway" }, async (reference) => {
					await reference.ready;
					await reference.binding.session.prompt([{ type: "text", text }], "queue");
				});
				return sessionId;
			};
			ctx.slots.inject("conversation.view", () =>
				ctx.slots.register(
					{ name: "conversation.view", id: "tasks", order: 30, label: () => "Tareas", inject: () => ({ getCwd, openFolder, createConversation, navigate }) },
					TasksView,
				),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
