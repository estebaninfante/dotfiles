/**
 * dsh-local-evidence — client half.
 *
 * Dos piezas, las dos con evidencia real del log de la sesión:
 *   - Tarjeta sobre el compositor: la prueba visual del último pedido terminado,
 *     con un resumen corto de lo que hizo el agente y un selector para mirar
 *     la evidencia de cualquier otra tarea de la conversación.
 *   - Vista "Evidencia" al lado de Chat y Tareas: todas las tareas de la sesión,
 *     cada una con su resumen, sus capturas y sus entregables.
 *
 * El nombre de cada tarea es su objetivo (/tasks/* lo guarda en `goal`); el
 * título corto queda como respaldo cuando la tarea no declaró objetivo.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-evidence",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;
		const { useEffect, useState } = React;

		/** El menú real del harness da el estilo; si no está, la tarjeta sigue en texto. */
		let primitives = null;
		try {
			primitives = require("@deepseek-ai/dsh-client-ui-primitives");
		} catch (error) {
			primitives = null;
		}
		const Menu = primitives && typeof primitives.Menu === "function" ? primitives.Menu : null;
		/** Lo que el usuario puede declarar; el estado lo aplica /tasks/update. */
		const STATES = ["abierta", "por_revisar", "cerrada", "fallada", "cancelada"].map((id) => ({ id, label: id.replace("_", " ") }));
		const stateId = (task) => (STATES.some((item) => item.id === task?.state) ? task.state : task?.state === "resuelta" ? "cerrada" : "abierta");
		/** El tilde sigue al rótulo que se muestra, no al estado guardado. */
		const stateKey = (text, stored) => {
			const label = String(text ?? "").trim();
			if (label === "por revisar" || label === "por cerrar") return "por_revisar";
			if (label === "abierta" || label === "cerrada" || label === "fallada" || label === "cancelada") return label;
			return stateId({ state: stored });
		};

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const STYLE_ID = "dsh-local-evidence-style";
		const CSS = [
			// El reset del harness deja las imágenes sin ancho máximo: las del
			// mensaje se dibujan a tamaño natural y el borde del chat las recorta.
			"[data-chat-turn] img{max-width:100%;height:auto}",
			".evd-root{box-sizing:border-box;width:calc(100% - var(--dsh-composer-side-clearance,0px) - var(--dsh-composer-side-clearance,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px));max-width:calc(var(--dsh-composer-card-max-width,952px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px) - var(--dsh-composer-dock-inset,0px));border-radius:var(--dsw-radius-lg,16px);background:var(--dsw-specific-menu,#202226);box-shadow:var(--dsw-elevation-panel,0 10px 30px #0007);backdrop-filter:var(--dsw-menu-backdrop-filter,blur(20px));flex:none;margin:0 auto;overflow:hidden}",
			".evd-body{display:flex;flex-direction:column;padding:6px 12px}",
			".evd-head{display:flex;align-items:center;gap:8px;width:100%;min-width:0}",
			".evd-toggle{display:flex;align-items:center;gap:8px;flex:none;height:24px;margin-left:-4px;padding:0 4px;border:0;border-radius:6px;background:transparent;font:inherit;color:inherit;cursor:pointer}",
			".evd-toggle:hover{background:var(--dsw-alias-bg-layer-2,#1d2027)}",
			".evd-toggle:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".evd-lead{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-title{flex:none;font-size:13px;font-weight:500;line-height:24px;color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-chevron{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3);transition:transform .18s ease}.evd-chevron[data-open='true']{transform:rotate(180deg)}",
			".evd-pick{display:flex;align-items:center;gap:6px;flex:0 1 auto;min-width:0;max-width:min(520px,46ch);height:24px;padding:0 6px;margin-left:-2px;border:0;border-radius:6px;background:transparent;font:inherit;color:var(--dsw-alias-label-secondary,#b9b9c2);cursor:pointer}",
			".evd-pick:hover{background:var(--dsw-alias-bg-layer-2,#1d2027);color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-pick:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".evd-pick-name{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;line-height:20px}",
			".evd-caret{display:grid;place-items:center;flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-task{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:400;line-height:20px;color:var(--dsw-alias-label-secondary,#b9b9c2)}",
			".evd-progress{flex:1 1 auto;min-width:0;margin-left:auto;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-align:right;font-size:12px;font-weight:400;line-height:20px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-state{flex:none;height:22px;padding:0 6px 0 8px;display:inline-flex;align-items:center;gap:4px;border:1px solid transparent;border-radius:6px;background:transparent;color:var(--dsw-alias-label-tertiary,#9a9aa3);font:inherit;font-size:12px;line-height:1;cursor:pointer;white-space:nowrap}.evd-state:hover{color:var(--dsw-alias-label-primary,#ececf1);border-color:var(--dsw-alias-border-l2,#3b3e46)}.evd-state:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".evd-panel{max-height:320px;overflow-y:auto;margin-top:6px;padding-top:8px;border-top:1px solid var(--dsw-alias-border-l1,#2c2f36);--dsh-scrollbar-thumb:var(--dsw-alias-scrollbar-bg-l2)}",
			".evd-summary{margin:0 0 8px;font-size:12.5px;line-height:1.55;color:var(--dsw-alias-label-secondary,#b9b9c2);display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}",
			".evd-more{margin:6px 0 0;padding:0;border:0;background:transparent;font:400 12px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3);cursor:pointer;text-align:left}.evd-more:hover{color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-empty{margin:0;font-size:12.5px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-flash{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:6px;border-radius:10px}",
			".evd-steps{margin:0 0 8px;padding:0;list-style:none;display:flex;flex-direction:column;gap:1px}",
			".evd-steps li{position:relative;padding-left:13px;font:400 12px/1.55 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-steps li::before{content:'·';position:absolute;left:3px}",
			".evd-gallery{display:flex;flex-wrap:wrap;gap:6px}.evd-thumb{display:block;width:132px;height:82px;border-radius:6px;overflow:hidden;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:var(--dsw-alias-bg-layer-1,#16181c);cursor:zoom-in}.evd-thumb img{width:100%;height:100%;object-fit:contain;display:block}",
			".evd-thumb:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}.evd-video{width:212px;height:120px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:#000}",
			".evd-lightbox{border:0;padding:0;margin:auto;max-width:none;max-height:none;background:transparent;overflow:visible}.evd-lightbox::backdrop{background:#08090bd9;backdrop-filter:blur(2px)}",
			".evd-lightbox-img{max-width:94vw;max-height:88vh;border-radius:10px;box-shadow:0 24px 60px #000a;display:block}",
			".evd-lightbox-close{position:fixed;top:16px;right:18px;width:34px;height:34px;display:grid;place-items:center;border:0;border-radius:9px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);cursor:pointer}.evd-lightbox-close:hover{color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-lightbox-close:focus-visible,.evd-lightbox-more:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:2px}",
			".evd-lightbox-more{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);border:0;border-radius:7px;padding:6px 10px;background:transparent;color:var(--dsw-alias-label-tertiary,#9a9aa3);font:inherit;font-size:12px;cursor:pointer}.evd-lightbox-more:hover{color:var(--dsw-alias-label-primary,#ececf1)}",
			".evd-opt{display:flex;align-items:baseline;gap:10px;min-width:0;max-width:100%}",
			".evd-opt-name{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".evd-opt-state{flex:none;font-size:11.5px;line-height:16px;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".evd-menu{min-width:340px;max-width:min(620px,90vw)}",
			"@media (max-width:600px){.evd-pick{flex:1 1 auto;max-width:none}.evd-progress{display:none}}",
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

		/** Abre la pestaña Tareas, donde está toda la evidencia de la sesión. */
		function openTasksTab() {
			const tab = [...document.querySelectorAll("[role=tab]")].find((item) => item.innerText.trim() === "Tareas");
			if (tab) tab.click();
		}

		/**
		 * Lleva al mensaje que originó la tarea: abre Chat y, si hace falta, va
		 * cargando los mensajes viejos hasta encontrar ese turno.
		 */
		function jumpToTurn(turn, request = "") {
			const target = Number(turn);
			if (!Number.isSafeInteger(target) || target <= 0) return;
			const needle = String(request ?? "").replace(/\s+/g, " ").trim().slice(0, 40).toLowerCase();
			const chatTab = [...document.querySelectorAll("[role=tab]")].find((tab) => tab.innerText.trim() === "Chat");
			if (chatTab && chatTab.getAttribute("aria-selected") !== "true") chatTab.click();
			const scroller = () => {
				let node = document.querySelector("[data-chat-turn]");
				while (node) {
					const style = getComputedStyle(node);
					if (/(auto|scroll)/.test(style.overflowY) && node.scrollHeight > node.clientHeight + 40) return node;
					node = node.parentElement;
				}
				return null;
			};
			const pick = () => {
				const nodes = [...document.querySelectorAll(`[data-chat-turn="${target}"]`)];
				if (!nodes.length) return null;
				if (needle) {
					const match = nodes.find((node) => (node.innerText ?? "").replace(/\s+/g, " ").toLowerCase().includes(needle));
					if (match) return match;
				}
				return nodes.sort((a, b) => a.innerText.length - b.innerText.length)[0];
			};
			let tries = 0;
			const step = () => {
				tries += 1;
				const found = pick();
				if (found) {
					found.scrollIntoView({ block: "center", behavior: "smooth" });
					found.classList.add("evd-flash");
					setTimeout(() => found.classList.remove("evd-flash"), 2400);
					return;
				}
				const earlier = [...document.querySelectorAll("button")].find((button) => /load earlier|cargar anteriores/i.test(button.innerText));
				const box = scroller();
				if (!earlier || !box || tries > 30) return;
				box.scrollTop = 0;
				earlier.click();
				setTimeout(step, 700);
			};
			setTimeout(step, 120);
		}

		/** El nombre de la tarea es su objetivo; el título corto solo si no hay objetivo. */
		function nameOf(task) {
			// El nombre es el título que eligió el agente; el detalle va de apoyo.
			const title = String(task?.title ?? "").trim();
			if (title) return title;
			const goal = String(task?.goal ?? "").trim();
			return goal ? goal.slice(0, 72) : "Tarea sin título";
		}

		/** Un renglón de estado: lo que el host ya resolvió, sin inventar nada. */
		/** Los cinco estados vienen resueltos del servidor. */
		function stateOf(task) {
			const text = String(task?.status ?? "").trim();
			if (text) return text;
			if (task?.state === "cancelada" || task?.outcome === "cancelada") return "cancelada";
			if (task?.outcome === "falló") return "fallada";
			if (task?.state === "resuelta" || task?.outcome === "ok") return "cerrada";
			return "abierta";
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

		/** La imagen se abre acá adentro, no en otra pestaña del navegador. */
		function Gallery(props) {
			const media = (props.media ?? []).slice(0, props.max ?? 99);
			const [view, setView] = useState(null);
			const dialog = React.useRef(null);
			const current = view === null ? null : media[view] ?? null;
			/**
			 * El visor es un `<dialog>` modal: se abre en la capa de arriba del
			 * navegador. Un overlay `position:fixed` dentro de la tarjeta queda
			 * recortado por el panel del composer, que tiene su propio overflow.
			 */
			useEffect(() => {
				const node = dialog.current;
				if (!node) return;
				if (view === null) {
					if (node.open) node.close();
					return;
				}
				if (!node.open) node.showModal();
			}, [view]);
			const move = React.useCallback(
				(delta) => {
					if (view === null) return;
					setView((index) => (index + delta + media.length) % media.length);
				},
				[view, media.length],
			);
			useEffect(() => {
				if (view === null) return undefined;
				const onKey = (event) => {
					if (event.key === "Escape") setView(null);
					if (event.key === "ArrowRight") move(1);
					if (event.key === "ArrowLeft") move(-1);
				};
				window.addEventListener("keydown", onKey);
				return () => window.removeEventListener("keydown", onKey);
			}, [view, move]);
			return h(
				React.Fragment,
				null,
				h(
					"div",
					{ className: "evd-gallery", style: { marginTop: 8 } },
					media.map((item, index) =>
						item.kind === "video"
							? h("video", { key: item.path, className: "evd-video", controls: true, preload: "metadata", src: item.url })
							: h(
									"a",
									{
										key: item.path,
										className: "evd-thumb",
										href: item.url,
										title: item.label,
										onClick: (event) => {
											if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
											event.preventDefault();
											setView(index);
										},
									},
									h("img", { src: item.url, alt: item.label, loading: "lazy" }),
								),
					),
				),
				current
					? h(
							"dialog",
							{
								ref: dialog, className: "evd-lightbox", "aria-label": current.label ?? "Imagen de la evidencia",
								onClose: () => setView(null),
								onClick: (event) => {
									if (event.target === event.currentTarget) setView(null);
								},
							},
							h("img", {
								className: "evd-lightbox-img", src: current.url, alt: current.label ?? "",
								// Inline: ningún reset del harness puede volver a recortarla.
								style: { width: "auto", height: "auto", maxWidth: "94vw", maxHeight: "88vh", objectFit: "contain", display: "block" },
								onClick: (event) => event.stopPropagation(),
							}),
							h(
								"button",
								{ type: "button", className: "evd-lightbox-close", "aria-label": "Cerrar", onClick: () => setView(null) },
								h(
									"svg",
									{ width: 18, height: 18, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
									h("path", { d: "M4 4l8 8M12 4l-8 8", stroke: "currentColor", strokeWidth: 1.5, strokeLinecap: "round" }),
								),
							),
							media.length > 1
								? h(
										"button",
										{
											type: "button",
											className: "evd-lightbox-more",
											onClick: (event) => {
												event.stopPropagation();
												move(1);
											},
										},
										`${view + 1} / ${media.length}`,
									)
								: null,
						)
					: null,
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

		/** La tarea en curso de la sesión: aparece apenas el agente la nombra. */
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
				const timer = setInterval(load, 4000);
				return () => {
					cancelled = true;
					clearInterval(timer);
				};
			}, [sessionId]);
			return turn;
		}

		/** Todas las tareas de la conversación, cada una con su evidencia y su objetivo. */
		function useSessionTasks(sessionId) {
			const [tasks, setTasks] = useState([]);
			useEffect(() => {
				if (!sessionId) {
					setTasks([]);
					return undefined;
				}
				let cancelled = false;
				const load = () => {
					Promise.all([getJson(`/tasks/session?session=${encodeURIComponent(sessionId)}`), getJson("/tasks/all")])
						.then(([session, all]) => {
							if (cancelled) return;
							const goals = new Map(((all && all.tasks) || []).map((task) => [task.id, String(task.goal ?? "")]));
							const items = ((session && session.tasks) || []).map((item) => ({ ...item, goal: goals.get(item.id) ?? "" }));
							setTasks(items);
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
			return tasks;
		}

		function EvidenceCard(props) {
			useStyles();
			const proof = useTurnEvidence(props.sessionId);
			const tasks = useSessionTasks(props.sessionId);
			const [open, setOpen] = useState(false);
			const [menuOpen, setMenuOpen] = useState(false);
			const [pickedId, setPickedId] = useState("auto");
			const [stateOpen, setStateOpen] = useState(false);
			const [localState, setLocalState] = useState(null);

			// Otra conversación = otra lista de tareas: el selector vuelve al último paso.
			useEffect(() => {
				setPickedId("auto");
				setMenuOpen(false);
			}, [props.sessionId]);

			const picked = pickedId === "auto" ? null : tasks.find((item) => item.id === pickedId) ?? null;
			// Con "auto" la tarjeta muestra el último pedido terminado; el menú marca ese renglón.
			const latestId = String(proof?.task?.id ?? "");
			const latest = latestId ? tasks.find((item) => item.id === latestId) ?? null : null;
			const selectedId = picked ? picked.id : latest?.id ?? "auto";
			const media = picked ? picked.media ?? [] : proof?.evidence?.media ?? [];
			const deliverables = picked ? picked.deliverables ?? [] : proof?.evidence?.deliverables ?? [];
			const summary = picked ? String(picked.summary ?? "").trim() : String(proof?.summary ?? "").trim();
			const task = picked ?? proof?.task ?? null;
			const remote = picked ? stateOf(picked) : proof?.status ?? null;
			// El cambio se ve al instante; el poll de 15 s confirma lo que guardó el host.
			const status = localState && task?.id === localState.id ? localState.text : remote;
			const name = task ? nameOf(task) : "Esta sesión";

			if (!proof && !picked) return null;
			// La tarjeta aparece apenas la tarea tiene nombre, aunque todavía no haya
			// prueba visual: se ve qué se está trabajando y en qué estado está.
			if (!picked && !media.length && !deliverables.length && !proof?.task) return null;

			const counts = [
				media.length ? `${media.length} ${media.length === 1 ? "prueba visual" : "pruebas visuales"}` : null,
				deliverables.length ? `${deliverables.length} ${deliverables.length === 1 ? "entregable" : "entregables"}` : null,
			].filter(Boolean);

			const items = tasks.map((item) => ({
				id: item.id,
				label: h(
					"span",
					{ className: "evd-opt" },
					h("span", { className: "evd-opt-name", title: nameOf(item) }, nameOf(item)),
					h("span", { className: "evd-opt-state" }, stateOf(item)),
				),
			}));

			const picker = h(
				"button",
				{
					type: "button",
					className: "evd-pick",
					"aria-haspopup": "menu",
					"aria-expanded": menuOpen,
					title: tasks.length > 1 ? `Ver la evidencia de otra tarea · ${name}` : name,
					onClick: () => {
						if (tasks.length > 1) setMenuOpen((value) => !value);
					},
				},
				h("span", { className: "evd-pick-name" }, name),
				h(
					"span",
					{ className: "evd-caret" },
					h(
						"svg",
						{ width: 12, height: 12, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
						h("path", { d: "M5 6.5L8 9.5l3-3", stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round" }),
					),
				),
			);

			return h(
				"div",
				{ className: "evd-root" },
				h(
					"div",
					{ className: "evd-body" },
					h(
						"div",
						{ className: "evd-head" },
						h(
							"button",
							{ type: "button", className: "evd-toggle", "aria-expanded": open, onClick: () => setOpen((value) => !value) },
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
							h("span", { className: "evd-title" }, "Tareas"),
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
						tasks.length > 1 && Menu
							? h(Menu, {
									open: menuOpen,
									anchor: picker,
									items,
									selectedId,
									side: "top",
									align: "start",
									dense: true,
									portal: true,
									listClassName: "evd-menu",
									onSelect: (id) => {
										setPickedId(id);
										setMenuOpen(false);
										setOpen(true);
										// Cambiar de tarea te lleva al mensaje que la originó.
										const chosen = tasks.find((item) => item.id === id);
										if (chosen?.turn) jumpToTurn(chosen.turn, chosen.request);
									},
									onClose: () => setMenuOpen(false),
								})
							: h("span", { className: "evd-task", title: name }, name),
						counts.length ? h("span", { className: "evd-progress" }, counts.join(" · ")) : null,
						task && status
							? h(Menu, {
									open: stateOpen,
									anchor: h(
										"button",
										{
											type: "button", className: "evd-state", "aria-haspopup": "menu", "aria-expanded": stateOpen,
											title: "Cambiar el estado de la tarea", onClick: () => setStateOpen((value) => !value),
										},
										h("span", null, status),
										h(
											"svg",
											{ width: 12, height: 12, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
											h("path", { d: "M4.5 6.5L8 10l3.5-3.5", stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round" }),
										),
									),
									items: STATES,
									selectedId: stateId(task),
									side: "top",
									align: "end",
									dense: true,
									portal: true,
									listClassName: "evd-menu",
									onClose: () => setStateOpen(false),
									onSelect: (id) => {
										setStateOpen(false);
										setLocalState({ id: task.id, text: id.replace("_", " ") });
										fetch("/tasks/update", {
											method: "POST",
											headers: { "content-type": "application/json", "x-dsh-tasks": "1" },
											body: JSON.stringify({ id: task.id, state: id }),
										}).catch(() => {});
									},
								})
							: status ? h("span", { className: "evd-state" }, status) : null,
					),
					open
						? h(
								"div",
								{ className: "evd-panel" },
								summary ? h("p", { className: "evd-summary" }, summary) : null,
								task?.steps?.length
									? h("ul", { className: "evd-steps" }, task.steps.map((step) => h("li", { key: step }, step)))
									: null,
								media.length ? h(Gallery, { media, max: 12 }) : null,
								media.length > 12
									? h(
											"button",
											{ type: "button", className: "evd-more", onClick: () => openTasksTab() },
											`+${media.length - 12} más en la pestaña Tareas`,
										)
									: null,
								media.length || deliverables.length
									? h("button", { type: "button", className: "evd-more", onClick: () => openTasksTab() }, "Ver todas en Tareas")
									: null,
								deliverables.length ? h(Deliverables, { items: deliverables.slice(0, 3) }) : null,
								!media.length && !deliverables.length
									? h("p", { className: "evd-empty" }, status === "en curso" ? "La tarea está en curso: la prueba visual aparece al terminar." : "Este paso no dejó prueba visual todavía.")
									: null,
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
