/**
 * dsh-local-tasks — client half.
 *
 * Vista "Tareas" al lado de Chat y Trajectory: las tareas de esta carpeta,
 * anotadas antes de arrancar la conversación. Y la carpeta actual en el header,
 * clickeable para abrirla en el gestor. La evidencia de cada conversación vive
 * en el plugin `dsh-local-evidence`, sobre el compositor.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-tasks",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;
		const { useCallback, useEffect, useState } = React;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const STYLE_ID = "dsh-local-tasks-style";
		const CSS = [
			".tsk-root{height:100%;overflow:auto;box-sizing:border-box}",
			".tsk-wrap{max-width:820px;margin:0 auto;padding:30px 32px 80px}",
			".tsk-head{display:flex;align-items:flex-start;gap:16px;justify-content:space-between;padding-bottom:14px}",
			".tsk-eyebrow{margin:0 0 7px;font:500 11px/1.2 ui-monospace,SFMono-Regular,monospace;letter-spacing:.08em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-h1{margin:0;font-size:18px;font-weight:550;letter-spacing:-.01em;color:var(--dsw-alias-label-primary,#ececf1)}",
			".tsk-path{margin:5px 0 0;padding:0;border:0;background:transparent;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:400 12px/1.5 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-secondary,#b9b9c2);cursor:pointer;text-align:left}",
			".tsk-path:hover{color:var(--dsw-alias-label-primary,#ececf1)}",
			".tsk-path:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:2px}",
			".tsk-actions{display:flex;align-items:center;gap:8px;flex-wrap:wrap}",
			".tsk-btn{box-sizing:border-box;height:28px;padding:0 11px;display:inline-flex;align-items:center;justify-content:center;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:transparent;color:var(--dsw-alias-label-primary,#e9e9ee);font:inherit;font-size:12px;line-height:1;cursor:pointer}",
			".tsk-btn:hover{background:var(--dsw-alias-bg-layer-3,#2a2d35)}",
			".tsk-btn:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".tsk-btn[disabled]{opacity:.5;cursor:default}",
			".tsk-btn--quiet{border-color:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2)}",
			".tsk-btn--primary{border-color:transparent;background:var(--dsw-alias-state-business-primary,#6ea8fe);color:#0e1116;font-weight:600}",
			".tsk-section{display:flex;align-items:baseline;gap:8px;margin:24px 0 4px;font:500 11px/1.2 ui-monospace,SFMono-Regular,monospace;letter-spacing:.07em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-list{border-top:1px solid var(--dsw-alias-border-l1,#2c2f36)}",
			".tsk-row{display:flex;align-items:flex-start;gap:12px;padding:12px 2px;border-bottom:1px solid var(--dsw-alias-border-l1,#2c2f36)}",
			".tsk-rowmain{flex:1 1 auto;min-width:0}",
			".tsk-title{margin:0;font-size:13.5px;font-weight:500;color:var(--dsw-alias-label-primary,#ececf1);overflow-wrap:anywhere}",
			".tsk-goal{margin:3px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary,#9a9aa3);overflow-wrap:anywhere}",
			".tsk-meta{margin:6px 0 0;display:flex;gap:12px;flex-wrap:wrap;font:400 11.5px/1.4 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-state{margin-left:auto;padding-left:12px;font:500 11px/1.7 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap}",
			".tsk-form{margin:6px 0 8px;padding:16px 0 18px;border-top:1px solid var(--dsw-alias-border-l2,#3b3e46)}",
			".tsk-label{display:block;margin:0 0 5px;font:500 11px/1.3 ui-monospace,SFMono-Regular,monospace;letter-spacing:.06em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-input,.tsk-area{box-sizing:border-box;width:100%;margin:0 0 12px;padding:7px 9px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-primary,#ececf1);font:inherit;font-size:13px}",
			".tsk-area{min-height:62px;resize:vertical;line-height:1.5}",
			".tsk-input:focus-visible,.tsk-area:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:0}",
			".tsk-note{margin:12px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-error{margin:10px 0 0;font-size:12px;color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".tsk-folder{display:inline-flex;align-items:center;gap:6px;max-width:260px;height:24px;padding:0 8px;border:0;border-radius:6px;background:transparent;color:var(--dsw-alias-label-tertiary,#9a9aa3);font:inherit;font-size:11.5px;cursor:pointer}",
			".tsk-folder:hover{background:var(--dsw-alias-bg-layer-3,#2a2d35);color:var(--dsw-alias-label-secondary,#b9b9c2)}",
			".tsk-folder:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".tsk-foldername{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
		].join("\n");

		async function api(path, body) {
			const init =
				body === undefined
					? { headers: { accept: "application/json" } }
					: {
							method: "POST",
							headers: { "content-type": "application/json", "x-dsh-tasks": "1", accept: "application/json" },
							body: JSON.stringify(body),
						};
			const response = await fetch(`/tasks${path}`, init);
			const payload = await response.json().catch(() => ({}));
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

		function ageLabel(time) {
			if (!time) return "";
			const minutes = Math.round((Date.now() - time) / 60000);
			if (minutes < 1) return "recién";
			if (minutes < 60) return `hace ${minutes} min`;
			const hours = Math.round(minutes / 60);
			if (hours < 24) return `hace ${hours} h`;
			const days = Math.round(hours / 24);
			return days === 1 ? "ayer" : `hace ${days} d`;
		}

		/** Cwd de la sesión: la lista de sesiones lo trae aunque el snapshot no. */
		function useCwd(getCwd, sessionId) {
			const [cwd, setCwd] = useState(() => (sessionId ? getCwd(sessionId) : ""));
			useEffect(() => {
				if (!sessionId) return undefined;
				const read = () => setCwd(getCwd(sessionId));
				read();
				let tries = 0;
				const timer = setInterval(() => {
					read();
					if (++tries >= 6) clearInterval(timer);
				}, 500);
				return () => clearInterval(timer);
			}, [getCwd, sessionId]);
			return cwd;
		}

		function TaskRow(props) {
			const { task, onOpen, onResolve, onReopen, busy } = props;
			return h(
				"div",
				{ className: "tsk-row" },
				h(
					"div",
					{ className: "tsk-rowmain" },
					h("p", { className: "tsk-title" }, task.title),
					task.goal ? h("p", { className: "tsk-goal" }, task.goal) : null,
					h(
						"p",
						{ className: "tsk-meta" },
						h("span", null, `creada ${ageLabel(task.createdAt)}`),
						h("span", null, task.sessionId ? "conversación ligada" : "sin conversación"),
					),
					h(
						"div",
						{ className: "tsk-actions", style: { marginTop: 9 } },
						h(
							"button",
							{ type: "button", className: task.sessionId ? "tsk-btn tsk-btn--quiet" : "tsk-btn", onClick: () => onOpen(task), disabled: busy },
							task.sessionId ? "Ver conversación" : "Abrir conversación",
						),
						task.state === "abierta"
							? h("button", { type: "button", className: "tsk-btn tsk-btn--quiet", onClick: () => onResolve(task), disabled: busy }, "Resolver")
							: h("button", { type: "button", className: "tsk-btn tsk-btn--quiet", onClick: () => onReopen(task), disabled: busy }, "Reabrir"),
					),
				),
				h("span", { className: "tsk-state" }, task.state),
			);
		}

		function TasksView(props) {
			const { getCwd, openFolder, createConversation, navigate } = props;
			useStyles();
			const cwd = useCwd(getCwd, props.sessionId);
			const [tasks, setTasks] = useState([]);
			const [phase, setPhase] = useState("loading");
			const [error, setError] = useState(null);
			const [formOpen, setFormOpen] = useState(false);
			const [draft, setDraft] = useState({ title: "", goal: "" });
			const [busy, setBusy] = useState(false);

			const load = useCallback(async () => {
				if (!cwd) {
					setTasks([]);
					setPhase("ready");
					return;
				}
				try {
					const payload = await api(`/list?workspace=${encodeURIComponent(cwd)}`);
					setTasks(payload.tasks ?? []);
					setError(null);
				} catch (cause) {
					setError(cause);
				} finally {
					setPhase("ready");
				}
			}, [cwd]);

			useEffect(() => {
				load();
			}, [load]);

			const mutate = async (task, patch) => {
				setBusy(true);
				try {
					await api("/update", { id: task.id, ...patch });
					await load();
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const create = async () => {
				if (!draft.title.trim() || !cwd) return;
				setBusy(true);
				try {
					await api("/create", { workspace: cwd, title: draft.title, goal: draft.goal });
					setDraft({ title: "", goal: "" });
					setFormOpen(false);
					await load();
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const openTask = async (task) => {
				setBusy(true);
				try {
					if (task.sessionId) navigate(task.sessionId);
					else navigate(await createConversation(task, cwd));
					await load();
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const abiertas = tasks.filter((task) => task.state === "abierta");
			const resueltas = tasks.filter((task) => task.state === "resuelta");
			const row = (task) =>
				h(TaskRow, {
					key: task.id,
					task,
					onOpen: openTask,
					onResolve: (item) => mutate(item, { state: "resuelta" }),
					onReopen: (item) => mutate(item, { state: "abierta" }),
					busy,
				});

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
							h("p", { className: "tsk-eyebrow" }, "Proyecto"),
							h("h1", { className: "tsk-h1" }, "Tareas"),
							cwd ? h("button", { type: "button", className: "tsk-path", title: `Abrir ${cwd}`, onClick: () => openFolder(cwd) }, cwd) : null,
						),
						cwd
							? h(
									"div",
									{ className: "tsk-actions" },
									h("button", { type: "button", className: "tsk-btn tsk-btn--primary", onClick: () => setFormOpen(true) }, "Nueva tarea"),
								)
							: null,
					),
					!cwd ? h("p", { className: "tsk-note" }, "Esta sesión no tiene carpeta. Abrí un workspace (una carpeta) y volvé: las tareas se guardan por carpeta.") : null,
					cwd && formOpen
						? h(
								"div",
								{ className: "tsk-form" },
								h("label", { className: "tsk-label", htmlFor: "tsk-title" }, "Qué hay que resolver"),
								h("input", {
									id: "tsk-title",
									className: "tsk-input",
									value: draft.title,
									autoFocus: true,
									placeholder: "ej. El login no guarda la sesión",
									onChange: (event) => setDraft((current) => ({ ...current, title: event.target.value })),
								}),
								h("label", { className: "tsk-label", htmlFor: "tsk-goal" }, "Cómo sé que está resuelto (opcional)"),
								h("textarea", {
									id: "tsk-goal",
									className: "tsk-area",
									value: draft.goal,
									placeholder: "La prueba concreta: entrar, recargar y seguir logueado.",
									onChange: (event) => setDraft((current) => ({ ...current, goal: event.target.value })),
								}),
								h(
									"div",
									{ className: "tsk-actions" },
									h("button", { type: "button", className: "tsk-btn tsk-btn--primary", onClick: create, disabled: busy || !draft.title.trim() }, "Guardar tarea"),
									h(
										"button",
										{
											type: "button",
											className: "tsk-btn",
											onClick: () => {
												setFormOpen(false);
												setDraft({ title: "", goal: "" });
											},
										},
										"Cancelar",
									),
								),
							)
						: null,
					error ? h("p", { className: "tsk-error" }, error.message) : null,
					phase === "loading" ? h("p", { className: "tsk-note" }, "Leyendo tareas…") : null,
					cwd && abiertas.length
						? h(
								React.Fragment,
								null,
								h("p", { className: "tsk-section" }, `Abiertas · ${abiertas.length}`),
								h("div", { className: "tsk-list" }, abiertas.map(row)),
							)
						: null,
					cwd && resueltas.length
						? h(
								React.Fragment,
								null,
								h("p", { className: "tsk-section" }, `Resueltas · ${resueltas.length}`),
								h("div", { className: "tsk-list" }, resueltas.map(row)),
							)
						: null,
					cwd && !tasks.length && phase === "ready"
						? h("p", { className: "tsk-note" }, "Sin tareas en esta carpeta. Anotá la primera: queda guardada acá y después abre su conversación.")
						: null,
				),
			);
		}

		function FolderPath(props) {
			useStyles();
			const cwd = useCwd(props.getCwd, props.sessionId);
			if (!cwd) return null;
			const home = cwd.replace(/^\/home\/[^/]+/, "~");
			const name = cwd.split("/").filter(Boolean).pop() ?? cwd;
			return h(
				"button",
				{ type: "button", className: "tsk-folder", title: `Abrir ${cwd}`, onClick: () => props.openFolder(cwd) },
				h(
					"svg",
					{ width: 12, height: 12, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
					h("path", {
						d: "M2 4.4c0-.7.6-1.2 1.2-1.2h2.4l1.3 1.4h5.9c.7 0 1.2.6 1.2 1.2v5.9c0 .7-.6 1.2-1.2 1.2H3.2c-.7 0-1.2-.6-1.2-1.2V4.4Z",
						stroke: "currentColor",
						strokeWidth: 1.2,
					}),
				),
				h("span", { className: "tsk-foldername" }, home === cwd ? name : home),
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
				const goal = task.goal ? `\nCriterio de éxito: ${task.goal}` : "";
				const text = `Tarea del proyecto: ${task.title}\nCarpeta: ${cwd}${goal}\n\nAl terminar, cerrá mostrando la evidencia real de lo que hiciste: archivos creados o modificados, comandos que corriste y cómo terminaron, tests. No des nada por hecho sin esa prueba.`;
				try {
					await sessions.using(sessionId, { source: "gateway" }, async (reference) => {
						await reference.ready;
						await reference.binding.session.prompt([{ type: "text", text }], "queue");
					});
				} finally {
					await api("/update", { id: task.id, sessionId, state: "abierta" }).catch(() => {});
				}
				return sessionId;
			};

			ctx.slots.inject("conversation.view", () =>
				ctx.slots.register(
					{
						name: "conversation.view",
						id: "tasks",
						order: 20,
						label: () => "Tareas",
						inject: () => ({ getCwd, openFolder, createConversation, navigate }),
					},
					TasksView,
				),
			);
			ctx.slots.inject("conversation.session.header.actions", () =>
				ctx.slots.register(
					{ name: "conversation.session.header.actions", id: "tasks-folder", order: 0, inject: () => ({ getCwd, openFolder }) },
					FolderPath,
				),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
