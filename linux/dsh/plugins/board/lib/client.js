/**
 * dsh-local-board — client half.
 *
 * Panel "Tareas" en el sidebar: todas las tareas de todas las conversaciones,
 * con su estado (abierta, ok, parcial, falló, resuelta) y el acceso a la
 * conversación donde se trabajó. Datos: /tasks/all de dsh-local-tasks.
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
			".brd-wrap{max-width:820px;margin:0 auto;padding:30px 32px 80px}",
			".brd-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px}",
			".brd-h1{margin:0;font-size:18px;font-weight:550;letter-spacing:-.01em;color:var(--dsw-alias-label-primary,#ececf1)}",
			".brd-line{margin:6px 0 0;font-size:12px;line-height:1.5;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".brd-filters{display:flex;gap:6px;margin:16px 0 4px;flex-wrap:wrap}",
			".brd-filter{height:26px;padding:0 10px;border:1px solid transparent;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);font:inherit;font-size:12px;cursor:pointer}",
			".brd-filter:hover{color:var(--dsw-alias-label-primary,#ececf1)}",
			".brd-filter[data-active='true']{border-color:var(--dsw-alias-border-l2,#3b3e46);color:var(--dsw-alias-label-primary,#ececf1)}",
			".brd-filter:focus-visible,.brd-icon:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".brd-section{margin:20px 0 2px;font:500 12px/1.4 system-ui,-apple-system,'Segoe UI',sans-serif;letter-spacing:.05em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			".brd-list{display:flex;flex-direction:column;gap:8px;padding-top:8px}",
			".brd-row{display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:center;gap:6px 14px;padding:12px 14px;border:1px solid var(--dsw-alias-border-l1,#2c2f36);border-radius:12px;background:var(--dsw-alias-bg-layer-2,#1d2027);transition:border-color .12s ease}.brd-row:hover{border-color:var(--dsw-alias-border-l2,#3b3e46)}",
			".brd-title{margin:0;font-size:13.5px;font-weight:500;line-height:1.45;color:var(--dsw-alias-label-primary,#ececf1);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".brd-where{margin:2px 0 0;font-size:12px;line-height:1.45;color:var(--dsw-alias-label-tertiary,#9a9aa3);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
			".brd-actions{display:flex;align-items:center;gap:2px;justify-content:flex-end}",
			".brd-state{font-size:11.5px;line-height:1.4;color:var(--dsw-alias-label-tertiary,#9a9aa3);white-space:nowrap;margin-right:6px}.brd-state[data-tone='bad']{color:var(--dsw-alias-state-danger-primary,#f2777a)}",
			".brd-icon{width:28px;height:28px;border:0;border-radius:7px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);display:grid;place-items:center;cursor:pointer}.brd-icon:hover{color:var(--dsw-alias-label-primary,#ececf1)}.brd-icon[disabled]{opacity:.45;cursor:default}",
			".brd-note{margin:12px 0 0;font-size:12px;line-height:1.55;color:var(--dsw-alias-label-tertiary,#9a9aa3)}",
			"@media (max-width:640px){.brd-wrap{padding:20px 18px 88px}.brd-row{grid-template-columns:minmax(0,1fr)}.brd-actions{justify-content:flex-start}}",
		].join("\n");

		const ICON = {
			open: "M6 3h7v7M13 3L5 11",
			check: "M3.5 8.2l3 3 6-6.4",
			undo: "M4 8a4 4 0 1 0 1.2-2.9M4 3.2v2.6h2.6",
		};

		function Icon(props) {
			return h(
				"button",
				{ type: "button", className: "brd-icon", title: props.label, "aria-label": props.label, onClick: props.onClick, disabled: props.disabled },
				h(
					"svg",
					{ width: 15, height: 15, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
					h("path", { d: ICON[props.icon], stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round" }),
				),
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
			if (!response.ok) throw new Error(payload?.message || payload?.error || `HTTP ${response.status}`);
			return payload;
		}

		function statusOf(task) {
			if (task.state === "resuelta") return { text: "resuelta", bad: false };
			if (task.outcome) return { text: task.outcome, bad: task.outcome === "falló" };
			if (task.closeReason) return { text: "sin revisar", bad: false };
			if (task.status) return { text: task.status, bad: false };
			return { text: "abierta", bad: false };
		}

		function titleOf(task) {
			const title = String(task.title ?? "").trim();
			return title.length > 64 ? (task.turn ? `Pedido del turno ${task.turn}` : "Pedido sin nombre") : title;
		}

		function BoardPanel(props) {
			useStyles();
			const [data, setData] = useState({ tasks: [] });
			const [filter, setFilter] = useState("abiertas");
			const [error, setError] = useState(null);
			const [busy, setBusy] = useState(false);

			const load = React.useCallback(async () => {
				try {
					setData(await api("/all"));
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

			const tasks = data.tasks ?? [];
			const abiertas = tasks.filter((task) => task.state === "abierta" && task.outcome !== "ok");
			const fallos = tasks.filter((task) => task.outcome === "falló");
			const cerradas = tasks.filter((task) => task.state === "resuelta" || task.outcome === "ok");
			const filters = [
				{ id: "abiertas", label: "Abiertas", count: abiertas.length, list: abiertas },
				{ id: "fallos", label: "Fallos", count: fallos.length, list: fallos },
				{ id: "cerradas", label: "Cerradas", count: cerradas.length, list: cerradas },
				{ id: "todas", label: "Todas", count: tasks.length, list: tasks },
			];
			const active = filters.find((item) => item.id === filter) ?? filters[0];

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

			const row = (task) => {
				const status = statusOf(task);
				return h(
					"div",
					{ className: "brd-row", key: task.id },
					h(
						"div",
						null,
						h("p", { className: "brd-title", title: task.title }, titleOf(task)),
						h("p", { className: "brd-where", title: task.note || task.workspace }, `${task.workspaceName}${task.note ? ` · ${task.note}` : ""}`),
					),
					h(
						"div",
						{ className: "brd-actions" },
						h("span", { className: "brd-state", "data-tone": status.bad ? "bad" : undefined }, status.text),
						task.sessionId ? h(Icon, { icon: "open", label: "Abrir conversación", onClick: () => props.openSession(task.sessionId) }) : null,
						task.state === "abierta"
							? h(Icon, { icon: "check", label: "Resolver", onClick: () => change(task, "resuelta"), disabled: busy })
							: h(Icon, { icon: "undo", label: "Reabrir", onClick: () => change(task, "abierta"), disabled: busy }),
					),
				);
			};

			return h(
				"div",
				{ className: "brd-root" },
				h(
					"div",
					{ className: "brd-wrap" },
					h("div", { className: "brd-head" }, h("h1", { className: "brd-h1" }, "Tareas")),
					h("p", { className: "brd-line" }, `${abiertas.length} abiertas · ${fallos.length} con fallos · ${cerradas.length} cerradas`),
					h(
						"div",
						{ className: "brd-filters" },
						filters.map((item) =>
							h("button", {
								type: "button",
								key: item.id,
								className: "brd-filter",
								"data-active": String(item.id === filter),
								onClick: () => setFilter(item.id),
							}, `${item.label} (${item.count})`),
						),
					),
					error ? h("p", { className: "brd-note" }, error.message) : null,
					!active.list.length ? h("p", { className: "brd-note" }, "No hay tareas en esta vista.") : null,
					active.list.length ? h("div", { className: "brd-list" }, active.list.slice(0, 120).map(row)) : null,
				),
			);
		}

		function BoardIcon(props) {
			const size = props?.size ?? 16;
			return h(
				"svg",
				{ width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
				h("rect", { x: 1.8, y: 1.8, width: 12.4, height: 12.4, rx: 3, stroke: "currentColor", strokeWidth: 1.3 }),
				h("path", { d: "M4.6 8.1l2 2 4.2-4.4", stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "round", strokeLinejoin: "round" }),
			);
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
				ctx.slots.register({ name: "sidebar.panellist", id: PANEL_ID, order: 20, label: () => "Tareas" }, BoardIcon),
			);
			ctx.slots.inject("main", () =>
				ctx.slots.register({ name: "main", key: PANEL_ID, inject: () => ({ openSession }) }, BoardPanel),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
