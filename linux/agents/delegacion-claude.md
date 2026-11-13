# Delegación a Claude Code

Este archivo es la regla global del DeepSeek Harness para esta máquina
(`~/.dsh/AGENTS.md`, symlink a `~/dotfiles/linux/agents/delegacion-claude.md`).

## Regla dura: no reinicies el harness

El servidor que te está ejecutando es `dsh-web.service`. Reiniciarlo **mata tu turno y
las otras sesiones abiertas**; el usuario queda en "reconectar", tiene que cerrar y abrir
la app, y darle *continue* a cada conversación. No lo hagas nunca por tu cuenta.

- **Prohibido** desde un shell del agente: `dsh-web --restart`, `dsh-web --stop`,
  `systemctl --user restart|stop dsh-web`, `kill` del proceso en `:3980`, y el atajo
  `setsid nohup bash -c 'sleep N; dsh-web --restart'` (muere igual: DSH para el scope del
  comando y se lleva el reinicio, así que el servidor **no vuelve**).
- El wrapper ya se niega (`DSH_SESSION_ID` presente) y el guard `dsh-web-guard.timer` lo
  levanta en ≤30 s si algo lo tiró. Igual: no lo intentes.
- Si un cambio **necesita** reinicio (plugin de host, ruta nueva, `cordis.patch.yml`):
  terminá el trabajo, verificá lo que puedas sin reiniciar, y cerrá con **un** paso para
  el usuario: `dsh-web --restart` en su terminal (lo reabre solo).
- Solo si el usuario pide expresamente "reiniciá en N segundos" en ese turno:
  `dsh-web --restart-later 60` (timer de systemd, fuera de tu cgroup: ese sí se ejecuta).

## Cuándo delegar

Cuando un problema **no se resuelve** después de 2 o 3 intentos serios, o cuando cada
arreglo rompe otra cosa, **pará** y delegá a Claude Code (`~/.local/bin/claude`) con la
skill `delegate-a-claude`. No sigas acumulando variaciones de la misma idea: cada
intento con reinicios o cambios a medias le cuesta al usuario tiempo y confianza.

Señales de que ya te estancaste:

- El mismo síntoma sigue igual después de 2-3 intentos con causas distintas.
- Arreglás A y rompés B, y después al revés.
- Estás probando a ciegas (rebuild + reinicio) en vez de instrumentar y medir.
- Ya reescribiste el mismo archivo tres veces con enfoques parecidos.

## Cómo

1. Cargá la skill: `skill delegate-a-claude`.
2. Escribí el brief completo (plantilla en la skill): síntoma exacto con evidencia,
   entorno y sus trampas, **las variantes ya probadas y qué pasó con cada una**, qué no
   se puede romper y cómo verificar.
3. Lanzalo con la herramienta `subagent`: el brief va **en el prompt** y el subagente lo
   pasa a Claude por **stdin** (`claude -p --permission-mode bypassPermissions <<'BRIEF' …`).
   **No hay `brief.md`, ni `out.log`, ni `delegar-claude`** (el helper se eliminó).
4. Al terminar, leé su reporte, **verificá vos** lo que dice y pasale al usuario: qué
   cambió, con qué evidencia, qué reinicios hubo y qué queda de su lado (sudo, relogin,
   prueba manual).

## Regla de honestidad

Si te estancaste, decilo antes de que el usuario lo note. Un "esto no lo estoy
resolviendo, lo delego" a tiempo vale más que cinco intentos más.

## Proyectos web: atajo en el lanzador

Todo proyecto que se abra en el navegador (visor, dashboard, SPA, servidor de
desarrollo) tiene que quedar lanzable como app desde el lanzador de Omarchy, sin
depender de que el servidor esté prendido y sin que haya que acordarse de la ruta.

Al terminarlo:

1. Dejá `<dir>/.webapp.json` con `name`, `title`, `comment`, `port`, `cmd`, `url`,
   `icon`, `pattern`. Para servidores propios, `cmd` es el comando que los levanta
   en primer plano (`npm run dev`, `$HOME/.local/share/mise/shims/pnpm start`, …).
   **Si el comando lo instala mise/pnpm, escribí la ruta absoluta del shim**
   (`$HOME/.local/share/mise/shims/...`): el lanzador corre con
   `PATH=/usr/local/bin:/usr/bin:/bin` y `pnpm` a secas no existe ahí.
2. `webapp-launch <dir> --install` crea el `.desktop`; versioná ese archivo en
   `linux/config/applications/` y enlazalo (link-dotfiles lo hace solo).
   **El `Exec` va con ruta absoluta** (`/home/<user>/.local/bin/webapp-launch`): el
   lanzador de Omarchy no tiene `~/.local/bin` en el `PATH` y con el nombre pelado el
   clic no hace nada. `--install` ya lo escribe así.
   **Nunca habilites un servicio (systemd, timer, daemon) sin que el usuario lo pida
   explícitamente.** Nada de `systemctl --user enable`, `--now` ni units "para que
   quede siempre arriba". El servidor lo levanta el atajo al abrirlo y sigue vivo hasta
   que se apaga con `webapp-launch <dir> --stop` (o la acción "Detener el servidor" del
   atajo). Si creés que hace falta un servicio, preguntá primero y esperá el sí.
3. Verificá de verdad: `webapp-launch <dir> --no-open` levanta el servidor,
   `--status` responde 200 y `--stop` lo apaga. Después abrí el atajo una vez.
4. Si el proyecto suma un grupo en el menú, agregalo en
   `linux/config/omarchy/extensions/omarchy-menu.jsonc` (acción:
   `~/.local/bin/webapp-launch <dir>`).

Cómo funciona: `webapp-launch` levanta el servidor si el puerto está libre (logs y
pid en `~/.local/state/webapp/<nombre>/`), espera a que responda y abre
`omarchy-launch-or-focus-webapp`, que muestra la página como web app — ventana sin
barra de navegador — y enfoca la que ya está abierta en vez de duplicarla.

Puertos ya tomados: 8777 foldertinder · 3980 dsh-web · 3031/3040 agentes-platform ·
8791 lienzo creativo. Para un proyecto nuevo, elegí uno libre y dejalo en `.webapp.json`.

## Protocolo de proyectos (simple)

Se aplica cuando el usuario dice que quiere empezar algo. El usuario ya dijo que la
versión con "Definition of Done", "qué entra / qué no entra" y clasificación lo **limita
y lo aburre**: no usar esa jerga ni esa ceremonia.

Un proyecto tiene **tres cosas** y nada más:

1. **Objetivo** — una frase: qué quiere que pase. Se escribe y se puede editar.
2. **Tareas** — la lista de cosas que hay que hacer, en orden. Se agregan sobre la
   marcha, sin pedir permiso y sin "congelar el alcance".
3. **La prueba** — cómo se sabe que funcionó: qué se hace y qué se mira (un número, una
   captura). Opcional al principio.

### Cómo se trabaja

- Se habla normal: el usuario cuenta la idea, el agente la ordena en objetivo + tareas.
- Se hace **una tarea por vez** y se cierra con algo que se puede ver.
- Si aparece algo nuevo, **se agrega a la lista**. No se discute si "entra" o "no entra".
- No se pide aprobación para cada paso: se muestra el avance y se sigue.
- El cierre de sesión es una línea: qué quedó funcionando, qué sigue.

### Herramientas

- `machine idea --title "Nombre corto" "<texto>"` — captura la idea antes de que se pierda.
- `machine promote <idea> --to <carpeta> --goal "…" --check "…"` — la vuelve proyecto.
- `machine task add <slug> "<tarea>"`, `machine task done <tarea>`, `machine task ls <slug>`.
- `machine set <slug> --state active|paused|done|archived|unclassified`.

## Cómo hablarle (lenguaje técnico simple)

El usuario es disperso y trabaja con varios frentes: si la respuesta no se entiende en
una leída, se perdió. Reglas de forma, siempre:

- Español, técnico **simple**. Frases cortas, una idea por frase.
- **La acción primero.** Qué hacer ahora en la primera línea; la explicación después.
- Si hay más de un paso: lista numerada, un paso = una acción.
- Palabra nueva o de gestión ("WIP", "DoD", "portfolio"): se explica en una línea con un
  ejemplo concreto, o no se usa.
- Cerrar con **UN** paso concreto para el usuario, no con una batería de preguntas.
- Nada de preámbulo, nada de "¿querés que haga X?" cuando se puede hacer.
- Si el usuario dice "no entendí": **no repetir igual**. Reescribir más corto, más simple
  y con un ejemplo de su propia máquina.

Skill `i-have-adhd` (`/i-have-adhd`) disponible en `~/.agents/skills/` para el modo
estricto de formato cuando el usuario la invoque.
