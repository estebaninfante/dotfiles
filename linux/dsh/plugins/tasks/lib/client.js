/**
 * dsh-local-tasks — client half.
 *
 * Vista "Tareas" al lado de Chat y Trajectory: cada pedido del usuario queda
 * como tarea del proyecto (el host la registra al llegar el mensaje) y cada
 * tarea muestra su prueba visual levantada del log de la sesión.
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
			".tsk-head{display:flex;align-items:flex-start;gap:16px;justify-content:space-between;padding-bottom:12px}",
			".tsk-h1{margin:0;font-size:18px;font-weight:550;letter-spacing:-.01em;color:var(--dsw-alias-label-primary,#ececf1)}.tsk-path{margin:4px 0 0;padding:0;border:0;background:transparent;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:400 12px/1.5 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-tertiary,#9a9aa3);cursor:pointer;text-align:left}",
			".tsk-path:hover{color:var(--dsw-alias-label-secondary,#b9b9c2)}.tsk-path:focus-visible,.tsk-btn:focus-visible,.tsk-input:focus-visible,.tsk-area:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".tsk-btn{box-sizing:border-box;height:26px;padding:0 10px;display:inline-flex;align-items:center;justify-content:center;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:transparent;color:var(--dsw-alias-label-primary,#e9e9ee);font:inherit;font-size:12px;line-height:1;cursor:pointer;white-space:nowrap}",
			".tsk-btn:hover{background:var(--dsw-alias-bg-layer-3,#2a2d35)}.tsk-btn[disabled]{opacity:.5;cursor:default}",
			".tsk-btn--quiet{border-color:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2)}.tsk-btn--primary{border-color:transparent;background:var(--dsw-alias-state-business-primary,#6ea8fe);color:#0e1116;font-weight:600}",
			".tsk-actions{display:flex;align-items:center;gap:4px;flex-wrap:wrap;justify-content:flex-end}",
			".tsk-section{display:flex;align-items:baseline;gap:8px;margin:22px 0 2px;font:500 12px/1.4 ui-monospace,SFMono-Regular,monospace;letter-spacing:.05em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-count{font-weight:400;color:var(--dsw-alias-label-quaternary,#7f838c)}.tsk-list{border-top:1px solid var(--dsw-alias-border-l1,#2c2f36)}",
			".tsk-row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:4px 16px;align-items:center;padding:12px 2px;border-bottom:1px solid var(--dsw-alias-border-l1,#2c2f36)}",
			".tsk-main{min-width:0}",
			".tsk-title{margin:0;font-size:13.5px;font-weight:500;line-height:1.45;color:var(--dsw-alias-label-primary,#ececf1);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".tsk-goal{margin:2px 0 0;font-size:12px;line-height:1.45;color:var(--dsw-alias-label-tertiary,#9a9aa3);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".tsk-side{display:flex;flex-direction:column;align-items:flex-end;gap:6px}",
			".tsk-state{font:400 11px/1.4 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap}",
			".tsk-state[data-tone='bad']{color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".tsk-form{margin:4px 0 8px;padding:14px 0 16px;border-top:1px solid var(--dsw-alias-border-l1,#2c2f36)}",
			".tsk-label{display:block;margin:0 0 4px;font:500 11px/1.3 ui-monospace,SFMono-Regular,monospace;letter-spacing:.05em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-input,.tsk-area{box-sizing:border-box;width:100%;margin:0 0 10px;padding:7px 9px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-primary,#ececf1);font:inherit;font-size:13px}.tsk-area{min-height:58px;resize:vertical;line-height:1.5}",
			".tsk-note{margin:12px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}.tsk-error{margin:10px 0 0;font-size:12px;color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".tsk-proof{grid-column:1 / -1;margin:8px 0 2px;padding:10px 12px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:8px;background:var(--dsw-alias-bg-layer-2,#1d2027)}",
			".tsk-evline{margin:0;font:400 12px/1.6 ui-monospace,SFMono-Regular,monospace;color:var(--dsw-alias-label-secondary,#b9b9c2);text-wrap:balance}.tsk-evline a{color:var(--dsw-alias-label-primary,#e9e9ee);text-decoration:none;border-bottom:1px solid var(--dsw-alias-border-l2,#3b3e46)}.tsk-evline a:hover{border-bottom-color:currentColor}",
			".tsk-gallery{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 0}.tsk-thumb{display:block;width:124px;height:78px;border-radius:6px;overflow:hidden;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:var(--dsw-alias-bg-layer-3,#2a2d35)}.tsk-thumb img{width:100%;height:100%;object-fit:cover;display:block}",
			".tsk-thumb:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}.tsk-video{width:200px;height:114px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:#000}",
			"@media (max-width:640px){.tsk-wrap{padding:20px 18px 88px}.tsk-head{flex-direction:column;gap:10px}.tsk-row{grid-template-columns:minmax(0,1fr)}.tsk-side{align-items:flex-start;flex-direction:row;gap:8px;flex-wrap:wrap}.tsk-actions{justify-content:flex-start}}",
		].join("\n");

		async function api(path, body) {
			const init =
				body === undefined
					? { headers: { accept: "application/json" } }
					: { method: "POST", headers: { "content-type": "application/json", "x-dsh-tasks": "1", accept: "application/json" }, body: JSON.stringify(body) };
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

		function statusOf(task) {
			if (task.state === "resuelta") return { text: "resuelta", bad: false };
			const status = task.status ?? null;
			if (!status) return { text: "abierta", bad: false };
			return { text: status, bad: !/^(en curso|cerró bien|abierta)$/.test(status) };
		}

		function proofLine(evidence) {
			const stats = evidence.stats;
			return [
				stats.media ? `${stats.media} ${stats.media === 1 ? "prueba visual" : "pruebas visuales"}` : null,
				stats.deliverables ? `${stats.deliverables} ${stats.deliverables === 1 ? "entregable" : "entregables"}` : null,
				evidence.end ? (evidence.end.reason === "completed" ? "cerró bien" : `cerró: ${evidence.end.reason}`) : null,
			]
				.filter(Boolean)
				.join(" · ");
		}

		function Proof(props) {
			const { proof } = props;
			if (proof.phase === "loading") return h("p", { className: "tsk-note" }, "Leyendo la prueba del pedido…");
			if (proof.phase === "error") return h("p", { className: "tsk-error" }, proof.error.message);
			const evidence = proof.evidence;
			const media = evidence.media ?? [];
			const deliverables = evidence.deliverables ?? [];
			return h(
				"div",
				{ className: "tsk-proof" },
				h("p", { className: "tsk-evline" }, proofLine(evidence) || "Sin prueba visual"),
				media.length
					? h(
							"div",
							{ className: "tsk-gallery" },
							media.map((item) =>
								item.kind === "video"
									? h("video", { key: item.path, className: "tsk-video", controls: true, preload: "metadata", src: item.url })
									: h(
											"a",
											{ key: item.path, className: "tsk-thumb", href: item.url, target: "_blank", rel: "noreferrer", title: item.path },
											h("img", { src: item.url, alt: item.label, loading: "lazy" }),
										),
							),
						)
					: null,
				!media.length && !deliverables.length ? h("p", { className: "tsk-note" }, "Cerró sin captura ni video: no hay prueba que se pueda ver.") : null,
				deliverables.map((file) =>
					h(
						"p",
						{ className: "tsk-evline", key: file.path },
						h("a", { href: `/api/file?path=${encodeURIComponent(file.path)}`, target: "_blank", rel: "noreferrer" }, file.path),
						file.description ? ` — ${file.description}` : "",
					),
				),
			);
		}

		function TaskRow(props) {
			const { task, onOpen, onResolve, onReopen, onProof, proof, proofOpen, busy } = props;
			const status = statusOf(task);
			return h(
				"div",
				{ className: "tsk-row" },
				h(
					"div",
					{ className: "tsk-main" },
					h("p", { className: "tsk-title", title: task.title }, task.title),
					task.goal ? h("p", { className: "tsk-goal", title: task.goal }, task.goal) : null,
				),
				h(
					"div",
					{ className: "tsk-side" },
					h("span", { className: "tsk-state", "data-tone": status.bad ? "bad" : undefined, title: task.turn ? `turno ${task.turn}` : undefined }, status.text),
					h(
						"div",
						{ className: "tsk-actions" },
						h("button", { type: "button", className: "tsk-btn tsk-btn--quiet", onClick: () => onOpen(task), disabled: busy }, task.sessionId ? "Abrir" : "Empezar"),
						task.sessionId ? h("button", { type: "button", className: "tsk-btn tsk-btn--quiet", onClick: () => onProof(task), disabled: busy }, proofOpen ? "Ocultar" : "Prueba") : null,
						task.state === "abierta"
							? h("button", { type: "button", className: "tsk-btn tsk-btn--quiet", onClick: () => onResolve(task), disabled: busy }, "Resolver")
							: h("button", { type: "button", className: "tsk-btn tsk-btn--quiet", onClick: () => onReopen(task), disabled: busy }, "Reabrir"),
					),
				),
				proofOpen ? h(Proof, { proof }) : null,
			);
		}

		function TasksView(props) {
			const { getCwd, openFolder, createConversation, navigate } = props;
			useStyles();
			const [cwd, setCwd] = useState(() => (props.sessionId ? getCwd(props.sessionId) : ""));
			const [tasks, setTasks] = useState([]);
			const [phase, setPhase] = useState("loading");
			const [error, setError] = useState(null);
			const [formOpen, setFormOpen] = useState(false);
			const [draft, setDraft] = useState({ title: "", goal: "" });
			const [busy, setBusy] = useState(false);
			const [proof, setProof] = useState(null);

			useEffect(() => {
				if (!props.sessionId) return undefined;
				let tries = 0;
				const timer = setInterval(() => {
					const value = getCwd(props.sessionId);
					if (value) {
						setCwd(value);
						clearInterval(timer);
					} else if (++tries >= 8) clearInterval(timer);
				}, 400);
				return () => clearInterval(timer);
			}, [getCwd, props.sessionId]);

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
				const timer = setInterval(load, 8000);
				return () => clearInterval(timer);
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

			const importRequests = async () => {
				if (!props.sessionId) return;
				setBusy(true);
				try {
					await api("/backfill", { session: props.sessionId });
					await load();
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const showProof = async (task) => {
				if (proof?.id === task.id) {
					setProof(null);
					return;
				}
				if (!task.sessionId) return;
				setProof({ id: task.id, phase: "loading" });
				try {
					const turn = task.turn ? `&turn=${task.turn}` : "";
					const payload = await api(`/evidence?session=${encodeURIComponent(task.sessionId)}${turn}`);
					setProof({ id: task.id, phase: "ready", evidence: payload.evidence });
				} catch (cause) {
					setProof({ id: task.id, phase: "error", error: cause });
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
					onProof: showProof,
					proof: proof?.id === task.id ? proof : null,
					proofOpen: proof?.id === task.id,
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
							h("h1", { className: "tsk-h1" }, "Tareas"),
							cwd ? h("button", { type: "button", className: "tsk-path", title: `Abrir ${cwd}`, onClick: () => openFolder(cwd) }, cwd) : null,
						),
						cwd ? h("div", { className: "tsk-actions" }, h("button", { type: "button", className: "tsk-btn tsk-btn--primary", onClick: () => setFormOpen(true) }, "Nueva tarea")) : null,
					),
					!cwd ? h("p", { className: "tsk-note" }, "Esta sesión no tiene carpeta. Abrí un workspace y volvé: las tareas se guardan por carpeta.") : null,
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
									{ className: "tsk-actions", style: { justifyContent: "flex-start" } },
									h("button", { type: "button", className: "tsk-btn tsk-btn--primary", onClick: create, disabled: busy || !draft.title.trim() }, "Guardar"),
									h("button", { type: "button", className: "tsk-btn", onClick: () => { setFormOpen(false); setDraft({ title: "", goal: "" }); } }, "Cancelar"),
								),
							)
						: null,
					error ? h("p", { className: "tsk-error" }, error.message) : null,
					phase === "loading" ? h("p", { className: "tsk-note" }, "Leyendo tareas…") : null,
					cwd && abiertas.length
						? h(React.Fragment, null, h("p", { className: "tsk-section" }, "Abiertas ", h("span", { className: "tsk-count" }, String(abiertas.length))), h("div", { className: "tsk-list" }, abiertas.map(row)))
						: null,
					cwd && resueltas.length
						? h(React.Fragment, null, h("p", { className: "tsk-section" }, "Resueltas ", h("span", { className: "tsk-count" }, String(resueltas.length))), h("div", { className: "tsk-list" }, resueltas.map(row)))
						: null,
					cwd && !tasks.length && phase === "ready"
						? h(
								React.Fragment,
								null,
								h("p", { className: "tsk-note" }, "Cada pedido del chat queda acá solo."),
								props.sessionId ? h("button", { type: "button", className: "tsk-btn", style: { marginTop: 10 }, onClick: importRequests, disabled: busy }, "Traer los pedidos de esta conversación") : null,
							)
						: null,
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
				const goal = task.goal ? `\nCriterio de éxito: ${task.goal}` : "";
				const text = `Tarea del proyecto: ${task.title}\nCarpeta: ${cwd}${goal}\n\nAl terminar, cerrá con la prueba visual real: captura de la app o video, rutas de archivos y resultado de los tests. Sin captura no hay evidencia visible.`;
				await sessions.using(sessionId, { source: "gateway" }, async (reference) => {
					await reference.ready;
					await reference.binding.session.prompt([{ type: "text", text }], "queue");
				});
				return sessionId;
			};

			ctx.slots.inject("conversation.view", () =>
				ctx.slots.register(
					{ name: "conversation.view", id: "tasks", order: 20, label: () => "Tareas", inject: () => ({ getCwd, openFolder, createConversation, navigate }) },
					TasksView,
				),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
