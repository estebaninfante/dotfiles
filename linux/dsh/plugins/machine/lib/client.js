/**
 * dsh-local-machine — client half.
 *
 * Una página completa con el inventario de proyectos: resumen arriba, tabla
 * con decisión por fila, ficha al costado con descripción y tareas.
 *
 * No usa React ni slots internos: se monta como una capa propia sobre la app
 * (mismo mecanismo que `side-questions`) para no depender de la composición
 * del shell. El chat queda debajo, intacto.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-machine",
	factory: () => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const STYLE_ID = "dsh-machine-style";
		const TAB_ID = "dsh-machine-tab";
		const PAGE_ID = "dsh-machine-page";
		const STATES = ["unclassified", "active", "paused", "done", "archived"];
		const LABEL = {
			unclassified: "sin decidir",
			active: "activo",
			paused: "pausado",
			done: "terminado",
			archived: "archivado",
		};
		const KIND_LABEL = {
			project: "proyecto",
			product: "producto",
			experiment: "experimento",
			service: "servicio",
			app: "app",
			idea: "idea",
			task: "tarea",
		};

		let projects = [];
		let filter = "all";
		let selected = null;
		let busy = false;

		const esc = (value) =>
			String(value ?? "").replace(/[&<>"']/g, (c) => ({
				"&": "&amp;",
				"<": "&lt;",
				">": "&gt;",
				'"': "&quot;",
				"'": "&#39;",
			})[c]);

		const CSS = `
#${TAB_ID}{position:fixed;left:0;top:50%;transform:translateY(-50%);z-index:2147482000;writing-mode:vertical-rl;
  padding:14px 6px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-left:0;border-radius:0 10px 10px 0;
  background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-secondary,#b9bdc6);
  font:600 11px/1 system-ui,-apple-system,sans-serif;letter-spacing:.12em;text-transform:uppercase;cursor:pointer;user-select:none}
#${TAB_ID}:hover{background:var(--dsw-alias-interactive-bg-hover,#2a2d33);color:var(--dsw-alias-label-primary,#e9e9ec)}
#${PAGE_ID}{position:fixed;inset:0;z-index:2147482100;display:flex;flex-direction:column;
  background:var(--dsw-alias-bg-base,#0d0e10);color:var(--dsw-alias-label-primary,#e9e9ec);
  font:400 13px/1.45 system-ui,-apple-system,sans-serif}
#${PAGE_ID} .m-head{display:flex;align-items:center;gap:14px;padding:16px 22px;border-bottom:1px solid var(--dsw-alias-border-l2,#2a2c30)}
#${PAGE_ID} h1{margin:0;font-size:16px;font-weight:600;letter-spacing:-.01em}
#${PAGE_ID} .m-counters{display:flex;gap:14px;font-size:11px;color:var(--dsw-alias-label-tertiary,#8b8f98)}
#${PAGE_ID} .m-counters b{color:var(--dsw-alias-label-primary,#e9e9ec);font-weight:600}
#${PAGE_ID} .m-spacer{flex:1}
#${PAGE_ID} button{font:inherit;cursor:pointer}
#${PAGE_ID} .m-icon{height:28px;padding:0 10px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:8px;
  background:transparent;color:inherit}
#${PAGE_ID} .m-icon:hover{background:var(--dsw-alias-interactive-bg-hover,#24262b)}
#${PAGE_ID} .m-body{flex:1;min-height:0;display:flex}
#${PAGE_ID} .m-main{flex:1;min-width:0;display:flex;flex-direction:column;overflow:auto}
#${PAGE_ID} .m-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;padding:16px 22px}
#${PAGE_ID} .m-card{padding:12px 14px;border:1px solid var(--dsw-alias-border-l2,#2a2c30);border-radius:12px;
  background:var(--dsw-alias-bg-overlay,#15171a)}
#${PAGE_ID} .m-card .n{font-size:22px;font-weight:600;line-height:1.1}
#${PAGE_ID} .m-card .l{font-size:11px;color:var(--dsw-alias-label-tertiary,#8b8f98);margin-top:2px}
#${PAGE_ID} .m-filters{display:flex;flex-wrap:wrap;gap:6px;padding:0 22px 12px}
#${PAGE_ID} .m-chip{height:26px;padding:0 11px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:999px;
  background:transparent;color:var(--dsw-alias-label-secondary,#b9bdc6);font-size:12px}
#${PAGE_ID} .m-chip[data-on="1"]{background:var(--dsw-alias-label-primary,#e9e9ec);color:var(--dsw-alias-label-primary-foreground,#141518);border-color:transparent}
#${PAGE_ID} table{width:100%;border-collapse:collapse;font-size:12.5px}
#${PAGE_ID} thead th{position:sticky;top:0;background:var(--dsw-alias-bg-base,#0d0e10);text-align:left;
  padding:8px 10px;font-size:10.5px;letter-spacing:.06em;text-transform:uppercase;
  color:var(--dsw-alias-label-tertiary,#8b8f98);border-bottom:1px solid var(--dsw-alias-border-l2,#2a2c30);font-weight:600}
#${PAGE_ID} tbody td{padding:7px 10px;border-bottom:1px solid var(--dsw-alias-border-l1,#1c1e21);vertical-align:middle}
#${PAGE_ID} tbody tr:hover td{background:var(--dsw-alias-interactive-bg-hover,#17191c)}
#${PAGE_ID} tbody tr[data-sel="1"] td{background:var(--dsw-alias-interactive-bg-hover,#1b1e22)}
#${PAGE_ID} .m-name{cursor:pointer}
#${PAGE_ID} .m-name b{font-weight:600}
#${PAGE_ID} .m-name span{display:block;font-size:11px;color:var(--dsw-alias-label-tertiary,#8b8f98);
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:38ch}
#${PAGE_ID} select{height:26px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:7px;
  background:var(--dsw-alias-bg-overlay,#15171a);color:inherit;font:inherit;font-size:12px;padding:0 6px}
#${PAGE_ID} .m-num{text-align:right;font-variant-numeric:tabular-nums;color:var(--dsw-alias-label-secondary,#b9bdc6)}
#${PAGE_ID} .m-tag{display:inline-block;padding:1px 7px;border-radius:999px;font-size:10.5px;
  border:1px solid var(--dsw-alias-border-l2,#3a3d42);color:var(--dsw-alias-label-secondary,#b9bdc6)}
#${PAGE_ID} .m-tag[data-warn="1"]{border-color:var(--dsw-alias-state-warning-primary,#c08a2e);color:var(--dsw-alias-state-warning-primary,#c08a2e)}
#${PAGE_ID} .m-tag[data-ok="1"]{border-color:var(--dsw-alias-state-success-primary,#3f9f63);color:var(--dsw-alias-state-success-primary,#3f9f63)}
#${PAGE_ID} .m-detail{width:400px;min-width:320px;border-left:1px solid var(--dsw-alias-border-l2,#2a2c30);
  padding:18px 20px;overflow:auto;display:none;background:var(--dsw-alias-bg-overlay,#111214)}
#${PAGE_ID} .m-detail[data-open="1"]{display:block}
#${PAGE_ID} .m-detail h2{margin:0 0 2px;font-size:15px}
#${PAGE_ID} .m-detail .m-sub{font-size:11.5px;color:var(--dsw-alias-label-tertiary,#8b8f98);margin-bottom:14px}
#${PAGE_ID} .m-kv{display:grid;grid-template-columns:96px 1fr;gap:4px 10px;font-size:12px;margin-bottom:16px}
#${PAGE_ID} .m-kv dt{color:var(--dsw-alias-label-tertiary,#8b8f98)}
#${PAGE_ID} .m-kv dd{margin:0;word-break:break-all}
#${PAGE_ID} .m-label{font-size:10.5px;letter-spacing:.06em;text-transform:uppercase;
  color:var(--dsw-alias-label-tertiary,#8b8f98);margin:16px 0 6px}
#${PAGE_ID} textarea{width:100%;box-sizing:border-box;min-height:64px;resize:vertical;padding:8px 9px;
  border:1px solid var(--dsw-alias-border-l3,#33363c);border-radius:8px;background:transparent;color:inherit;font:inherit;outline:none}
#${PAGE_ID} textarea:focus{border-color:var(--dsw-alias-state-business-primary,#4c8dff)}
#${PAGE_ID} .m-tasks{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:5px}
#${PAGE_ID} .m-tasks li{display:flex;align-items:flex-start;gap:8px;font-size:12.5px}
#${PAGE_ID} .m-tasks li[data-done="1"] span{text-decoration:line-through;color:var(--dsw-alias-label-tertiary,#8b8f98)}
#${PAGE_ID} .m-tasks input{margin-top:3px}
#${PAGE_ID} .m-add{display:flex;gap:6px;margin-top:8px}
#${PAGE_ID} .m-add input{flex:1;min-width:0;height:30px;padding:0 9px;border:1px solid var(--dsw-alias-border-l3,#33363c);
  border-radius:8px;background:transparent;color:inherit;font:inherit;outline:none}
#${PAGE_ID} .m-empty{padding:40px 22px;color:var(--dsw-alias-label-tertiary,#8b8f98)}
`;

		async function api(path, body) {
			const options = body
				? {
						method: "POST",
						headers: { "content-type": "application/json", "x-dsh-machine": "1" },
						body: JSON.stringify(body),
					}
				: { method: "GET" };
			const res = await fetch(path, options);
			const data = await res.json().catch(() => ({}));
			if (!res.ok) throw new Error(data.message || data.error || `HTTP ${res.status}`);
			return data;
		}

		function injectStyles() {
			if (document.getElementById(STYLE_ID)) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = CSS;
			document.head.appendChild(style);
		}

		function mountTab() {
			if (document.getElementById(TAB_ID)) return;
			const tab = document.createElement("div");
			tab.id = TAB_ID;
			tab.textContent = "proyectos";
			tab.title = "Ver todos los proyectos";
			tab.addEventListener("click", openPage);
			document.body.appendChild(tab);
		}

		function counts() {
			const by = { unclassified: 0, active: 0, paused: 0, done: 0, archived: 0 };
			for (const p of projects) by[p.state] = (by[p.state] || 0) + 1;
			const stale = projects.filter(
				(p) => p.state !== "archived" && p.age_days != null && p.age_days >= 30,
			).length;
			const dirty = projects.filter((p) => Number(p.facts?.dirty || 0) > 0).length;
			const remotes = projects.filter((p) =>
				["github", "gitlab"].includes(p.facts?.remote_host || ""),
			).length;
			return { by, stale, dirty, remotes };
		}

		function visible() {
			return projects.filter((p) => (filter === "all" ? true : p.state === filter));
		}

		function rowHtml(p) {
			const facts = p.facts || {};
			const age = p.age_days == null ? "—" : `${p.age_days}d`;
			const remote = ["github", "gitlab"].includes(facts.remote_host || "")
				? `<span class="m-tag" data-ok="1">${esc(facts.remote_host)}</span>`
				: `<span class="m-tag">sin remoto</span>`;
			const dirty = Number(facts.dirty || 0);
			const dirtyHtml =
				dirty > 0 ? `<span class="m-tag" data-warn="1">${dirty} sin guardar</span>` : "—";
			const options = STATES.map(
				(s) =>
					`<option value="${s}"${p.state === s ? " selected" : ""}>${LABEL[s]}</option>`,
			).join("");
			return `<tr data-slug="${esc(p.slug)}"${selected === p.slug ? ' data-sel="1"' : ""}>
  <td class="m-name" data-open="${esc(p.slug)}"><b>${esc(p.slug)}</b><span>${esc(p.title || "")}</span></td>
  <td>${esc(KIND_LABEL[p.kind] || p.kind)}</td>
  <td><select data-state="${esc(p.slug)}">${options}</select></td>
  <td class="m-num">${age}</td>
  <td>${remote}</td>
  <td>${dirtyHtml}</td>
  <td class="m-num">${esc(facts.tickets_open ?? 0)}</td>
</tr>`;
		}

		function renderPage() {
			const page = document.getElementById(PAGE_ID);
			if (!page) return;
			const c = counts();
			const rows = visible();
			page.querySelector(".m-counters").innerHTML =
				`<span><b>${projects.length}</b> proyectos</span>` +
				`<span><b>${c.by.active || 0}</b> activos</span>` +
				`<span><b>${c.by.unclassified || 0}</b> sin decidir</span>` +
				`<span><b>${c.remotes}</b> con remoto</span>`;
			page.querySelector(".m-cards").innerHTML = [
				[`${c.by.unclassified || 0}`, "sin decisión", "arriba en la lista"],
				[`${c.by.active || 0}`, "activos", "tope recomendado: 3"],
				[`${c.stale}`, "sin tocar +30 días", "candidatos a archivar"],
				[`${c.dirty}`, "con cambios sin guardar", "riesgo de perder trabajo"],
			]
				.map(
					([n, l, hint]) =>
						`<div class="m-card"><div class="n">${esc(n)}</div><div class="l">${esc(l)} · ${esc(hint)}</div></div>`,
				)
				.join("");
			page.querySelector(".m-filters").innerHTML = ["all", ...STATES]
				.map(
					(s) =>
						`<button class="m-chip" data-filter="${s}" data-on="${filter === s ? 1 : 0}">${
							s === "all" ? "todos" : LABEL[s]
						}</button>`,
				)
				.join("");
			page.querySelector(".m-table tbody").innerHTML = rows.length
				? rows.map(rowHtml).join("")
				: `<tr><td colspan="7" class="m-empty">Nada con ese filtro.</td></tr>`;
		}

		async function loadProjects() {
			const data = await api("/machine/projects");
			projects = data.projects || [];
			projects.sort((a, b) => {
				const rank = (p) => STATES.indexOf(p.state);
				if (rank(a) !== rank(b)) return rank(a) - rank(b);
				return (a.age_days ?? 9999) - (b.age_days ?? 9999);
			});
			renderPage();
		}

		async function openDetail(slug) {
			selected = slug;
			const detail = document.querySelector(`#${PAGE_ID} .m-detail`);
			if (!detail) return;
			renderPage();
			detail.dataset.open = "1";
			detail.innerHTML = `<div class="m-sub">cargando…</div>`;
			try {
				const p = await api(`/machine/project?slug=${encodeURIComponent(slug)}`);
				const f = p.facts || {};
				const tasks = (p.tasks || [])
					.map(
						(t) =>
							`<li data-done="${t.state === "done" ? 1 : 0}">
  <input type="checkbox" data-task="${esc(t.slug)}"${t.state === "done" ? " checked" : ""}>
  <span>${esc(t.title)}</span>
</li>`,
					)
					.join("");
				detail.innerHTML = `
<h2>${esc(p.slug)}</h2>
<div class="m-sub">${esc(p.title || "")}</div>
<dl class="m-kv">
  <dt>estado</dt><dd>${esc(LABEL[p.state] || p.state)}</dd>
  <dt>tipo</dt><dd>${esc(KIND_LABEL[p.kind] || p.kind)}</dd>
  <dt>ruta</dt><dd>${esc(f.path || "—")}</dd>
  <dt>rama</dt><dd>${esc(f.branch || "—")}</dd>
  <dt>último commit</dt><dd>${esc(f.last_commit || "—")}${p.age_days == null ? "" : ` (hace ${p.age_days}d)`}</dd>
  <dt>remoto</dt><dd>${esc(f.remote_url || "sin remoto")}</dd>
  <dt>sin guardar</dt><dd>${esc(f.dirty || 0)} archivo(s)</dd>
  <dt>sin subir</dt><dd>${esc(f.ahead || "—")} commit(s)</dd>
</dl>
<div class="m-label">descripción / nota</div>
<textarea id="m-note" placeholder="Para qué es, en qué quedó, qué falta…">${esc(p.note || "")}</textarea>
<div class="m-label">tareas</div>
<ul class="m-tasks">${tasks || '<li><span style="opacity:.6">sin tareas</span></li>'}</ul>
<div class="m-add">
  <input id="m-new-task" placeholder="Nueva tarea…">
  <button class="m-icon" id="m-add-task">Agregar</button>
</div>`;

				detail.querySelector("#m-note").addEventListener("change", async (event) => {
					await api("/machine/entity", { slug: p.slug, note: event.target.value });
					const local = projects.find((x) => x.slug === p.slug);
					if (local) local.note = event.target.value;
				});
				detail.querySelector("#m-add-task").addEventListener("click", () => addTask(p.slug));
				detail.querySelector("#m-new-task").addEventListener("keydown", (event) => {
					if (event.key === "Enter") addTask(p.slug);
				});
				for (const box of detail.querySelectorAll("[data-task]")) {
					box.addEventListener("change", async () => {
						if (!box.checked) return;
						await api("/machine/task-done", { task: box.dataset.task });
						box.closest("li").dataset.done = "1";
					});
				}
			} catch (error) {
				detail.innerHTML = `<div class="m-sub">no se pudo cargar: ${esc(error.message)}</div>`;
			}
		}

		async function addTask(slug) {
			const input = document.querySelector(`#${PAGE_ID} #m-new-task`);
			const title = input?.value?.trim();
			if (!title) return;
			input.value = "";
			await api("/machine/task", { slug, title });
			await openDetail(slug);
		}

		async function setState(slug, state) {
			const local = projects.find((p) => p.slug === slug);
			const before = local?.state;
			if (local) local.state = state;
			renderPage();
			try {
				await api("/machine/entity", { slug, state });
			} catch (error) {
				if (local && before) local.state = before;
				renderPage();
				console.error("machine:", error);
			}
		}

		function openPage() {
			if (document.getElementById(PAGE_ID)) return;
			const page = document.createElement("div");
			page.id = PAGE_ID;
			page.innerHTML = `
<div class="m-head">
  <h1>Proyectos</h1>
  <div class="m-counters"></div>
  <div class="m-spacer"></div>
  <button class="m-icon" id="m-refresh" title="Volver a leer el disco">Actualizar</button>
  <button class="m-icon" id="m-close" title="Cerrar (Esc)">Cerrar</button>
</div>
<div class="m-body">
  <div class="m-main">
    <div class="m-cards"></div>
    <div class="m-filters"></div>
    <table class="m-table">
      <thead><tr><th>proyecto</th><th>tipo</th><th>estado</th><th>últ. cambio</th><th>remoto</th><th>sin guardar</th><th>tareas</th></tr></thead>
      <tbody></tbody>
    </table>
  </div>
  <aside class="m-detail"></aside>
</div>`;
			document.body.appendChild(page);

			page.querySelector("#m-close").addEventListener("click", closePage);
			page.querySelector("#m-refresh").addEventListener("click", async () => {
				await api("/machine/scan", {}).catch(() => {});
				await loadProjects();
			});
			page.addEventListener("click", (event) => {
				const chip = event.target.closest("[data-filter]");
				if (chip) {
					filter = chip.dataset.filter;
					renderPage();
					return;
				}
				const opener = event.target.closest("[data-open]");
				if (opener) openDetail(opener.dataset.open);
			});
			page.addEventListener("change", (event) => {
				const select = event.target.closest("[data-state]");
				if (select) setState(select.dataset.state, select.value);
			});
			document.addEventListener("keydown", onKey);
			loadProjects().catch((error) => {
				page.querySelector(".m-table tbody").innerHTML =
					`<tr><td colspan="7" class="m-empty">no se pudo leer la base: ${esc(error.message)}</td></tr>`;
			});
		}

		function closePage() {
			document.removeEventListener("keydown", onKey);
			document.getElementById(PAGE_ID)?.remove();
			selected = null;
		}

		function onKey(event) {
			if (event.key !== "Escape") return;
			const detail = document.querySelector(`#${PAGE_ID} .m-detail[data-open="1"]`);
			if (detail) {
				detail.dataset.open = "0";
				selected = null;
				renderPage();
				return;
			}
			closePage();
		}

		function apply() {
			injectStyles();
			mountTab();
		}

		exports.apply = apply;
		exports.inject = [];
		return module.exports;
	},
});
