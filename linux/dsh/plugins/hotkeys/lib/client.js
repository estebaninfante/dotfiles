/**
 * dsh-local-hotkeys — client half.
 *
 * Ctrl+Alt+N (o Ctrl+Alt+T) crea una sesión nueva desde el teclado. En Brave
 * Ctrl+N y Ctrl+T nunca llegan a la página —el navegador los usa para ventana y
 * pestaña nueva—, así que el atajo suma Alt para poder existir dentro del tab.
 * El servicio shortcuts del harness rechaza esa combinación en web/Linux, por eso
 * el atajo se escucha acá y no se registra en el catálogo de atajos.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-hotkeys",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		/** Códigos físicos que crean la sesión. */
		const CODES = ["KeyN", "KeyT"];
		/** Lo que ya está pidiendo teclas: diálogos, menús y el grabador de atajos. */
		const FOREGROUND = '[role="dialog"][aria-modal="true"], [role="menu"]';

		function apply(ctx) {
			const get = (name) => (typeof ctx.get === "function" ? ctx.get(name) : ctx[name]);

			const startSession = () => {
				const uiWorkspace = get("uiWorkspace");
				if (!uiWorkspace || typeof uiWorkspace.startSession !== "function") return false;
				uiWorkspace.startSession();
				return true;
			};

			const onKeyDown = (event) => {
				if (event.defaultPrevented || event.isComposing || event.repeat) return;
				if (!event.ctrlKey || !event.altKey || event.shiftKey || event.metaKey) return;
				if (!CODES.includes(event.code)) return;
				if (document.querySelector(FOREGROUND) !== null) return;
				if (!startSession()) return;
				event.preventDefault();
				event.stopPropagation();
			};

			ctx.effect(() => {
				window.addEventListener("keydown", onKeyDown, true);
				return () => window.removeEventListener("keydown", onKeyDown, true);
			}, "dsh-local-hotkeys: sesión nueva");
		}

		exports.apply = apply;
		exports.inject = [];
		return module.exports;
	},
});
