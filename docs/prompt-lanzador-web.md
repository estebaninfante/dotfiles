# Prompt: dejar una app web lanzable desde el lanzador

Copiar de acá abajo, reemplazando `<APP>` por el nombre o la ruta de lo que haya
que atajar. Funciona con cualquier agente que sepa usar bash en esta máquina.

---

Sos un agente en esta máquina (Omarchy / Hyprland / Arch). Quiero que **<APP>**
quede lanzable desde el lanzador como una app: que abra en una ventana sin barra
de navegador y que levante su servidor solo si está apagado. La herramienta ya
existe — **no la reescribas**.

## Antes de tocar nada, leé esto

1. `~/.local/bin/webapp-launch --help` y su fuente `~/dotfiles/linux/bin/webapp-launch`.
   Es el mecanismo: lee `<dir>/.webapp.json`, levanta el `cmd` si el puerto está
   libre (log y pid en `~/.local/state/webapp/<nombre>/`), espera HTTP 200 y abre
   `omarchy-launch-or-focus-webapp` (ventana sin navegador, y enfoca en vez de
   duplicar).
2. Un caso completo ya resuelto: `~/Proyectos/videolab`. Mirá `.webapp.json`,
   `~/dotfiles/linux/config/applications/videolab.desktop` y la última sección de
   `~/dotfiles/linux/agents/AGENTS.md`.
3. Reglas del repo: se edita **dentro de `~/dotfiles/`**, nunca `~/.config/` ni
   `/usr/share/omarchy/`. Se publica con `~/dotfiles/scripts/publish.sh --yes`.

## Primero averiguá qué es (no asumas)

¿Un proyecto en `~/Proyectos/<x>` con servidor propio (`package.json`,
`manage.py`, `python3 -m http.server`, …)? ¿Una app instalada que levanta su
propio servidor en localhost? ¿Una app nativa de escritorio? De eso depende el caso.

## Caso A — proyecto con servidor propio

- Elegí un puerto **libre** y dejalo fijo (verificá con `ss -ltn`). Ya están
  tomados: 8777, 3980, 3031, 3040, 8791. Un puerto fijo mantiene el origen y las
  cookies del navegador entre arranques.
- Creá `<dir>/.webapp.json`:
  `name`, `title`, `comment`, `port`, `cmd` (el comando en primer plano que sirve
  la app), `url` (ruta relativa al puerto), `icon`, `pattern`.
- `pattern` es el texto con el que se busca la ventana abierta. Para un loopback
  conviene la clase de la ventana (`127.0.0.1__<ruta>`) en vez del título: así no
  confunde una pestaña normal del navegador con la app.
- `webapp-launch <dir> --install`
- Versioná el `.desktop` en `~/dotfiles/linux/config/applications/<nombre>.desktop`
  y enlazalo en `~/.local/share/applications/` (`--install` escribe a través del
  symlink si ya existe).
- Sumá una fila en `~/dotfiles/linux/config/omarchy/extensions/omarchy-menu.jsonc`
  bajo el grupo `proyectos` (ya existe), y copiá ese archivo a
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` (se recarga solo).

## Caso B — app instalada con UI web (levanta su servidor sola)

No necesita servidor propio: un `.desktop` cuyo `Exec` arranque lo que haga falta
y después abra la ventana, por ejemplo:

```
Exec=sh -c "systemctl --user start <unit>; exec omarchy-launch-or-focus-webapp <pattern> <url>"
```

Si hay un unit de systemd, usá el unit (no levantes el server a mano). Confirmá
que escuche en loopback y que el puerto no choque con otro proyecto.

## Caso C — app nativa

`.desktop` común: `Exec=<binario>`, `Icon=<icono>`, `Terminal=false`. Sin servidor
ni ventana de navegador.

## Verificación obligatoria (no digas "listo" sin esto)

1. Apagá el server (`webapp-launch <dir> --stop` o el unit) y confirmá que el
   puerto quedó libre.
2. Ejecutá el `Exec=` **exacto** del `.desktop`. Tiene que levantar el servidor solo
   y aparecer **una** ventana de app (sin barra de navegador). Comprobalo con:
   `hyprctl clients -j | jq -r '.[] | "\(.class) | \(.title)"'`
3. Ejecutá el mismo `Exec=` una segunda vez: **no** debe duplicar la ventana, debe
   enfocar la que ya está.
4. `Super+Espacio` → escribí el nombre → el atajo aparece y abre.
5. Publicá con `~/dotfiles/scripts/publish.sh --yes` y confirmá que el push salió.

## No hagas

- Tocar `/usr/share/omarchy/`.
- Reusar puertos de otros proyectos.
- Dejar procesos sueltos con `nohup` fuera del pidfile de `webapp-launch`.
- Pedir permiso en cada paso: hacelo y verificá. Avisá solo si no encontrás cómo
  se levanta la app o si el puerto que necesita está ocupado por otro servicio.
