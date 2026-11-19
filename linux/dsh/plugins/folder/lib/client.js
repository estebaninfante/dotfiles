/**
 * dsh-local-folder — client half.
 *
 * La carpeta del proyecto en el header de la conversación: `~/Proyectos/zentr0`,
 * con el path completo en el tooltip y click para abrirla en el gestor.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-folder",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;
		const { useEffect, useState } = React;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const STYLE_ID = "dsh-local-folder-style";
		const CSS = [
			".fld-root{display:inline-flex;align-items:center;gap:6px;max-width:280px;height:24px;padding:0 8px;border:0;border-radius:6px;background:transparent;color:var(--dsw-alias-label-secondary,#b9b9c2);font:inherit;font-size:12px;cursor:pointer}",
			".fld-root:hover{color:var(--dsw-alias-label-primary,#ececf1)}",
			".fld-root:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#6ea8fe);outline-offset:1px}",
			".fld-name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
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

		/** El cwd llega por la lista de sesiones; puede tardar una pizca en estar. */
		function useCwd(getCwd, sessionId) {
			const [cwd, setCwd] = useState(() => (sessionId ? getCwd(sessionId) : ""));
			useEffect(() => {
				if (!sessionId) return undefined;
				let tries = 0;
				const timer = setInterval(() => {
					const value = getCwd(sessionId);
					if (value) {
						setCwd(value);
						clearInterval(timer);
					} else if (++tries >= 8) clearInterval(timer);
				}, 400);
				return () => clearInterval(timer);
			}, [getCwd, sessionId]);
			return cwd;
		}

		function FolderPath(props) {
			useStyles();
			const cwd = useCwd(props.getCwd, props.sessionId);
			if (!cwd) return null;
			const home = cwd.replace(/^\/home\/[^/]+/, "~");
			const shown = home.length > 38 ? `…/${home.split("/").slice(-2).join("/")}` : home;
			return h(
				"button",
				{ type: "button", className: "fld-root", title: `Abrir ${cwd}`, onClick: () => props.openFolder(cwd) },
				h(
					"svg",
					{ width: 12, height: 12, viewBox: "0 0 16 16", "aria-hidden": "true", fill: "none" },
					h("path", {
						d: "M2 4.4c0-.7.6-1.2 1.2-1.2h2.4l1.3 1.4h5.9c.7 0 1.2.6 1.2 1.2v5.9c0 .7-.6 1.2-1.2 1.2H3.2c-.7 0-1.2-.6-1.2-1.2V4.4Z",
						stroke: "currentColor",
						strokeWidth: 1.2,
					}),
				),
				h("span", { className: "fld-name" }, shown),
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
			const openFolder = (path) =>
				fetch("/tasks/open", {
					method: "POST",
					headers: { "content-type": "application/json", "x-dsh-tasks": "1" },
					body: JSON.stringify({ path }),
				}).catch(() => {});
			ctx.slots.inject("conversation.session.header.actions", () =>
				ctx.slots.register(
					{ name: "conversation.session.header.actions", id: "local-folder", order: 0, inject: () => ({ getCwd, openFolder }) },
					FolderPath,
				),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
