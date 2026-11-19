/**
 * dsh-local-hotkeys — client half.
 *
 * Ctrl+Shift+. crea una sesión nueva desde el teclado dentro de cualquier
 * navegador. Tres límites que fijan el combo:
 *   - Ctrl+N y Ctrl+T los toma el navegador (ventana y pestaña nueva): nunca
 *     llegan a la página.
 *   - Con keyd, sostener Alt activa la capa numpad y se traga el modificador:
 *     Ctrl+Alt+N llega como Ctrl+N. Por eso Alt no se usa.
 *   - Ctrl+Shift+. es la combinación que el propio harness admite en web/Linux
 *     (junto con Ctrl+/), así que ningún atajo del navegador la pisa.
 * Ctrl+Alt+N y Ctrl+Alt+T quedan como alias para máquinas sin esa capa.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-hotkeys",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		/** Combinaciones exactas: cualquier modificador de más no dispara. */
		const TRIGGERS = [
			{ code: "Period", ctrl: true, shift: true, alt: false },
			{ code: "KeyN", ctrl: true, shift: false, alt: true },
			{ code: "KeyT", ctrl: true, shift: false, alt: true },
		];
		/** Lo que ya está pidiendo teclas: diálogos, menús y el grabador de atajos. */
		const FOREGROUND = '[role="dialog"][aria-modal="true"], [role="menu"]';

		function matches(event) {
			return TRIGGERS.some(
				(trigger) =>
					trigger.code === event.code &&
					trigger.ctrl === event.ctrlKey &&
					trigger.alt === event.altKey &&
					trigger.shift === event.shiftKey &&
					event.metaKey === false,
			);
		}

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
				if (!matches(event)) return;
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
