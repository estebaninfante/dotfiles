/**
 * dsh-local-sidebar-fit — client half.
 *
 * La sidebar del GUI (0.2.2) se redimensiona arrastrando su borde, pero el
 * handle mide 8 px: cuesta agarrarlo. Acá se ensancha a 14 px centrado en el
 * borde, sin mover el layout ni el cálculo de anchos (el mínimo real de 264 px
 * y el auto-colapso bajo 1024 px son del bundle del layout, no de este plugin).
 *
 * La clase del handle es de un CSS module: lleva un hash que cambia entre
 * releases; se busca por el sufijo estable "_handle" y el atributo data-side.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-sidebar-fit",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		/** Zona de agarre del borde: 8 px es muy fino para el mouse. */
		const HANDLE_CSS =
			'[class*="_handle"][data-side="sidebar"]{width:14px;margin-left:-3px}';

		function apply(ctx) {
			if (typeof document === "undefined") return;

			ctx.effect(() => {
				const style = document.createElement("style");
				style.dataset.plugin = "dsh-local-sidebar-fit";
				style.textContent = HANDLE_CSS;
				document.head.append(style);
				return () => style.remove();
			}, "dsh-local-sidebar-fit: agarre del borde");
		}

		exports.apply = apply;
		exports.inject = [];
		return module.exports;
	},
});
