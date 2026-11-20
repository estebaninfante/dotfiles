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
			".tsk-tools{display:flex;align-items:center;gap:4px;flex-wrap:wrap;margin-top:12px}",
			".tsk-tools-label{margin-right:2px;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-btn[data-active='true']{color:var(--dsw-alias-label-primary,#ececf1);border-color:var(--dsw-alias-border-l2,#3b3e46)}",
			".tsk-restart{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:12px 0;border-top:1px solid var(--dsw-alias-border-l1,#2c2f36)}",
			".tsk-restart-title{margin:0;font-size:13px;line-height:1.5;color:var(--dsw-alias-label-primary,#ececf1)}",
			".tsk-restart-hint{margin:2px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-list{display:flex;flex-direction:column;gap:8px;padding-top:10px}",
			".tsk-card{display:flex;flex-direction:column;gap:6px;padding:13px 15px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:12px;background:var(--dsw-alias-bg-layer-2,#1d2027);transition:border-color .12s ease}.tsk-card:hover{border-color:var(--dsw-alias-border-l2,#3b3e46)}",
			".tsk-row{display:flex;align-items:center;gap:14px;justify-content:space-between}",
			".tsk-title{margin:0;font-size:13.5px;font-weight:500;line-height:1.45;color:var(--dsw-alias-label-primary,#ececf1);overflow-wrap:anywhere;text-wrap:pretty}",
			".tsk-side{display:flex;align-items:center;gap:2px;flex:none}",
			".tsk-state{font-size:12px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap;margin-right:6px}.tsk-state[data-tone='bad']{color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".tsk-chevron{display:grid;place-items:center;color:var(--dsw-alias-label-tertiary,#9a9aa3);transition:transform .18s ease}.tsk-chevron[data-closed='false']{transform:rotate(180deg)}.tsk-toggle:hover .tsk-chevron{color:var(--dsw-alias-label-primary,#ececf1)}",
			".tsk-time{margin:2px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-steps{margin:2px 0 0;padding:0;list-style:none;display:flex;flex-direction:column;gap:1px}",
			".tsk-steps li{position:relative;padding-left:13px;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-steps li::before{content:'·';position:absolute;left:3px}",
			".tsk-lightbox{position:fixed;inset:0;z-index:80;display:grid;place-items:center;padding:28px;background:#08090bd9;backdrop-filter:blur(2px)}",
			".tsk-lightbox-img{max-width:94vw;max-height:88vh;border-radius:10px;box-shadow:0 24px 60px #000a;display:block}",
			".tsk-lightbox-close{position:fixed;top:16px;right:18px;width:34px;height:34px;display:grid;place-items:center;border:0;border-radius:9px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);cursor:pointer}.tsk-lightbox-close:hover{color:var(--dsw-alias-label-primary,#ececf1)}",
			".tsk-lightbox-close:focus-visible,.tsk-lightbox-more:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:2px}",
			".tsk-lightbox-more{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);border:0;border-radius:7px;padding:6px 10px;background:transparent;color:var(--dsw-alias-label-tertiary,#9a9aa3);font:inherit;font-size:12px;cursor:pointer}.tsk-lightbox-more:hover{color:var(--dsw-alias-label-primary,#ececf1)}",
			".tsk-flash{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:6px;border-radius:10px}",
			".tsk-summary{margin:0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-secondary,#b9b9c2);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}",
			".tsk-gallery{display:flex;flex-wrap:wrap;gap:6px;margin:2px 0 0}.tsk-thumb{display:block;width:118px;height:74px;border-radius:6px;overflow:hidden;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:var(--dsw-alias-bg-layer-1,#16181c)}.tsk-thumb img{width:100%;height:100%;object-fit:cover;display:block}.tsk-thumb:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".tsk-video{width:198px;height:112px;border-radius:6px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);background:#000}",
			".tsk-icon{width:28px;height:28px;border:0;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);display:grid;place-items:center;cursor:pointer}.tsk-icon:hover{color:var(--dsw-alias-label-primary,#ececf1)}.tsk-icon[disabled]{opacity:.45;cursor:default}",
			".tsk-file{display:flex;align-items:center;gap:7px;margin:1px -6px;padding:5px 6px;border-radius:7px;text-decoration:none;color:var(--dsw-alias-label-primary,#e9e9ee)}.tsk-file:hover{background:var(--dsw-alias-bg-layer-2,#1d2027)}.tsk-file:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".tsk-file-icon{flex:none;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-file-name{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:400 12.5px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif}",
			".tsk-file-desc{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:400 12px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".tsk-turn{font-size:12px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap;margin-right:6px}",
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

		/** Sube el archivo en crudo y lo ata a la tarea. */
		async function uploadFile(taskId, file) {
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

		function sizeText(bytes) {
			const value = Number(bytes);
			if (!Number.isFinite(value) || value <= 0) return "";
			if (value < 1024) return `${value} B`;
			if (value < 1024 * 1024) return `${Math.round(value / 1024)} KB`;
			return `${(value / 1024 / 1024).toFixed(value < 10 * 1024 * 1024 ? 1 : 0)} MB`;
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

		/** Los estados vienen resueltos del servidor: abierta, en curso, por revisar, cerrada, fallada, cancelada. */
		function statusOf(task) {
			const text = String(task?.status ?? "").trim();
			const bad = text === "fallada" || task?.outcome === "falló";
			if (text) return { text, bad };
			if (task?.state === "cancelada") return { text: "cancelada", bad: false };
			if (task?.outcome === "falló") return { text: "fallada", bad: true };
			// Terminó el agente: queda por revisar. Solo el usuario la cierra.
			if (task?.state === "cerrada" || task?.state === "resuelta") return { text: "cerrada", bad: false };
			if (task?.state === "por_revisar" || task?.outcome === "ok") return { text: "por revisar", bad: false };
			return { text: "abierta", bad: false };
		}

		/** Qué turno(s) de la conversación trabaja esta tarea. */
		function turnLabel(task) {
			const turns = Array.isArray(task.turns) && task.turns.length ? task.turns : task.turn ? [task.turn] : [];
			if (!turns.length) return "";
			if (turns.length === 1) return `turno ${turns[0]}`;
			return `turnos ${turns[0]}–${turns[turns.length - 1]}`;
		}

		/** Duración en palabras: 3 min, 2 h 15 min, 3 d. */
		function took(ms) {
			const value = Number(ms);
			if (!Number.isFinite(value) || value <= 0) return "";
			const minutes = Math.round(value / 60000);
			if (minutes < 1) return "menos de 1 min";
			if (minutes < 60) return `${minutes} min`;
			const hours = Math.floor(minutes / 60);
			if (hours < 24) return minutes % 60 ? `${hours} h ${minutes % 60} min` : `${hours} h`;
			const days = Math.floor(hours / 24);
			return `${days} d ${hours % 24} h`;
		}

		/** Cuánto lleva abierta y cuánto se trabajó en ella. */
		function timeLabel(task, status = "") {
			const worked = took(task.workedMs);
			const open = took(task.openMs);
			// Una tarea terminada no "lleva abierta": se informa solo lo trabajado.
			const closed = status === "cerrada" || status === "fallada" || status === "cancelada";
			const parts = [];
			if (!closed && open) parts.push(`abierta hace ${open}`);
			if (worked) parts.push(`trabajada ${worked}`);
			return parts.join(" · ");
		}

		/**
		 * Las imágenes se abren acá adentro, no en otra pestaña del navegador. Con
		 * Ctrl+clic o clic del medio sigue abriendo la pestaña de siempre.
		 */
		function Gallery(props) {
			const items = (props.items ?? []).slice(0, props.max ?? 8);
			const [view, setView] = useState(null);
			const current = view === null ? null : items[view] ?? null;
			const move = React.useCallback(
				(delta) => {
					if (view === null) return;
					setView((index) => (index + delta + items.length) % items.length);
				},
				[view, items.length],
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
					{ className: "tsk-gallery" },
					items.map((item, index) =>
						item.kind === "video"
							? h("video", { key: item.path, className: "tsk-video", controls: true, preload: "metadata", src: item.url })
							: h(
									"a",
									{
										key: item.path,
										className: "tsk-thumb",
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
							"div",
							{ className: "tsk-lightbox", role: "dialog", "aria-modal": "true", "aria-label": current.label ?? "Imagen de la evidencia", onClick: () => setView(null) },
							h("img", { className: "tsk-lightbox-img", src: current.url, alt: current.label ?? "", onClick: (event) => event.stopPropagation() }),
							h(
								"button",
								{ type: "button", className: "tsk-lightbox-close", "aria-label": "Cerrar", onClick: () => setView(null) },
								h(
									"svg",
									{ width: 18, height: 18, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
									h("path", { d: "M4 4l8 8M12 4l-8 8", stroke: "currentColor", strokeWidth: 1.5, strokeLinecap: "round" }),
								),
							),
							items.length > 1
								? h(
										"button",
										{
											type: "button",
											className: "tsk-lightbox-more",
											onClick: (event) => {
												event.stopPropagation();
												move(1);
											},
										},
										`${view + 1} / ${items.length}`,
									)
								: null,
						)
					: null,
			);
		}

		/** El entregable se ve como archivo, con su nombre, no con su ruta. */
		function fileName(file) {
			const name = String(file?.name ?? "").trim();
			if (name) return name;
			const path = String(file?.path ?? "");
			return path.split("/").filter(Boolean).pop() ?? "archivo";
		}

		function fileIcon() {
			return h(
				"svg",
				{ width: 14, height: 14, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none", className: "tsk-file-icon" },
				h("path", {
					d: "M9 1.8H4.6A1.6 1.6 0 0 0 3 3.4v9.2a1.6 1.6 0 0 0 1.6 1.6h6.8a1.6 1.6 0 0 0 1.6-1.6V5.2L9 1.8Z",
					stroke: "currentColor",
					strokeWidth: 1.2,
					strokeLinejoin: "round",
				}),
				h("path", { d: "M9 1.9v3.4h3.9", stroke: "currentColor", strokeWidth: 1.2, strokeLinejoin: "round" }),
			);
		}

		function Deliverables(props) {
			return h(
				React.Fragment,
				null,
				(props.items ?? []).map((file) =>
					h(
						"a",
						{ className: "tsk-file", key: file.path, href: `/api/file?path=${encodeURIComponent(file.path)}`, target: "_blank", rel: "noreferrer" },
						fileIcon(),
						h("span", { className: "tsk-file-name" }, fileName(file)),
						file.description ? h("span", { className: "tsk-file-desc" }, file.description) : null,
					),
				),
			);
		}

		function Action(props) {
			const path =
				props.icon === "check"
					? "M3.5 8.2l3 3 6-6.4"
					: props.icon === "jump"
						? "M4.5 11.5l7-7M6.5 4.5h5v5"
						: "M4 8a4 4 0 1 0 1.2-2.9M4 3.2v2.6h2.6";
			return h(
				"button",
				{ type: "button", className: "tsk-icon", title: props.label, "aria-label": props.label, onClick: props.onClick, disabled: props.disabled },
				h("svg", { width: 15, height: 15, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" }, h("path", {
					d: path,
					stroke: "currentColor",
					strokeWidth: 1.4,
					strokeLinecap: "round",
					strokeLinejoin: "round",
				})),
			);
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
			// El turno puede estar en varios nodos: se busca el del mensaje del usuario.
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
					found.classList.add("tsk-flash");
					setTimeout(() => found.classList.remove("tsk-flash"), 2400);
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

		/** El nombre de la tarea es el título que eligió el agente. */
		function nameOf(task) {
			const title = String(task?.title ?? "").trim();
			if (title) return title;
			const goal = String(task?.goal ?? "").trim();
			return goal ? goal.slice(0, 72) : "Tarea sin título";
		}

		function TaskCard(props) {
			const { task, onChange, busy, collapsed, onToggle } = props;
			const status = statusOf(task);
			const turns = turnLabel(task);
			return h(
				"div",
				{ className: "tsk-card" },
				h(
					"div",
					{ className: "tsk-row" },
					h("span", { className: "tsk-title", title: nameOf(task) }, nameOf(task)),
					h(
						"div",
						{ className: "tsk-side" },
						turns ? h("span", { className: "tsk-turn" }, turns) : null,
						h("span", { className: "tsk-state", "data-tone": status.bad ? "bad" : undefined }, status.text),
						task.turn ? h(Action, { icon: "jump", label: "Ir al mensaje que originó la tarea", onClick: () => jumpToTurn(task.turn, task.request) }) : null,
						task.state === "cerrada" || task.state === "cancelada"
							? h(Action, { icon: "undo", label: "Reabrir tarea", onClick: () => onChange(task, "abierta"), disabled: busy })
							: h(Action, { icon: "check", label: "Cerrar tarea", onClick: () => onChange(task, "cerrada"), disabled: busy }),
						h(
							"button",
							{ type: "button", className: "tsk-icon tsk-toggle", "aria-expanded": collapsed ? "false" : "true", title: collapsed ? "Expandir tarea" : "Colapsar tarea", onClick: onToggle },
							h(
								"span",
								{ className: "tsk-chevron", "data-closed": collapsed ? "true" : "false" },
								h(
									"svg",
									{ width: 14, height: 14, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
									h("path", { d: "M4.5 6.5L8 10l3.5-3.5", stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round" }),
								),
							),
						),
					),
				),
				collapsed
					? null
					: h(
							React.Fragment,
							null,
							timeLabel(task, status.text) ? h("p", { className: "tsk-time" }, timeLabel(task, status.text)) : null,
							task.summary ? h("p", { className: "tsk-summary" }, task.summary) : null,
							task.steps?.length ? h("ul", { className: "tsk-steps" }, task.steps.map((step) => h("li", { key: step }, step))) : null,
							task.note ? h("p", { className: "tsk-note" }, task.note) : null,
							task.attachments?.length
								? h(
										"div",
										{ className: "tsk-gallery" },
										task.attachments.map((file) =>
											file.kind === "image"
												? h("a", { key: file.path, className: "tsk-thumb", href: fileUrl(file.path), target: "_blank", rel: "noreferrer", title: file.name },
														h("img", { src: fileUrl(file.path), alt: file.name, loading: "lazy" }))
												: h("a", { key: file.path, className: "tsk-file", href: fileUrl(file.path, true), title: `${file.name} · ${sizeText(file.size)}` },
														fileIcon(), h("span", { className: "tsk-file-name" }, file.name)),
										),
									)
								: null,
							task.media?.length ? h(Gallery, { items: task.media }) : null,
							h(Deliverables, { items: task.deliverables ?? [] }),
						),
			);
		}

		/** Ajustes → reiniciar el harness. El servidor tarda unos segundos en volver. */
		function RestartRow() {
			useStyles();
			const [state, setState] = useState("idle");
			const restart = async () => {
				setState("busy");
				try {
					await api("/restart", {});
					setState("done");
					setTimeout(() => setState("idle"), 6000);
				} catch (cause) {
					setState("error");
					setTimeout(() => setState("idle"), 5000);
				}
			};
			const hint =
				state === "done"
					? "Reiniciando: cuando vuelva, recargá la página."
					: state === "error"
						? "No se pudo reiniciar desde acá. Usá `dsh-web --restart` en la terminal."
						: "Aplica cambios del host sin abrir la terminal.";
			return h(
				"div",
				{ className: "tsk-restart" },
				h(
					"div",
					{ className: "tsk-restart-text" },
					h("p", { className: "tsk-restart-title" }, "Reiniciar el harness"),
					h("p", { className: "tsk-restart-hint" }, hint),
				),
				h(
					"button",
					{ type: "button", className: "tsk-btn", onClick: restart, disabled: state === "busy" },
					state === "busy" ? "Reiniciando…" : "Reiniciar",
				),
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
			const [titleDraft, setTitleDraft] = useState("");
			const [files, setFiles] = useState([]);
			const [justSaved, setJustSaved] = useState("");
			const [collapsed, setCollapsed] = useState(() => new Set());
			const [order, setOrder] = useState("nuevas");
			const [grouped, setGrouped] = useState(false);

			const load = React.useCallback(async () => {
				try {
					const [session, all] = await Promise.all([api(`/session?session=${encodeURIComponent(sessionId)}`), api("/all")]);
					const goals = new Map(((all && all.tasks) || []).map((task) => [task.id, String(task.goal ?? "")]));
					setData({ ...session, tasks: (session.tasks ?? []).map((item) => ({ ...item, goal: goals.get(item.id) ?? "" })) });
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
			const count = (label) => tasks.filter((task) => statusOf(task).text === label).length;
			const abiertas = count("abierta");
			const fallos = count("fallada");
			const canceladas = count("cancelada");
			const cerradas = count("cerrada");
			const porRevisar = count("por revisar");
			// Orden y agrupado elegidos por el usuario, como en la lista de sesiones.
			const sorted = tasks.slice().sort((a, b) => {
				if (grouped) {
					const rank = (task) => ["en curso", "por revisar", "abierta", "fallada", "cancelada", "cerrada"].indexOf(statusOf(task).text);
					if (rank(a) !== rank(b)) return rank(a) - rank(b);
				}
				if (order === "viejas") return (a.turn ?? 0) - (b.turn ?? 0);
				if (order === "trabajo") return (b.workedMs ?? 0) - (a.workedMs ?? 0);
				return (b.turn ?? 0) - (a.turn ?? 0);
			});

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

			const create = async (thenLaunch) => {
				if (!cwd || !draft.trim()) return;
				setBusy(true);
				try {
					const created = await api("/create", { workspace: cwd, title: titleDraft.trim(), request: draft });
					for (const item of files) await uploadFile(created.task.id, item.file);
					setDraft("");
					setTitleDraft("");
					setFiles([]);
					setFormOpen(false);
					if (thenLaunch) navigate(await createConversation(created.task, cwd));
					else {
						setJustSaved(`Guardada sin lanzar: la vas a encontrar en Tareas (sidebar) para lanzarla cuando quieras.`);
						await load();
					}
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
							h("p", { className: "tsk-line" }, `${abiertas} abiertas · ${porRevisar} por revisar · ${fallos} con fallos · ${canceladas} canceladas · ${cerradas} cerradas`),
						),
						cwd ? h("button", { type: "button", className: "tsk-btn tsk-btn--primary", onClick: () => setFormOpen((open) => !open) }, "Nueva tarea") : null,
						h(
							"button",
							{
								type: "button",
								className: "tsk-btn",
								title: "Reiniciar el harness para aplicar cambios del host",
								onClick: async () => {
									try {
										await api("/restart", {});
										setError(null);
									} catch (cause) {
										setError(cause);
									}
								},
							},
							"Reiniciar",
						),
					),
					h(
						"div",
						{ className: "tsk-tools" },
						h("span", { className: "tsk-tools-label" }, "Ordenar"),
						...[
							["nuevas", "Recientes"],
							["viejas", "Viejas"],
							["trabajo", "Trabajo"],
						].map(([id, label]) =>
							h("button", {
								type: "button",
								key: id,
								className: "tsk-btn",
								"data-active": String(order === id),
								onClick: () => setOrder(id),
							}, label),
						),
						h("button", {
							type: "button",
							className: "tsk-btn",
							"data-active": String(grouped),
							title: "Agrupar por estado",
							onClick: () => setGrouped((value) => !value),
						}, grouped ? "Agrupadas" : "Agrupar"),
					),
					cwd && formOpen
						? h(
								"div",
								{ className: "tsk-form" },
								h("textarea", {
									className: "tsk-input",
									style: { minHeight: 96, resize: "vertical", lineHeight: 1.55 },
									value: draft,
									autoFocus: true,
									placeholder: "Qué hay que resolver, con el contexto que haga falta",
									onChange: (event) => setDraft(event.target.value),
								}),
								h("input", {
									className: "tsk-input",
									value: titleDraft,
									placeholder: "Título corto (opcional)",
									onChange: (event) => setTitleDraft(event.target.value),
								}),
								h("div", { style: { display: "flex", gap: 8, alignItems: "center", marginBottom: 10, flexWrap: "wrap" } },
									h("button", { type: "button", className: "tsk-btn", onClick: () => document.getElementById("tsk-file-input")?.click() }, "Adjuntar archivos"),
									h("input", {
										id: "tsk-file-input",
										type: "file",
										multiple: true,
										style: { display: "none" },
										onChange: (event) => {
											const list = [...(event.target.files ?? [])].filter((file) => file.size <= 512 * 1024 * 1024);
											setFiles((current) => [...current, ...list.map((file) => ({ key: `${file.name}-${file.size}-${Math.random()}`, file }))].slice(0, 40));
											event.target.value = "";
										},
									}),
									h("span", { className: "tsk-line", style: { margin: 0 } }, files.length ? `${files.length} archivo${files.length === 1 ? "" : "s"}` : "imágenes, videos, PDFs, logs"),
								),
								files.length
									? h("div", { style: { display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 10 } },
											files.map((item) =>
												h("span", { key: item.key, style: { display: "inline-flex", alignItems: "center", gap: 6, padding: "3px 6px", border: "1px solid var(--dsw-alias-border-l1,#2c2f36)", borderRadius: 6, fontSize: 12, color: "var(--dsw-alias-label-secondary,#b9b9c2)" } },
													h("span", { style: { maxWidth: 180, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } }, item.file.name),
													h("span", { className: "tsk-line", style: { margin: 0 } }, sizeText(item.file.size)),
													h("button", { type: "button", className: "tsk-icon", title: "Quitar archivo", onClick: () => setFiles((current) => current.filter((entry) => entry.key !== item.key)) }, "×"))))
									: null,
								h("div", { style: { display: "flex", gap: 8 } },
									h("button", { type: "button", className: "tsk-btn tsk-btn--primary", onClick: () => create(false), disabled: busy || !draft.trim() }, "Guardar"),
									h("button", { type: "button", className: "tsk-btn", onClick: () => create(true), disabled: busy || !draft.trim() }, "Guardar y lanzar"),
									h("button", { type: "button", className: "tsk-btn", onClick: () => { setFormOpen(false); setDraft(""); setTitleDraft(""); setFiles([]); } }, "Cancelar"),
								),
							)
						: null,
					justSaved ? h("p", { className: "tsk-line", style: { marginTop: 10 } }, justSaved) : null,
					error ? h("p", { className: "tsk-error" }, error.message) : null,
					tasks.length
						? h(
								"div",
								{ className: "tsk-list" },
								sorted.map((task) =>
									h(TaskCard, {
										key: task.id,
										task,
										onChange: change,
										busy,
										collapsed: collapsed.has(task.id),
										onToggle: () => setCollapsed((prev) => {
											const next = new Set(prev);
											if (next.has(task.id)) next.delete(task.id);
											else next.add(task.id);
											return next;
										}),
									}),
								),
							)
						: null,
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
				await api("/update", { id: task.id, sessionId, state: "abierta", launchedAt: Date.now() }).catch(() => {});
				const lines = [`Tarea: ${nameOf(task)}`, `Carpeta: ${cwd}`];
				if (task.request) lines.push("", task.request);
				const attached = task.attachments ?? [];
				if (attached.length) lines.push("", "Archivos del pedido:", ...attached.map((file) => `- ${file.path} (${file.name})`));
				lines.push("", "Al terminar, cerrá con la prueba visual real: captura de la app o video, rutas de archivos y resultado de los tests. Sin captura no hay evidencia visible.");
				const text = lines.join("\n");
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
			// Ajustes: reiniciar el harness sin salir a la terminal.
			ctx.slots.inject("settings.general.item", () =>
				ctx.slots.register({ name: "settings.general.item", id: "local-restart", order: 80 }, RestartRow),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
