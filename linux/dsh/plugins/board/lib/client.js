/**
 * dsh-local-board — client half.
 *
 * La bandeja de tareas: acá se agrega una tarea (workspace + mensaje guardado +
 * imágenes, videos o cualquier archivo), queda esperando y después se lanza:
 * sola, o en lote con un orquestador que decide cuántos agentes abrir.
 * Datos: /tasks/all, /tasks/workspaces y /tasks/upload de dsh-local-tasks.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-board",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;
		const { useEffect, useState } = React;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const PANEL_ID = "tasks-board";
		const STYLE_ID = "dsh-local-board-style";
		const CSS = [
			".brd-root{height:100%;overflow:auto;box-sizing:border-box}",
			".brd-wrap{max-width:820px;margin:0 auto;padding:30px 32px 96px}",
			".brd-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px}",
			".brd-h1{margin:0;font-size:18px;font-weight:550;letter-spacing:-.01em;color:var(--dsw-alias-label-primary,#ececf1)}",
			".brd-line{margin:6px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".brd-btn{box-sizing:border-box;height:28px;padding:0 11px;display:inline-flex;align-items:center;justify-content:center;gap:6px;border:1px solid transparent;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);font:inherit;font-size:12px;line-height:1;cursor:pointer;white-space:nowrap}",
			".brd-btn:hover{color:var(--dsw-alias-label-primary,#ececf1);border-color:var(--dsw-alias-border-l2,#3b3e46)}.brd-btn:focus-visible,.brd-icon:focus-visible,.brd-input:focus-visible,.brd-select:focus-visible,.brd-area:focus-visible,.brd-drop:focus-visible,.brd-check:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".brd-btn[disabled]{opacity:.45;cursor:default}.brd-btn--primary{border-color:transparent;background:var(--dsw-alias-state-business-primary,#6ea8fe);color:#0e1116;font-weight:600}",
			".brd-filters{display:flex;gap:6px;margin:16px 0 4px;flex-wrap:wrap;align-items:center}",
			".brd-filter{height:26px;padding:0 10px;border:1px solid transparent;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);font:inherit;font-size:12px;cursor:pointer}",
			".brd-filter:hover{color:var(--dsw-alias-label-primary,#ececf1)}.brd-filter:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".brd-filter[data-active='true']{border-color:var(--dsw-alias-border-l2,#3b3e46);color:var(--dsw-alias-label-primary,#ececf1)}",
			".brd-form{margin:14px 0 4px;padding:14px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:12px;background:var(--dsw-alias-bg-layer-2,#1d2027)}",
			".brd-label{display:block;margin:0 0 5px;font-size:12px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".brd-select,.brd-input,.brd-area{box-sizing:border-box;width:100%;padding:7px 9px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-primary,#ececf1);font:inherit;font-size:13px}",
			".brd-area{min-height:104px;resize:vertical;line-height:1.55}",
			".brd-field{margin:0 0 12px}",
			".brd-drop{margin:0 0 12px;padding:14px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:9px;background:transparent;color:var(--dsw-alias-label-tertiary,#9a9aa3);font:inherit;font-size:12px;text-align:center;cursor:pointer;width:100%}",
			".brd-drop:hover{color:var(--dsw-alias-label-primary,#ececf1)}.brd-drop[data-over='true']{border-color:var(--dsw-alias-state-business-primary,#6ea8fe);color:var(--dsw-alias-label-primary,#ececf1)}",
			".brd-files{display:flex;flex-wrap:wrap;gap:8px;margin:0 0 12px}",
			".brd-file{display:flex;align-items:center;gap:8px;max-width:100%;padding:5px 6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:8px;background:var(--dsw-alias-bg-layer-1,#16181c)}",
			".brd-file-img{width:44px;height:32px;border-radius:5px;object-fit:cover;display:block;flex:none}",
			".brd-file-body{min-width:0;display:flex;flex-direction:column;gap:1px}",
			".brd-file-name{font-size:12px;line-height:1.4;color:var(--dsw-alias-label-primary,#ececf1);max-width:210px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".brd-file-size{font-size:11px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".brd-row{display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:start;gap:6px 14px;padding:12px 14px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:12px;background:var(--dsw-alias-bg-layer-2,#1d2027);transition:border-color .12s ease}.brd-row:hover{border-color:var(--dsw-alias-border-l2,#3b3e46)}",
			".brd-title{margin:0;font-size:13.5px;font-weight:500;line-height:1.45;color:var(--dsw-alias-label-primary,#ececf1);overflow-wrap:anywhere;text-wrap:pretty}",
			".brd-where{margin:2px 0 0;font-size:12px;line-height:1.45;color:var(--dsw-alias-label-tertiary,#9a9aa3);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".brd-req{margin:4px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-secondary,#b9b9c2);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;overflow-wrap:anywhere}",
			".brd-thumbs{display:flex;gap:6px;margin-top:8px;flex-wrap:wrap}",
			".brd-thumb{width:74px;height:48px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);object-fit:cover;background:var(--dsw-alias-bg-layer-1,#16181c);display:block}",
			".brd-thumb-link{display:block;border-radius:6px}.brd-thumb-link:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".brd-more{align-self:center;font-size:11.5px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".brd-actions{display:flex;align-items:center;gap:2px;justify-content:flex-end}",
			".brd-state{font-size:11.5px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap;margin-right:6px}.brd-state[data-tone='bad']{color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".brd-icon{width:28px;height:28px;border:0;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);display:grid;place-items:center;cursor:pointer}.brd-icon:hover{color:var(--dsw-alias-label-primary,#ececf1)}.brd-icon[disabled]{opacity:.45;cursor:default}",
			".brd-note{margin:12px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}.brd-error{margin:10px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".brd-check{width:14px;height:14px;margin:2px 0 0;flex:none;accent-color:var(--dsw-alias-state-business-primary,#6ea8fe);cursor:pointer}",
			".brd-list{display:flex;flex-direction:column;gap:8px;padding-top:8px}",
			"@media (max-width:640px){.brd-wrap{padding:20px 18px 96px}.brd-row{grid-template-columns:minmax(0,1fr)}.brd-actions{justify-content:flex-start;flex-wrap:wrap}}",
		].join("\n");

		const ICON = {
			open: "M6 3h7v7M13 3L5 11",
			check: "M3.5 8.2l3 3 6-6.4",
			undo: "M4 8a4 4 0 1 0 1.2-2.9M4 3.2v2.6h2.6",
			trash: "M4.2 5.4h7.6M6.6 5.4V4h2.8v1.4M5.4 5.4l.5 6.2h4.2l.5-6.2",
		};

		function Icon(props) {
			return h(
				"button",
				{ type: "button", className: "brd-icon", title: props.label, "aria-label": props.label, onClick: props.onClick, disabled: props.disabled },
				h("svg", { width: 15, height: 15, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
					h("path", { d: ICON[props.icon], stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round" })),
			);
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

		async function api(path, body) {
			const init = body
				? { method: "POST", headers: { "content-type": "application/json", "x-dsh-tasks": "1" }, body: JSON.stringify(body) }
				: { headers: { accept: "application/json" } };
			const response = await fetch(`/tasks${path}`, init);
			const payload = await response.json().catch(() => ({}));
			if (response.status === 404) throw new Error("El servidor todavía no tiene las tareas cargadas. Reiniciá el harness: dsh-web --restart.");
			if (!response.ok) throw new Error(payload?.message || payload?.error || `HTTP ${response.status}`);
			return payload;
		}

		/** Sube el archivo tal cual: el cuerpo es el archivo, no un JSON. */
		async function upload(taskId, file) {
			const query = `task=${encodeURIComponent(taskId)}&name=${encodeURIComponent(file.name)}`;
			const response = await fetch(`/tasks/upload?${query}`, {
				method: "POST",
				headers: { "x-dsh-tasks": "1", "content-type": file.type || "application/octet-stream" },
				body: file,
			});
			const payload = await response.json().catch(() => ({}));
			if (!response.ok) throw new Error(payload?.message || payload?.error || `No se pudo subir ${file.name}`);
			return payload.attachment;
		}

		function fileUrl(path, download) {
			return `/tasks/file?path=${encodeURIComponent(path)}${download ? "&download=1" : ""}`;
		}

		function size(bytes) {
			const value = Number(bytes);
			if (!Number.isFinite(value) || value <= 0) return "";
			if (value < 1024) return `${value} B`;
			if (value < 1024 * 1024) return `${Math.round(value / 1024)} KB`;
			return `${(value / 1024 / 1024).toFixed(value < 10 * 1024 * 1024 ? 1 : 0)} MB`;
		}

		function took(ms) {
			const value = Number(ms);
			if (!Number.isFinite(value) || value <= 0) return "";
			const minutes = Math.round(value / 60000);
			if (minutes < 1) return "menos de 1 min";
			if (minutes < 60) return `${minutes} min`;
			const hours = Math.floor(minutes / 60);
			if (hours < 24) return minutes % 60 ? `${hours} h ${minutes % 60} min` : `${hours} h`;
			return `${Math.floor(hours / 24)} d ${hours % 24} h`;
		}

		function statusOf(task) {
			const text = String(task?.status ?? "").trim();
			const bad = text === "fallada" || task?.outcome === "falló";
			if (text) return { text, bad };
			if (task?.state === "cancelada" || task?.outcome === "cancelada") return { text: "cancelada", bad: false };
			if (task?.outcome === "falló") return { text: "fallada", bad: true };
			if (task?.state === "resuelta" || task?.outcome === "ok") return { text: "cerrada", bad: false };
			return { text: "abierta", bad: false };
		}

		/** Tarea guardada que todavía no trabajó ningún agente. */
		function parked(task) {
			return !task?.sessionId && !task?.orchestratorSessionId && task?.state === "abierta";
		}

		function nameOf(task) {
			const title = String(task?.title ?? "").trim();
			if (title) return title;
			const request = String(task?.request ?? "").trim();
			return request ? request.slice(0, 72) : "Tarea sin título";
		}

		/** Los adjuntos se ven como miniaturas; lo que no es imagen, como archivo. */
		function Thumbs(props) {
			const files = props.files ?? [];
			const shown = files.slice(0, props.max ?? 4);
			return h(
				"div",
				{ className: "brd-thumbs" },
				shown.map((file) =>
					file.kind === "image"
						? h("a", { key: file.path, className: "brd-thumb-link", href: fileUrl(file.path), target: "_blank", rel: "noreferrer", title: file.name },
								h("img", { className: "brd-thumb", src: fileUrl(file.path), alt: file.name, loading: "lazy" }))
						: h("a", { key: file.path, className: "brd-thumb-link", href: fileUrl(file.path, true), title: `${file.name} · ${size(file.size)}`, style: { display: "flex", alignItems: "center", padding: "4px 7px", border: "1px solid var(--dsw-alias-border-l1,#2c2f36)", borderRadius: 6, maxWidth: 168, textDecoration: "none" } },
								h("span", { className: "brd-file-name", style: { maxWidth: 130, fontSize: 11.5 } }, file.name)),
				),
				files.length > shown.length ? h("span", { className: "brd-more" }, `+${files.length - shown.length}`) : null,
			);
		}

		/** Lanzar: una tarea abre su conversación; un lote abre un orquestador por workspace. */
		function useLauncher(get) {
			const sessions = () => {
				const value = get("sessions");
				if (!value || typeof value.create !== "function") throw new Error("el harness no expone `sessions`");
				return value;
			};
			const prompt = (task) => {
				const lines = [`Tarea: ${nameOf(task)}`, `Carpeta: ${task.workspace}`];
				if (task.request) lines.push("", task.request);
				const files = task.attachments ?? [];
				if (files.length) {
					lines.push("", "Archivos del pedido:");
					for (const file of files) lines.push(`- ${file.path} (${file.name}${file.kind === "image" ? ", imagen" : file.kind === "video" ? ", video" : ""})`);
				}
				lines.push("", "Al terminar, cerrá con la prueba visual real: captura de la app o video, rutas de archivos y resultado de los tests. Sin captura no hay evidencia visible.");
				return lines.join("\n");
			};
			const start = async (cwd, text) => {
				const created = await sessions().create(cwd ? { cwd } : {});
				if (!created || created.ok !== true) throw new Error(created?.error?.message || "no se pudo crear la conversación");
				const sessionId = created.value.sessionId;
				await sessions().using(sessionId, { source: "gateway" }, async (reference) => {
					await reference.ready;
					await reference.binding.session.prompt([{ type: "text", text }], "queue");
				});
				return sessionId;
			};
			const one = async (task) => {
				const sessionId = await start(task.workspace, prompt(task));
				await api("/update", { id: task.id, sessionId, launchedAt: Date.now() }).catch(() => null);
				return sessionId;
			};
			const lot = async (tasks) => {
				const groups = new Map();
				for (const task of tasks) {
					const list = groups.get(task.workspace) ?? [];
					list.push(task);
					groups.set(task.workspace, list);
				}
				const opened = [];
				for (const [cwd, list] of groups) {
					const body = list.map((task, index) => {
						const files = (task.attachments ?? []).length ? ` · archivos: ${task.attachments.map((file) => file.path).join(", ")}` : "";
						return `${index + 1}. ${nameOf(task)} (id ${task.id})${files}\n   ${String(task.request ?? "").split("\n").join("\n   ")}`;
					});
					const text = [
						`Sos el orquestador de ${list.length} tarea${list.length === 1 ? "" : "s"} guardada${list.length === 1 ? "" : "s"} en ${cwd}.`,
						"Decidí vos cuántos agentes lanzar y delegá con tus herramientas de subagentes: los archivos de cada tarea están en su ruta y los podés leer.",
						"",
						...body,
						"",
						"Al terminar cada una, contá qué quedó y qué falló. La prueba visual es obligatoria.",
					].join("\n");
					const sessionId = await start(cwd, text);
					for (const task of list) await api("/update", { id: task.id, orchestratorSessionId: sessionId, launchedAt: Date.now() }).catch(() => null);
					opened.push(sessionId);
				}
				return opened;
			};
			return { one, lot };
		}

		function BoardPanel(props) {
			useStyles();
			const get = (name) => (typeof props.get === "function" ? props.get(name) : props[name]);
			const launcher = useLauncher(get);
			const [data, setData] = useState({ tasks: [], workspaces: [], home: "" });
			const [filter, setFilter] = useState("sin-lanzar");
			const [error, setError] = useState(null);
			const [busy, setBusy] = useState(false);
			const [formOpen, setFormOpen] = useState(false);
			const [workspace, setWorkspace] = useState("");
			const [request, setRequest] = useState("");
			const [title, setTitle] = useState("");
			const [files, setFiles] = useState([]);
			const [over, setOver] = useState(false);
			const [picked, setPicked] = useState(() => new Set());

			const load = React.useCallback(async () => {
				try {
					const [all, spaces] = await Promise.all([api("/all"), api("/workspaces")]);
					setData({ tasks: all.tasks ?? [], workspaces: spaces.workspaces ?? [], home: spaces.home ?? "" });
					setWorkspace((current) => current || spaces.home || (spaces.workspaces?.[0]?.path ?? ""));
					setError(null);
				} catch (cause) {
					setError(cause);
				}
			}, []);

			useEffect(() => {
				load();
				const timer = setInterval(load, 8000);
				return () => clearInterval(timer);
			}, [load]);

			const tasks = data.tasks;
			const byState = (label) => tasks.filter((task) => statusOf(task).text === label);
			const parkedTasks = tasks.filter(parked);
			const filters = [
				{ id: "sin-lanzar", label: "Sin lanzar", list: parkedTasks },
				{ id: "abiertas", label: "Abiertas", list: byState("abierta").filter((task) => !parked(task)) },
				{ id: "por-cerrar", label: "Por cerrar", list: byState("por cerrar") },
				{ id: "fallos", label: "Fallos", list: byState("fallada") },
				{ id: "cerradas", label: "Cerradas", list: byState("cerrada") },
				{ id: "todas", label: "Todas", list: tasks },
			];
			const active = filters.find((item) => item.id === filter) ?? filters[0];
			const chosen = tasks.filter((task) => picked.has(task.id) && parked(task));

			const addFiles = (list) => {
				const incoming = [...list].filter(Boolean);
				const next = incoming
					.filter((file) => file.size <= 512 * 1024 * 1024)
					.map((file) => ({ key: `${file.name}-${file.size}-${Date.now()}-${Math.random()}`, file, preview: /^image\//.test(file.type) ? URL.createObjectURL(file) : "" }));
				setFiles((current) => [...current, ...next].slice(0, 40));
				if (next.length < incoming.length) setError(new Error("Se saltearon archivos de más de 512 MB."));
			};

			const drop = (event) => {
				event.preventDefault();
				setOver(false);
				if (event.dataTransfer?.files?.length) addFiles(event.dataTransfer.files);
			};

			const create = async () => {
				if (!workspace || !request.trim()) return;
				setBusy(true);
				setError(null);
				try {
					const created = await api("/create", { workspace, title: title.trim(), request });
					for (const item of files) await upload(created.task.id, item.file);
					setRequest("");
					setTitle("");
					setFiles([]);
					setFormOpen(false);
					setFilter("sin-lanzar");
					await load();
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const launch = async (task) => {
				setBusy(true);
				setError(null);
				try {
					const sessionId = await launcher.one(task);
					await load();
					props.openSession?.(sessionId);
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const launchLot = async () => {
				if (!chosen.length) return;
				setBusy(true);
				setError(null);
				try {
					const opened = await launcher.lot(chosen);
					setPicked(new Set());
					await load();
					if (opened.length) props.openSession?.(opened[0]);
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

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

			const remove = async (task) => {
				setBusy(true);
				try {
					await api("/delete", { id: task.id });
					await load();
				} catch (cause) {
					setError(cause);
				} finally {
					setBusy(false);
				}
			};

			const row = (task) => {
				const status = parked(task) ? "sin lanzar" : statusOf(task).text;
				const target = task.sessionId ?? task.orchestratorSessionId;
				return h(
					"div",
					{ className: "brd-row", key: task.id },
					h(
						"div",
						{ style: { display: "flex", gap: 9, minWidth: 0 } },
						parked(task)
							? h("input", {
									type: "checkbox",
									className: "brd-check",
									checked: picked.has(task.id),
									"aria-label": `Elegir ${nameOf(task)}`,
									onChange: (event) =>
										setPicked((current) => {
											const next = new Set(current);
											if (event.target.checked) next.add(task.id);
											else next.delete(task.id);
											return next;
										}),
								})
							: null,
						h(
							"div",
							{ style: { minWidth: 0 } },
							h("p", { className: "brd-title" }, nameOf(task)),
							h("p", { className: "brd-where", title: task.workspace },
								`${task.workspaceName ?? task.workspace}${task.attachments?.length ? ` · ${task.attachments.length} archivo${task.attachments.length === 1 ? "" : "s"}` : ""}${task.openMs ? ` · guardada hace ${took(task.openMs)}` : ""}`),
							task.request ? h("p", { className: "brd-req" }, task.request) : null,
							task.attachments?.length ? h(Thumbs, { files: task.attachments, max: 4 }) : null,
						),
					),
					h(
						"div",
						{ className: "brd-actions" },
						h("span", { className: "brd-state", "data-tone": statusOf(task).bad ? "bad" : undefined }, status),
						parked(task) ? h("button", { type: "button", className: "brd-btn", onClick: () => launch(task), disabled: busy, title: `Lanzar en ${task.workspace}` }, "Lanzar") : null,
						target ? h(Icon, { icon: "open", label: "Abrir conversación", onClick: () => props.openSession?.(target) }) : null,
						task.state === "abierta"
							? h(Icon, { icon: "check", label: "Resolver", onClick: () => change(task, "resuelta"), disabled: busy })
							: h(Icon, { icon: "undo", label: "Reabrir", onClick: () => change(task, "abierta"), disabled: busy }),
						h(Icon, { icon: "trash", label: "Borrar tarea", onClick: () => remove(task), disabled: busy }),
					),
				);
			};

			return h(
				"div",
				{ className: "brd-root" },
				h(
					"div",
					{ className: "brd-wrap" },
					h("div", { className: "brd-head" },
						h("div", { style: { minWidth: 0 } },
							h("h1", { className: "brd-h1" }, "Tareas"),
							h("p", { className: "brd-line" }, `${parkedTasks.length} sin lanzar · ${byState("abierta").length - parkedTasks.length} en curso · ${byState("fallada").length} con fallos · ${byState("cerrada").length} cerradas`)),
						h("div", { style: { display: "flex", gap: 6 } },
							h("button", { type: "button", className: "brd-btn brd-btn--primary", onClick: () => setFormOpen((open) => !open) }, "Nueva tarea"))),
					formOpen
						? h(
								"div",
								{ className: "brd-form" },
								h("div", { className: "brd-field" },
									h("label", { className: "brd-label", htmlFor: "brd-ws" }, "Workspace"),
									h("select", { id: "brd-ws", className: "brd-select", value: workspace, onChange: (event) => setWorkspace(event.target.value) },
										data.workspaces.map((item) => h("option", { key: item.path, value: item.path }, item.title ? `${item.title} — ${item.path}` : item.path)))),
								h("div", { className: "brd-field" },
									h("label", { className: "brd-label", htmlFor: "brd-req" }, "Mensaje para el agente"),
									h("textarea", { id: "brd-req", className: "brd-area", value: request, placeholder: "Qué hay que resolver, con el contexto que haga falta. Esto se le manda al agente cuando la lances.", onChange: (event) => setRequest(event.target.value) })),
								h("div", { className: "brd-field" },
									h("label", { className: "brd-label", htmlFor: "brd-title" }, "Título corto (opcional)"),
									h("input", { id: "brd-title", className: "brd-input", value: title, placeholder: "Si no ponés uno, se usa la primera línea del mensaje", onChange: (event) => setTitle(event.target.value) })),
								h("div", { className: "brd-field" },
									h("span", { className: "brd-label" }, "Archivos (imágenes, videos, PDFs, logs)"),
									h("div", {
										className: "brd-drop",
										role: "button",
										tabIndex: 0,
										"data-over": String(over),
										onClick: () => document.getElementById("brd-file-input")?.click(),
										onKeyDown: (event) => {
											if (event.key === "Enter" || event.key === " ") {
												event.preventDefault();
												document.getElementById("brd-file-input")?.click();
											}
										},
										onDragOver: (event) => {
											event.preventDefault();
											setOver(true);
										},
										onDragLeave: () => setOver(false),
										onDrop: drop,
									}, over ? "Soltá los archivos acá" : "Arrastrá archivos acá o hacé clic para elegirlos"),
									h("input", { id: "brd-file-input", type: "file", multiple: true, style: { display: "none" }, onChange: (event) => { addFiles(event.target.files ?? []); event.target.value = ""; } })),
								files.length
									? h("div", { className: "brd-files" },
											files.map((item) =>
												h("div", { className: "brd-file", key: item.key },
													item.preview ? h("img", { className: "brd-file-img", src: item.preview, alt: item.file.name }) : null,
													h("div", { className: "brd-file-body" },
														h("span", { className: "brd-file-name", title: item.file.name }, item.file.name),
														h("span", { className: "brd-file-size" }, size(item.file.size))),
													h("button", { type: "button", className: "brd-icon", title: "Quitar archivo", "aria-label": `Quitar ${item.file.name}`, onClick: () => setFiles((current) => current.filter((entry) => entry.key !== item.key)) },
														h("svg", { width: 13, height: 13, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" }, h("path", { d: "M4 4l8 8M12 4l-8 8", stroke: "currentColor", strokeWidth: 1.5, strokeLinecap: "round" })))))
									: null,
								h("div", { style: { display: "flex", gap: 8, marginTop: 4 } },
									h("button", { type: "button", className: "brd-btn brd-btn--primary", onClick: create, disabled: busy || !request.trim() || !workspace }, busy ? "Guardando…" : "Guardar tarea"),
									h("button", { type: "button", className: "brd-btn", onClick: () => { setFormOpen(false); setRequest(""); setTitle(""); setFiles([]); } }, "Cancelar")))
						: null,
					h("div", { className: "brd-filters" },
						filters.map((item) =>
							h("button", {
								type: "button",
								key: item.id,
								className: "brd-filter",
								"data-active": String(item.id === filter),
								onClick: () => setFilter(item.id),
							}, `${item.label} (${item.list.length})`)),
						chosen.length
							? h("button", { type: "button", className: "brd-btn", onClick: launchLot, disabled: busy, title: "Un orquestador por workspace decide cuántos agentes abrir" }, busy ? "Lanzando…" : `Lanzar lote (${chosen.length})`)
							: null),
					error ? h("p", { className: "brd-error" }, error.message) : null,
					active.list.length ? h("div", { className: "brd-list" }, active.list.slice(0, 200).map(row)) : null,
					!active.list.length && !error
						? h("p", { className: "brd-note" }, filter === "sin-lanzar" ? "No hay tareas guardadas: creá una con Nueva tarea y queda esperando." : "No hay tareas en esta vista.")
						: null,
				),
			);
		}

		function BoardIcon(props) {
			const size = props?.size ?? 16;
			return h("svg", { width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
				h("rect", { x: 1.8, y: 1.8, width: 12.4, height: 12.4, rx: 3, stroke: "currentColor", strokeWidth: 1.3 }),
				h("path", { d: "M4.6 8.1l2 2 4.2-4.4", stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "round", strokeLinejoin: "round" }));
		}

		function apply(ctx) {
			const get = (name) => (typeof ctx.get === "function" ? ctx.get(name) : ctx[name]);
			const openSession = (sessionId) => {
				const layout = get("layout");
				if (layout && typeof layout.selectPanel === "function") layout.selectPanel(null);
				const uiWorkspace = get("uiWorkspace");
				if (uiWorkspace && typeof uiWorkspace.openSession === "function") uiWorkspace.openSession(sessionId);
			};
			ctx.slots.inject("sidebar.panellist", () =>
				ctx.slots.register({ name: "sidebar.panellist", id: PANEL_ID, order: 20, label: () => "Tareas" }, BoardIcon));
			ctx.slots.inject("main", () =>
				ctx.slots.register({ name: "main", key: PANEL_ID, inject: () => ({ get, openSession }) }, BoardPanel));
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
