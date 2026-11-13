/**
 * dsh-local-video-preview — client half.
 *
 * Registra un visor de video en el panel lateral derecho. El visor propio del
 * harness solo sabe de texto, imágenes, PDF, Office y planillas, y para un
 * `.mp4` mostraba "este tipo de archivo todavía no tiene vista previa".
 *
 * El elemento `<video>` no recibe bytes por JS: apunta a `/video-preview/stream`
 * (mitad host), que sirve el archivo con `Range`. Así un video de cientos de MB
 * arranca al instante y se puede adelantar, en vez de cargarse entero en memoria.
 *
 * El cuerpo se registra con `loading: "renderer"`: el dueño del tab no lee nada
 * por su cuenta y este visor avisa cuándo terminó (`content.loaded(version)`),
 * que es lo que habilita el refresco automático cuando el archivo cambia.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-video-preview",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		/** Identidad del visor: misma clave para el registro y para el slot. */
		const ID = "dsh-local-video-preview/video";
		const STYLE_ID = "dsh-video-preview-style";
		const STREAM = "/video-preview/stream";

		/** Lo que el navegador reproduce sin plugins; mkv/mov dependen del códec. */
		const EXTENSIONS = ["mp4", "m4v", "mov", "webm", "mkv", "ogv", "ogg"];

		const STYLE_CSS = [
			".dsh-video-frame{box-sizing:border-box;display:flex;align-items:center;justify-content:center;",
			"min-height:100%;height:100%;padding:12px;white-space:normal;font-family:var(--dsw-font,sans-serif);",
			"font-size:13px;position:relative}",
			".dsh-video-player{display:block;max-width:100%;max-height:100%;width:auto;height:auto;",
			"background:#000;border-radius:var(--dsw-radius-md,8px);outline:none}",
			".dsh-video-note{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);margin:0;",
			"max-width:min(420px,80%);text-align:center;line-height:1.55;color:var(--dsw-alias-label-secondary,#9a9aa2);",
			"pointer-events:none}",
			".dsh-video-error{display:flex;flex-direction:column;align-items:center;gap:10px;max-width:420px;",
			"margin:auto;text-align:center;color:var(--dsw-alias-label-secondary,#9a9aa2);line-height:1.6}",
			".dsh-video-error-title{margin:0;color:var(--dsw-alias-label-primary,#e9e9ec);font-size:13px}",
			".dsh-video-error-hint{margin:0;font-size:12px}",
			".dsh-video-retry{height:30px;padding:0 14px;border:.5px solid var(--dsw-alias-border-l2,#3a3d42);",
			"border-radius:var(--dsw-radius-sm,6px);background:0 0;color:var(--dsw-alias-label-primary,#e9e9ec);",
			"font:inherit;font-size:12px;cursor:pointer}",
			".dsh-video-retry:hover{background:var(--dsw-alias-interactive-bg-hover,#ffffff12)}",
			"@media (max-width:820px){.dsh-video-frame{padding:6px}.dsh-video-retry{height:36px}}"
		].join("\n");

		function ensureStyle() {
			if (document.getElementById(STYLE_ID) !== null) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = STYLE_CSS;
			document.head.appendChild(style);
		}

		/**
		 * Cuerpo del visor: un `<video>` nativo apuntando al stream del host.
		 * @param props - props del slot keyed `sidebar.right.tab.document`.
		 */
		function VideoBody(props) {
			const { useTabInfo, useResource, content, resourceAddress } = props;
			const { tab } = useTabInfo();
			const meta = useResource(resourceAddress);
			const absolutePath = meta.value?.absolutePath;
			const version = meta.value?.version;
			const revision = content.kind === "renderer" ? content.revision : 0;
			const [status, setStatus] = React.useState("loading");
			const reported = React.useRef(-1);

			const src = React.useMemo(() => {
				if (typeof absolutePath !== "string" || absolutePath.length === 0) return void 0;
				const params = new URLSearchParams();
				params.set("path", absolutePath);
				// Basura de caché: un refresh del tab cambia la revisión y el
				// navegador vuelve a pedir el archivo en vez de repetir el anterior.
				params.set("r", String(revision));
				return `${STREAM}?${params.toString()}`;
			}, [absolutePath, revision]);

			React.useEffect(() => {
				setStatus("loading");
			}, [src]);

			// El dueño del tab solo deja de mostrar "cargando" cuando el visor
			// confirma la versión que está mostrando. Sin esto el tab queda
			// marcado como pendiente y el refresco automático no se activa.
			const reportLoaded = React.useCallback(() => {
				if (content.kind !== "renderer") return;
				if (typeof version !== "string" || version.length === 0) return;
				if (reported.current === revision) return;
				reported.current = revision;
				content.loaded(version);
			}, [content, revision, version]);

			const retry = React.useCallback(() => {
				setStatus("loading");
				if (content.kind === "renderer") content.reload();
			}, [content]);

			const failed = status === "failed";

			let body;
			if (failed) {
				body = h("div", { className: "dsh-video-error", role: "alert" },
					h("p", { className: "dsh-video-error-title" }, "No pude reproducir este video."),
					h("p", { className: "dsh-video-error-hint" },
						"El códec o el contenedor pueden no estar soportados por el navegador. " +
						"Usá Abrir en la barra de arriba para verlo con la app del sistema."),
					h("button", { type: "button", className: "dsh-video-retry", onClick: retry }, "Reintentar"));
			} else if (src === void 0) {
				body = h("p", { className: "dsh-video-note" },
					meta.failure === void 0 ? "Cargando video…" : "No pude leer este archivo.");
			} else {
				body = h("video", {
					key: src,
					className: "dsh-video-player",
					src,
					controls: true,
					playsInline: true,
					preload: "metadata",
					"data-video-preview": true,
					onLoadedMetadata: () => {
						setStatus("ready");
						reportLoaded();
					},
					onError: () => {
						setStatus("failed");
					}
				});
			}

			return h("div", { className: "dsh-video-frame", "data-video-tab": tab.id },
				body,
				status === "loading" && !failed && src !== void 0
					? h("p", { className: "dsh-video-note" }, "Cargando video…")
					: null);
		}

		/**
		 * @param ctx - contexto cliente con el registro de visores y los slots.
		 */
		function apply(ctx) {
			ensureStyle();
			ctx.effect(() => ctx.documentPreviews.register({
				id: ID,
				extensions: EXTENSIONS,
				// Son contenedores binarios: no tiene sentido ofrecer "texto plano".
				binaryExtensions: EXTENSIONS,
				// Banda de extensión: gana sobre el fallback de texto del producto.
				priority: "extension",
				title: () => "Video",
				loading: "renderer",
				wrap: false
			}), "video-preview: metadata");

			ctx.effect(() => ctx.slots.inject("sidebar.right.tab.document", () => ctx.slots.register({
				name: "sidebar.right.tab.document",
				key: ID,
				inject: () => ({})
			}, VideoBody)), "video-preview: body");
		}

		exports.apply = apply;
		exports.inject = ["slots", "documentPreviews"];
		return module.exports;
	}
});
