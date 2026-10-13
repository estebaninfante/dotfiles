---
name: agent-friendly-app
description: >
  Contrato y flujo para construir apps agent-friendly en esta maquina (AFA v1). Toda app,
  web, dashboard, sitio, CLI o servicio debe nacer con estructura feature-first, 1
  responsabilidad por archivo, tipos en los boundaries y linter + typecheck + tests. Usala
  cuando pidan "crear app", "nueva app", "construir dashboard", "montar sitio", "hacer un
  CLI", "scaffold", "arrancar proyecto", "app desde cero", "refactorizar a modulos",
  "partir un monolito", o cuando un archivo fuente crezca demasiado. Triggers: crear app,
  nueva app, dashboard, scaffolding, scaffold, estructura de carpetas, monolito,
  feature-first, agent-friendly, new-app, app-arch-lint.
---

# App Agent-Friendly (AFA v1)

Contrato obligatorio para TODA app que se construya en esta maquina. Una app es
**agent-friendly** cuando un agente puede ubicar, entender y cambiar cualquier parte sin
leer miles de lineas. El objetivo no es maximizar LOC: es escribir **menos** y mas claro.

Dueño: agente `app-architect`. Verificacion determinista: `verify run app-arch`.
Linter on-edit: `app-arch-lint`. Scaffold por defecto: `new-app`.

## Cuando dispara

Cualquier pedido de **crear/arrancar/estructurar** una app, web, dashboard, sitio, CLI o
servicio; **partir un monolito**; o **reestructurar** un repo para que sea mantenible por
agentes. Tambien cuando un archivo fuente cruza el umbral de tamano (el linter avisa solo).

No dispara para UI/UX (eso es `ui-ux`) ni para automatizar el navegador (eso es
`browser-pilot`).

## Contrato AFA v1 (fijo, no negociable)

1. **1 responsabilidad por archivo.** Si un archivo hace dos cosas, se parte.
2. **HARD FAIL**: un archivo fuente (`js`, `mjs`, `cjs`, `ts`, `tsx`, `jsx`, `css`, `scss`,
   `py`, `rs`, `go`, `html`, `vue`, `svelte`) **> 400 lineas** falla. **WARN > 300**.
3. **Estructura feature-first** (ver abajo). No hay `utils.ts` cajon-de-sastre.
4. **Monolito prohibido**: un repo cuya unica app sea `index.html` + `app.js`/`main.js` +
   `style.css`/`app.css` en la raiz sumando **> 600 lineas** esta roto. No se acepta.
5. **Tipos en los boundaries**: parsear/validar datos externos (fetch, config, env, stdin)
   en el borde; adentro confiar en los tipos. Prohibido `any` sin justificacion escrita.
6. **Boundaries**: los guards viven en CLI/config/red/APIs externas; la logica de negocio
   vive en **funciones puras** testeables.
7. **Linter + typecheck + tests obligatorios** por proyecto.
8. **`AGENTS.md` del proyecto**: cada repo de app documenta su estructura y comandos
   (`dev`, `test`, `lint`, `typecheck`) en su propio `AGENTS.md`.

## Estructura feature-first

```
src/
  features/<feature>/
    ui/        componentes de la feature
    model/     estado + logica pura (funciones, reducers, hooks puros)
    api/       llamadas externas + mapeo a tipos del dominio
    types.ts   tipos de la feature
  components/  compartidos entre features
  lib/         utilidades puras sin dependencias de features
  types/       tipos globales del dominio
  hooks/       hooks compartidos
tests/         o tests colocados junto al fuente (*.test.ts)
```

Regla: una feature no importa el `model/` ni la `ui/` de otra feature. Si lo necesita,
eso es `lib/` o `components/`. Dependencias siempre hacia adentro (ui -> model -> types).

## Principios (portados de pstack, en contexto de apps)

Cada uno es una regla corta y accionable. Aplicalos SIEMPRE, no solo al refactor.

1. **Laziness protocol** — sesga hacia **borrar** y al cambio mas chico que resuelve. Si
   puedes eliminar codigo en vez de agregarlo, elimina.
2. **Foundational thinking** — antes de escribir logica, decide los **tipos y estructuras
   de datos**. Con los datos correctos, el codigo de abajo se vuelve obvio.
3. **Model the domain** — la regla del negocio se codifica en una **estructura** (union,
   enum, estado explicito), no en condicionales dispersos por todo el repo.
4. **Boundary discipline** — concentra los guards en el borde (CLI, config, red, API
   externa); adentro confia en los tipos y manten la logica en funciones puras.
5. **Type-system discipline** — haz los estados ilegales **irrepresentables**; parsea y
   valida los datos externos al entrar; no le mientas al compilador; deriva de un schema
   autoritativo. Nada de `any`.
6. **Subtract before you add** — antes de construir, quita peso muerto, validadores
   redundantes y stubs. Construye sobre la base mas simple.
7. **Build the lever** — para trabajo no trivial (migracion, chequeo, generacion), construye
   la **herramienta** (script, generador, lint) en vez de hacerlo a mano. La herramienta es
   el artefacto que un revisor puede re-correr.
8. **Prove it works** — verifica contra el **artefacto real** (corre la feature, lee el valor
   real, inspecciona el diff), no contra un proxy, un self-report ni un "compila".
9. **Fix root causes** — reproduce primero; pregunta "por que" hasta la causa raiz y arregla
   ahi. Los guards que silencian un crash sin explicarlo no son fixes.
10. **Sequence verifiable units** — parte el trabajo en unidades chicas que **cada una
    termina en un estado verificable**; verifica cada una antes de la siguiente. Ordena los
    commits igual: cada paso se prueba.
11. **Encode lessons in structure** — cuando una correccion se repite, conviertela en
    **lint, script o check de runtime**, no en mas texto. Regla -> enforcement.
12. **Guard the context window** — manda el trabajo en bruto a subagentes; trae solo
    **resumenes** al hilo principal, nunca payloads crudos. Un contexto limpio dura mas.

## Flujo obligatorio

1. **Antes de crear**: corre `new-app <nombre> <tipo>` (scaffold por defecto; produce la
   estructura feature-first + `AGENTS.md` + linter/tests configurados). No arranques a mano.
2. **Implementar** respetando el contrato AFA v1 y la estructura. Un archivo = una
   responsabilidad.
3. **On-edit**: `app-arch-lint` corre automatico en cada edit (plugin) y reporta
   HARD FAIL (>400 lineas, monolito raiz, estructura invalida) o WARN (>300, boundaries
   rotos). Corrige TODO ERROR antes de seguir.
4. **Cierre**: `verify run app-arch` en **PASS** (checks de estructura, tamanos, boundaries,
   `AGENTS.md` del proyecto, linter/typecheck/tests presentes). No cierres la tarea sin
   verde.
5. **Delega lo que no es arquitectura**: UI/UX -> `ui-ux`; navegador -> `browser-pilot`;
   systemd/paquetes/scripts de maquina -> `dotfiles`.

## Tier (E3)

`medio` por defecto (cambio de estructura acotado, 1-5 archivos). `riesgoso` solo si el
refactor toca muchos archivos o rompe boundaries entre features. `micro` si es un rename o
mover un archivo suelto.

## Anti-patrones (por que existe esta regla)

Estos repos reales salieron como monolitos y son el motivo del contrato:

- `foldertinder/static`: `app.js` 3548 lineas + `app.css` 3060 + `index.html` 291.
- `hypr-remote/public/app.js`: 4266 lineas.
- `noteriv`: `globals.css` 9037 lineas.

Ninguno tiene owner, regla ni verificacion. Esta skill, el agente `app-architect`, el
linter `app-arch-lint` y `verify run app-arch` cierran ese hueco para que **no vuelva a
pasar**.
