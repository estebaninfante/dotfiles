/**
 * dsh-local-board — client half.
 *
 * La pestaña Tareas: buscador por texto, el estado de cada tarea en su menú y
 * un menú para agrupar y ordenar. Arriba se guarda una tarea nueva y abajo se
 * lanza sola o en lote. Datos: /tasks/all, /tasks/workspaces, /tasks/update.
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
		const primitives = (() => { try { return require("@deepseek-ai/dsh-client-ui-primitives"); } catch { return null; } })();
		const Menu = primitives?.Menu ?? null;

		const CSS = [
			".brd-root{height:100%;overflow:auto;box-sizing:border-box}.brd-wrap{max-width:820px;margin:0 auto;padding:30px 32px 96px}",
			".brd-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px}.brd-h1{margin:0;font-size:18px;font-weight:550;letter-spacing:-.01em;color:var(--dsw-alias-label-primary,#ececf1)}",
			".brd-line{margin:6px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary,#9a9aa3)}.brd-label{display:block;margin:0 0 5px;font-size:12px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".brd-btn{box-sizing:border-box;height:28px;padding:0 11px;display:inline-flex;align-items:center;justify-content:center;gap:6px;border:1px solid transparent;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);font:inherit;font-size:12px;line-height:1;cursor:pointer;white-space:nowrap}.brd-btn:hover{color:var(--dsw-alias-label-primary,#ececf1);border-color:var(--dsw-alias-border-l2,#3b3e46)}.brd-btn[disabled]{opacity:.45;cursor:default}",
			".brd-btn--primary{border-color:transparent;background:var(--dsw-alias-state-business-primary,#6ea8fe);color:#0e1116;font-weight:600}",
			".brd-btn:focus-visible,.brd-icon:focus-visible,.brd-input:focus-visible,.brd-select:focus-visible,.brd-area:focus-visible,.brd-drop:focus-visible,.brd-check:focus-visible,.brd-thumb-link:focus-visible,.brd-state:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".brd-tools{display:flex;gap:8px;align-items:center;margin:18px 0 10px;flex-wrap:wrap}.brd-search{flex:1 1 240px;min-width:0}.brd-search input{box-sizing:border-box;width:100%;height:30px;padding:0 10px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-primary,#ececf1);font:inherit;font-size:13px}",
			".brd-trigger{height:30px;padding:0 9px 0 10px;display:inline-flex;align-items:center;gap:6px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);font:inherit;font-size:12px;cursor:pointer;white-space:nowrap}.brd-trigger:hover{color:var(--dsw-alias-label-primary,#ececf1)}.brd-trigger[data-open='true']{color:var(--dsw-alias-label-primary,#ececf1);border-color:var(--dsw-alias-border-l3,#4a4d57)}",
			".brd-form{margin:14px 0 4px;padding:14px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:12px;background:var(--dsw-alias-bg-layer-2,#1d2027)}.brd-field{margin:0 0 12px}",
			".brd-select,.brd-area{box-sizing:border-box;width:100%;padding:7px 9px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:7px;background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-primary,#ececf1);font:inherit;font-size:13px}.brd-area{min-height:104px;resize:vertical;line-height:1.55}",
			".brd-drop{margin:0 0 12px;padding:14px;border:1px solid var(--dsw-alias-border-l2,#3b3e46);border-radius:9px;background:transparent;color:var(--dsw-alias-label-tertiary,#9a9aa3);font:inherit;font-size:12px;text-align:center;cursor:pointer;width:100%}.brd-drop:hover,.brd-drop[data-over='true']{color:var(--dsw-alias-label-primary,#ececf1)}.brd-drop[data-over='true']{border-color:var(--dsw-alias-state-business-primary,#6ea8fe)}",
			".brd-files{display:flex;flex-wrap:wrap;gap:8px;margin:0 0 12px}.brd-file{display:flex;align-items:center;gap:8px;max-width:100%;padding:5px 6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:8px;background:var(--dsw-alias-bg-layer-1,#16181c)}",
			".brd-file-img{width:44px;height:32px;border-radius:5px;object-fit:cover;display:block;flex:none}.brd-file-body{min-width:0;display:flex;flex-direction:column;gap:1px}.brd-file-name{font-size:12px;line-height:1.4;color:var(--dsw-alias-label-primary,#ececf1);max-width:210px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.brd-file-size{font-size:11px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".brd-group{margin:18px 0 0}.brd-group-h{margin:0 0 8px;font-size:12px;font-weight:500;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3)}.brd-list{display:flex;flex-direction:column;gap:8px}",
			".brd-row{display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:start;gap:6px 14px;padding:12px 14px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:12px;background:var(--dsw-alias-bg-layer-2,#1d2027);transition:border-color .12s ease}.brd-row:hover{border-color:var(--dsw-alias-border-l2,#3b3e46)}",
			".brd-title{margin:0;font-size:13.5px;font-weight:500;line-height:1.45;color:var(--dsw-alias-label-primary,#ececf1);overflow-wrap:anywhere;text-wrap:pretty}",
			".brd-where{margin:2px 0 0;font-size:12px;line-height:1.45;color:var(--dsw-alias-label-tertiary,#9a9aa3);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".brd-req{margin:4px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-secondary,#b9b9c2);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;overflow-wrap:anywhere}",
			".brd-thumbs{display:flex;gap:6px;margin-top:8px;flex-wrap:wrap}.brd-more{align-self:center;font-size:11.5px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}.brd-thumb{width:74px;height:48px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);object-fit:cover;background:var(--dsw-alias-bg-layer-1,#16181c);display:block}.brd-thumb-link{display:block;border-radius:6px}",
			".brd-file-chip{display:flex;align-items:center;padding:4px 7px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:6px;max-width:168px;text-decoration:none}",
			".brd-actions{display:flex;align-items:center;gap:2px;justify-content:flex-end}.brd-state{border-color:transparent;background:transparent}.brd-state[data-tone='bad']{color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".brd-icon{width:28px;height:28px;border:0;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);display:grid;place-items:center;cursor:pointer}.brd-icon:hover{color:var(--dsw-alias-label-primary,#ececf1)}.brd-icon[disabled]{opacity:.45;cursor:default}",
			".brd-note{margin:12px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}.brd-error{margin:10px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".brd-check{width:14px;height:14px;margin:2px 0 0;flex:none;accent-color:var(--dsw-alias-state-business-primary,#6ea8fe);cursor:pointer}",
			"@media (max-width:640px){.brd-wrap{padding:20px 18px 96px}.brd-row{grid-template-columns:minmax(0,1fr)}.brd-actions{justify-content:flex-start;flex-wrap:wrap}}",
		].join("\n");

		const PATHS = {
			open: "M6 3h7v7M13 3L5 11", trash: "M4.2 5.4h7.6M6.6 5.4V4h2.8v1.4M5.4 5.4l.5 6.2h4.2l.5-6.2",
			close: "M4 4l8 8M12 4l-8 8", chevron: "M4.5 6.5L8 10l3.5-3.5",
		};
		const glyph = (name, size = 15) =>
			h("svg", { width: size, height: size, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
				h("path", { d: PATHS[name], stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round" }));
		const Icon = (props) =>
			h("button", { type: "button", className: "brd-icon", title: props.label, "aria-label": props.label, onClick: props.onClick, disabled: props.disabled }, glyph(props.icon));

		const useStyles = () => useEffect(() => {
			const style = document.getElementById(STYLE_ID) ?? Object.assign(document.createElement("style"), { id: STYLE_ID });
			if (!style.isConnected) document.head.appendChild(style);
			if (style.textContent !== CSS) style.textContent = CSS;
		}, []);

		const api = async (path, body) => {
			const init = body ? { method: "POST", headers: { "content-type": "application/json", "x-dsh-tasks": "1" }, body: JSON.stringify(body) } : {};
			const response = await fetch(`/tasks${path}`, init);
			const payload = await response.json().catch(() => ({}));
			if (response.status === 404) throw new Error("El servidor todavía no tiene las tareas cargadas. Reiniciá el harness: dsh-web --restart.");
			if (!response.ok) throw new Error(payload?.message || payload?.error || `HTTP ${response.status}`);
			return payload;
		};
		/** El archivo sube tal cual: el cuerpo es el archivo, no un JSON. */
		async function upload(taskId, file) {
			const query = `task=${encodeURIComponent(taskId)}&name=${encodeURIComponent(file.name)}`;
			const response = await fetch(`/tasks/upload?${query}`, { method: "POST", headers: { "x-dsh-tasks": "1", "content-type": file.type || "application/octet-stream" }, body: file });
			const payload = await response.json().catch(() => ({}));
			if (!response.ok) throw new Error(payload?.message || payload?.error || `No se pudo subir ${file.name}`);
			return payload.attachment;
		}
		const fileUrl = (path, download) => `/tasks/file?path=${encodeURIComponent(path)}${download ? "&download=1" : ""}`;
		const size = (bytes) => {
			const value = Number(bytes);
			if (!Number.isFinite(value) || value <= 0) return "";
			if (value < 1024) return `${value} B`;
			if (value < 1024 * 1024) return `${Math.round(value / 1024)} KB`;
			return `${(value / 1024 / 1024).toFixed(value < 10 * 1024 * 1024 ? 1 : 0)} MB`;
		};
		const took = (ms) => {
			const minutes = Math.round(Number(ms) / 60000);
			if (!Number.isFinite(minutes) || minutes < 1) return "";
			if (minutes < 60) return `${minutes} min`;
			const hours = Math.floor(minutes / 60);
			if (hours < 24) return minutes % 60 ? `${hours} h ${minutes % 60} min` : `${hours} h`;
			return `${Math.floor(hours / 24)} d ${hours % 24} h`;
		};

		/** Lo que el usuario puede declarar. "en curso" y "sin lanzar" son del servidor. */
		const STATES = ["abierta", "por_revisar", "cerrada", "fallada", "cancelada"].map((id) => ({ id, label: id.replace("_", " ") }));
		const GROUPS = [["none", "Sin agrupar"], ["estado", "Estado"], ["proyecto", "Proyecto"], ["sesion", "Conversación"], ["dia", "Día"], ["origen", "Origen"]].map(([id, label]) => ({ id, label }));
		const SORTS = [["recientes", "Más recientes"], ["antiguas", "Más antiguas"], ["titulo", "Título A–Z"], ["estado", "Estado"]].map(([id, label]) => ({ id, label }));
		const ORDER = ["sin lanzar", "en curso", "por revisar", "abierta", "fallada", "cancelada", "cerrada"];
		/** El estado lo resuelve el servidor; la UI solo lo muestra y lo cambia. */
		function statusOf(task) {
			const text = String(task?.status ?? "").trim();
			if (text) return { text, bad: text === "fallada" || task?.outcome === "falló" };
			if (task?.state === "cancelada") return { text: "cancelada", bad: false };
			if (task?.state === "cerrada" || task?.state === "resuelta") return { text: "cerrada", bad: false };
			return { text: "abierta", bad: false };
		}
		/** Tarea guardada que todavía no trabajó ningún agente. */
		const parked = (task) => !task?.sessionId && !task?.orchestratorSessionId && task?.state === "abierta";
		const shownStatus = (task) => (parked(task) ? "sin lanzar" : statusOf(task).text);
		function nameOf(task) {
			const title = String(task?.title ?? "").trim();
			if (title) return title;
			const request = String(task?.request ?? "").trim();
			return request ? request.slice(0, 72) : "Tarea sin título";
		}
		/** Los adjuntos se ven como miniaturas; lo que no es imagen, como archivo. */		function Thumbs(props) {
			const files = props.files ?? [];
			const shown = files.slice(0, props.max ?? 4);
			return h("div", { className: "brd-thumbs" },
				shown.map((file) => file.kind === "image"
					? h("a", { key: file.path, className: "brd-thumb-link", href: fileUrl(file.path), target: "_blank", rel: "noreferrer", title: file.name },
						h("img", { className: "brd-thumb", src: fileUrl(file.path), alt: file.name, loading: "lazy" }))
					: h("a", { key: file.path, className: "brd-thumb-link brd-file-chip", href: fileUrl(file.path, true), title: `${file.name} · ${size(file.size)}` },
						h("span", { className: "brd-file-name", style: { maxWidth: 130, fontSize: 11.5 } }, file.name))),
				files.length > shown.length ? h("span", { className: "brd-more" }, `+${files.length - shown.length}`) : null);
		}
		/** Lanzar: una tarea abre su conversación; un lote abre un orquestador por workspace. */
		function useLauncher(get) {
			const sessions = () => {
				const value = get("sessions");
				if (!value || typeof value.create !== "function") throw new Error("el harness no expone `sessions`");
				return value;
			};
			const prompt = (task) => {
				const files = task.attachments ?? [];
				return [
					`Tarea: ${nameOf(task)}`, `Carpeta: ${task.workspace}`, task.request ? `\n${task.request}` : "",
					files.length ? `\nArchivos del pedido:\n${files.map((file) => `- ${file.path} (${file.name}${file.kind === "image" ? ", imagen" : file.kind === "video" ? ", video" : ""})`).join("\n")}` : "",
					"\nAl terminar, cerrá con la prueba visual real: captura de la app o video, rutas de archivos y resultado de los tests. Sin captura no hay evidencia visible.",
					"No cierres la tarea: dejala por revisar. El estado final lo declara el usuario.",
				].join("\n");
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
				for (const task of tasks) groups.set(task.workspace, [...(groups.get(task.workspace) ?? []), task]);
				const opened = [];
				for (const [cwd, list] of groups) {
					const body = list.map((task, index) => `${index + 1}. ${nameOf(task)} (id ${task.id})\n   ${String(task.request ?? "").split("\n").join("\n   ")}`);
					const text = [
						`Sos el orquestador de ${list.length} tarea${list.length === 1 ? "" : "s"} guardada${list.length === 1 ? "" : "s"} en ${cwd}.`,
						"Decidí vos cuántos agentes lanzar y delegá con tus herramientas de subagentes.",
						"", ...body, "", "Contá qué quedó y qué falló en cada una. La prueba visual es obligatoria. No cierres las tareas: quedan por revisar.",
					].join("\n");
					const sessionId = await start(cwd, text);
					for (const task of list) await api("/update", { id: task.id, orchestratorSessionId: sessionId, launchedAt: Date.now() }).catch(() => null);
					opened.push(sessionId);
				}
				return opened;
			};
			return { one, lot };
		}
		/** Un renglón: título, de dónde salió, sus archivos y su estado. */
		function Row(props) {
			const { task, busy, onLaunch, onOpen, onDelete, onState, chosen } = props;
			const [open, setOpen] = useState(false);
			const target = task.sessionId ?? task.orchestratorSessionId;
			const current = STATES.find((item) => item.id === task.state) ?? STATES[0];
			const trigger = h("button", {
				type: "button", className: "brd-trigger brd-state", "data-open": String(open), "data-tone": statusOf(task).bad ? "bad" : undefined,
				onClick: () => setOpen((value) => !value), title: "Cambiar el estado",
			}, h("span", null, shownStatus(task)), glyph("chevron", 13));
			return h("div", { className: "brd-row" },
				h("div", { style: { display: "flex", gap: 9, minWidth: 0 } },
					parked(task) ? h("input", { type: "checkbox", className: "brd-check", checked: chosen, "aria-label": `Elegir ${nameOf(task)}`, onChange: props.onPick }) : null,
					h("div", { style: { minWidth: 0 } },
						h("p", { className: "brd-title" }, nameOf(task)),
						h("p", { className: "brd-where", title: task.workspace },
							`${task.workspaceName ?? task.workspace}${task.attachments?.length ? ` · ${task.attachments.length} archivo${task.attachments.length === 1 ? "" : "s"}` : ""}${task.openMs ? ` · guardada hace ${took(task.openMs)}` : ""}`),
						task.request ? h("p", { className: "brd-req" }, task.request) : null,
						task.attachments?.length ? h(Thumbs, { files: task.attachments, max: 4 }) : null)),
				h("div", { className: "brd-actions" },
					Menu
						? h(Menu, { open, anchor: trigger, selectedId: current.id, dense: true, align: "end", portal: true, items: STATES, onClose: () => setOpen(false), onSelect: (id) => { setOpen(false); onState(id); } })
						: trigger,
					parked(task) ? h("button", { type: "button", className: "brd-btn", onClick: onLaunch, disabled: busy, title: `Lanzar en ${task.workspace}` }, "Lanzar") : null,
					target ? h(Icon, { icon: "open", label: "Abrir conversación", onClick: () => onOpen(target) }) : null,
					h(Icon, { icon: "trash", label: "Borrar tarea", onClick: onDelete, disabled: busy })));
		}

		function BoardPanel(props) {
			useStyles();
			const get = (name) => (typeof props.get === "function" ? props.get(name) : props[name]);
			const launcher = useLauncher(get);
			const [data, setData] = useState({ tasks: [], workspaces: [], home: "" });
			const [query, setQuery] = useState("");
			const [group, setGroup] = useState("estado");
			const [sort, setSort] = useState("recientes");
			const [organize, setOrganize] = useState(false);
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
					// /workspaces es opcional: con la lista de tareas alcanza para pintar.
					const [all, spaces] = await Promise.all([api("/all"), api("/workspaces").catch(() => ({}))]);
					const tasks = all.tasks ?? [];
					const known = (spaces.workspaces ?? []).length ? spaces.workspaces : [...new Set(tasks.map((task) => task.workspace).filter(Boolean))].map((path) => ({ path, title: "" }));
					setData({ tasks, workspaces: known, home: spaces.home ?? "" });
					setWorkspace((current) => current || spaces.home || known[0]?.path || "");
					setError(null);
				} catch (cause) { setError(cause); }
			}, []);
			useEffect(() => {
				load();
				const timer = setInterval(load, 8000);
				return () => clearInterval(timer);
			}, [load]);

			const tasks = data.tasks;
			const count = (label) => tasks.filter((task) => shownStatus(task) === label).length;
			const chosen = tasks.filter((task) => picked.has(task.id) && parked(task));
			const needle = query.trim().toLowerCase();
			const found = needle
				? tasks.filter((task) => [nameOf(task), task.request, task.workspace, task.workspaceName, shownStatus(task)].join(" ").toLowerCase().includes(needle))
				: tasks;
			const sorted = found.slice().sort((a, b) => {
				if (sort === "titulo") return nameOf(a).localeCompare(nameOf(b), "es");
				if (sort === "estado") return ORDER.indexOf(shownStatus(a)) - ORDER.indexOf(shownStatus(b)) || (b.createdAt ?? 0) - (a.createdAt ?? 0);
				if (sort === "antiguas") return (a.createdAt ?? 0) - (b.createdAt ?? 0);
				return (b.createdAt ?? 0) - (a.createdAt ?? 0);
			});
			/** La clave del grupo: el nombre que se muestra arriba de cada bloque. */
			const bucket = (task) => {
				if (group === "estado") return shownStatus(task);
				if (group === "proyecto") return task.workspaceName ?? task.workspace;
				if (group === "sesion") return task.sessionId ? `Conversación ${String(task.sessionId).replace(/^session-/, "").slice(0, 8)}` : "Sin conversación";
				if (group === "dia") return new Date(Number(task.createdAt) || Date.now()).toLocaleDateString("es", { day: "2-digit", month: "short", year: "numeric" });
				if (group === "origen") return task.origin === "ui" ? "Creadas por vos" : task.origin === "import" ? "Importadas" : "Del agente";
				return "";
			};
			const sections = (() => {
				if (group === "none") return [{ name: "", list: sorted }];
				const map = new Map();
				for (const task of sorted) map.set(bucket(task), [...(map.get(bucket(task)) ?? []), task]);
				return [...map.entries()].map(([name, list]) => ({ name, list }));
			})();

			const addFiles = (list) => {
				const incoming = [...list].filter(Boolean);
				const next = incoming.filter((file) => file.size <= 512 * 1024 * 1024)
					.map((file) => ({ key: `${file.name}-${file.size}-${Date.now()}-${Math.random()}`, file, preview: /^image\//.test(file.type) ? URL.createObjectURL(file) : "" }));
				setFiles((current) => [...current, ...next].slice(0, 40));
				if (next.length < incoming.length) setError(new Error("Se saltearon archivos de más de 512 MB."));
			};
			const create = async () => {
				if (!workspace || !request.trim()) return;
				setBusy(true); setError(null);
				try {
					const created = await api("/create", { workspace, title: title.trim(), request });
					for (const item of files) await upload(created.task.id, item.file);
					setRequest(""); setTitle(""); setFiles([]); setFormOpen(false);
					await load();
				} catch (cause) { setError(cause); } finally { setBusy(false); }
			};
			const act = (work) => async () => {
				setBusy(true); setError(null);
				try { await work(); await load(); } catch (cause) { setError(cause); } finally { setBusy(false); }
			};
			const launch = (task) => act(async () => props.openSession?.(await launcher.one(task)))();
			const launchLot = () => act(async () => {
				const opened = await launcher.lot(chosen);
				setPicked(new Set());
				if (opened.length) props.openSession?.(opened[0]);
			})();
			const change = (task, state) => act(() => api("/update", { id: task.id, state }))();
			const remove = (task) => act(() => api("/delete", { id: task.id }))();
			const togglePick = (task) => (event) => setPicked((current) => {
				const next = new Set(current);
				if (event.target.checked) next.add(task.id); else next.delete(task.id);
				return next;
			});

			const field = (label, control) => h("div", { className: "brd-field" }, h("span", { className: "brd-label" }, label), control);
			const openPicker = () => document.getElementById("brd-file-input")?.click();
			const pickFiles = (event) => { addFiles([...(event.target.files ?? [])]); event.target.value = ""; };
			const drop = (event) => { event.preventDefault(); setOver(false); if (event.dataTransfer?.files?.length) addFiles(event.dataTransfer.files); };

			const form = h("div", { className: "brd-form" },
				field("Workspace", h("select", { className: "brd-select", value: workspace, onChange: (event) => setWorkspace(event.target.value) },
					data.workspaces.map((item) => h("option", { key: item.path, value: item.path }, item.title ? `${item.title} — ${item.path}` : item.path)))),
				field("Mensaje para el agente", h("textarea", { className: "brd-area", value: request, placeholder: "Qué hay que resolver, con el contexto que haga falta.", onChange: (event) => setRequest(event.target.value) })),
				field("Título corto (opcional)", h("input", { className: "brd-select", value: title, placeholder: "Si no ponés uno, se usa la primera línea del mensaje", onChange: (event) => setTitle(event.target.value) })),
				h("div", { className: "brd-field" },
					h("span", { className: "brd-label" }, "Archivos (imágenes, videos, PDFs, logs)"),
					h("div", {
						className: "brd-drop", role: "button", tabIndex: 0, "data-over": String(over), onClick: openPicker,
						onKeyDown: (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); openPicker(); } },
						onDragOver: (event) => { event.preventDefault(); setOver(true); },
						onDragLeave: () => setOver(false), onDrop: drop,
					}, over ? "Soltá los archivos acá" : "Arrastrá archivos acá o hacé clic para elegirlos"),
					h("input", { id: "brd-file-input", type: "file", multiple: true, style: { display: "none" }, onChange: pickFiles })),
				files.length ? h("div", { className: "brd-files" },
					files.map((item) => h("div", { className: "brd-file", key: item.key },
						item.preview ? h("img", { className: "brd-file-img", src: item.preview, alt: item.file.name }) : null,
						h("div", { className: "brd-file-body" }, h("span", { className: "brd-file-name", title: item.file.name }, item.file.name), h("span", { className: "brd-file-size" }, size(item.file.size))),
						h("button", { type: "button", className: "brd-icon", title: "Quitar archivo", "aria-label": `Quitar ${item.file.name}`, onClick: () => setFiles((current) => current.filter((entry) => entry.key !== item.key)) }, glyph("close", 13))))) : null,
				h("div", { style: { display: "flex", gap: 8, marginTop: 4 } },
					h("button", { type: "button", className: "brd-btn brd-btn--primary", onClick: create, disabled: busy || !request.trim() || !workspace }, busy ? "Guardando…" : "Guardar tarea"),
					h("button", { type: "button", className: "brd-btn", onClick: () => { setFormOpen(false); setRequest(""); setTitle(""); setFiles([]); } }, "Cancelar")));

			const organizeItems = [
				{ type: "label", id: "l-group", text: "Agrupar por" },
				...GROUPS.map((item) => ({ id: `g:${item.id}`, label: item.label })),
				{ type: "separator", id: "sep" },
				{ type: "label", id: "l-sort", text: "Ordenar por" },
				...SORTS.map((item) => ({ id: `s:${item.id}`, label: item.label })),
			];
			const organizeTrigger = h("button", { type: "button", className: "brd-trigger", "data-open": String(organize), onClick: () => setOrganize((value) => !value) },
				`${GROUPS.find((item) => item.id === group)?.label} · ${SORTS.find((item) => item.id === sort)?.label}`, glyph("chevron", 13));
			const organizeMenu = Menu
				? h(Menu, {
					open: organize, anchor: organizeTrigger, items: organizeItems, dense: true, align: "end", portal: true,
					selectedIds: [`g:${group}`, `s:${sort}`], onClose: () => setOrganize(false),
					onSelect: (id) => { setOrganize(false); if (id.startsWith("g:")) setGroup(id.slice(2)); if (id.startsWith("s:")) setSort(id.slice(2)); },
				})
				: organizeTrigger;
			const search = h("div", { className: "brd-search" },
				h("input", { type: "search", value: query, placeholder: "Buscar por título, pedido o proyecto", "aria-label": "Buscar tareas", onChange: (event) => setQuery(event.target.value) }));

			return h("div", { className: "brd-root" },
				h("div", { className: "brd-wrap" },
					h("div", { className: "brd-head" },
						h("div", { style: { minWidth: 0 } },
							h("h1", { className: "brd-h1" }, "Tareas"),
							h("p", { className: "brd-line" }, `${count("sin lanzar")} sin lanzar · ${count("en curso")} en curso · ${count("por revisar")} por revisar · ${count("abierta")} abiertas · ${count("fallada")} falladas · ${count("cerrada")} cerradas`)),
						h("button", { type: "button", className: "brd-btn brd-btn--primary", onClick: () => setFormOpen((open) => !open) }, "Nueva tarea")),
					formOpen ? form : null,
					h("div", { className: "brd-tools" },
						search, organizeMenu,
						chosen.length ? h("button", { type: "button", className: "brd-btn", onClick: launchLot, disabled: busy, title: "Un orquestador por workspace decide cuántos agentes abrir" }, busy ? "Lanzando…" : `Lanzar lote (${chosen.length})`) : null),
					error ? h("p", { className: "brd-error" }, error.message) : null,
					!tasks.length && !error ? h("p", { className: "brd-note" }, "No hay tareas: creá una con Nueva tarea y queda esperando a que la lances.") : null,
					tasks.length && !sorted.length ? h("p", { className: "brd-note" }, `Ninguna tarea coincide con “${query.trim()}”.`) : null,
					sections.map((section, index) => h("section", { className: "brd-group", key: `${section.name}-${index}` },
						section.name ? h("h2", { className: "brd-group-h" }, `${section.name} (${section.list.length})`) : null,
						h("div", { className: "brd-list" }, section.list.map((task) => h(Row, {
							key: task.id, task, busy, chosen: picked.has(task.id), onPick: togglePick(task),
							onLaunch: launch(task), onOpen: (id) => props.openSession?.(id), onDelete: remove(task), onState: (state) => change(task, state),
						})))))));
		}

		const BoardIcon = (props) => h("svg", { width: props?.size ?? 16, height: props?.size ?? 16, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
			h("rect", { x: 1.8, y: 1.8, width: 12.4, height: 12.4, rx: 3, stroke: "currentColor", strokeWidth: 1.3 }), h("path", { d: "M4.6 8.1l2 2 4.2-4.4", stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "round", strokeLinejoin: "round" }));

		function apply(ctx) {
			const get = (name) => (typeof ctx.get === "function" ? ctx.get(name) : ctx[name]);
			const openSession = (sessionId) => {
				const layout = get("layout");
				if (layout && typeof layout.selectPanel === "function") layout.selectPanel(null);
				const uiWorkspace = get("uiWorkspace");
				if (uiWorkspace && typeof uiWorkspace.openSession === "function") uiWorkspace.openSession(sessionId);
			};
			ctx.slots.inject("sidebar.panellist", () => ctx.slots.register({ name: "sidebar.panellist", id: PANEL_ID, order: 20, label: () => "Tareas" }, BoardIcon));
			ctx.slots.inject("main", () => ctx.slots.register({ name: "main", key: PANEL_ID, inject: () => ({ get, openSession }) }, BoardPanel));
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
