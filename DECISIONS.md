# Decisiones

Registro de decisiones de arquitectura del repo: qué se eligió, por qué y qué
se descartó. Las entradas no se reescriben; se agregan.

## 2026-10-28 — Omni tiene una página local, y una sola fuente de estado

**Contexto.** Omni ya tenía el oído abierto, la tecla de Windows y el HUD
flotante, pero ninguna superficie para hablarle con el mouse, escribirle o ver
el hilo de la conversación. El usuario pidió "un frontend, una página local para
interactuar con el omni de mi computador, por palabra y botón".

**Qué se eligió.** Un subcomando, `omni web`, que sirve una sola página
(`linux/config/omni/omni-web.html`) en `127.0.0.1:9932` usando solo la
biblioteca estándar de Python. La página tiene un botón de micrófono y un campo
de texto, y muestra el hilo y el estado en vivo. Endpoints: `GET /` (página),
`GET /api/estado`, `GET /api/eventos` (SSE), `POST /api/ptt`, `POST /api/texto`,
`POST /api/oido`. El botón reusa `omni ptt` (grabación con sox en el equipo) y
el texto reusa `omni pedir`: la página no reimplementa nada. El estado sale del
mismo `status.json` que dibuja el HUD, así la tarjeta flotante y el navegador
nunca se contradicen. Un lock serializa grabación y pedido; si el modelo está
dormido, el primer toque lo levanta (`asegurar_modelo`) antes de grabar. Unit
`omni-web.service` con el resto de la sesión gráfica (es liviano: no carga nada
hasta que se usa).

**Por qué.** Lo que ya funcionaba (grabar, transcribir, pensar, hablar, anotar
el estado) queda en un solo lugar. La página es una vista, no un segundo Omni.

**Descartado.**

- **Grabar en el navegador (`MediaRecorder`) y subir el audio**: otra ruta de
audio, otro formato, conversión y permisos del navegador; `rec` ya estaba
  probado y es el mismo camino que la tecla.
- **Un framework (React/Svelte) o un servidor aparte**: una página sola, sin
  build ni dependencias, que se puede leer de punta a punta.
- **Websockets**: el estado va en una sola dirección; SSE alcanza y no suma
  dependencias.
- **Que la página hable directo con el modelo**: duplicaría la limpieza del
  texto, el buzón y el contexto.

**Verificador** `scripts/verify/omni-web.py`: levanta el servidor en un puerto
libre con estado temporal y comprueba página, estado real, canal en vivo,
validación de pedidos y 404. Nunca toca el micrófono ni el modelo.

**El HUD de Quickshell se fue.** `omni-hud.qml` y su unit corrían las 24 h para
una tarjeta flotante que ahora reemplaza la página. Se sacaron del repo y del
sistema: la página no cuesta nada cuando nadie la mira, y el estado sigue en
`status.json` para cualquier otra superficie que quiera leerlo.

## 2026-10-28 — Un grabador por vez, y el español lo dice Kokoro

**Contexto.** El usuario avisó que le hablaba y Omni no lo entendía, mientras
que la página sí. El registro mostraba transcripciones de un video de fondo, y
en el proceso del oído había **siete** `rec` vivos. Además el acento del modelo
sonaba a extranjero leyendo español.

**Qué se eligió.** (1) `grabar()` mata el `rec` que sobró en el `finally`
(sesión propia, `killpg`) y `cmd_oido` toma un `oido.pid`: un solo oído por vez,
y al cerrarlo suelta el micrófono. (2) La voz por defecto la pone `voice`
(Kokoro), que ya habla español parejo en esta máquina; el TTS del modelo queda
como opción con `OMNI_TTS=omni` o `{"tts": "omni"}` en la config. El modelo se
sigue usando para escuchar, que lo hace bien.

**Por qué.** `rec` con `silence` espera sonido para siempre: en una habitación
en silencio el `wait` de 35 s vencía, el grabador quedaba vivo y el bucle
arrancaba otro. A los diez minutos había ocho compitiendo por el mismo
micrófono Bluetooth y ninguno entendía. No era el modelo: era la cola de
grabadores.

**Descartado.**

- **Subir el tiempo de espera**: solo retrasa que se apilen.
- **Detección de voz propia (VAD) en Python**: sox ya sabe cortar por silencio;
  el problema era no matar el proceso cuando no había nada que cortar.
- **Cambiar de modelo por el acento**: el modelo escucha bien y su TTS en
español es lo único flojo; se cambia la boca, no el oído.

**Verificador** `scripts/verify/omni-web.py` suma dos casos: con un `rec` de
mentira que nunca termina, el que sobra queda muerto; y con un `oido.pid` vivo,
el segundo oído se aparta en menos de diez segundos.

## 2026-10-22 — Modo extremo, segunda vuelta: todo afuera, solo SSH/Tailscale

**Contexto.** La primera versión conservaba `rig-main-seat` (la silla del
agente) y `voice-daemon` (voz en CPU). El usuario pidió que se apague **todo**
proceso de fondo y que RAM y VRAM queden al mínimo, dejando vivos solo Tailscale
y lo necesario para entrar por SSH.

**Qué se eligió.** Se suman a la lista `voice-daemon`, `rig-main-seat`,
`audio-jack-guard` y `omarchy-migrate-notify`, y se liberan las cachés del kernel
(`drop_caches`) después de parar todo. Queda vivo únicamente: SSH/Tailscale/red,
la sesión gráfica (Hyprland, shell, idle, lock, polkit, fcitx5, keyd), el keyring
(agente SSH) y la plomería del sistema (dbus, logind, udev, journald, polkit,
upower, pipewire por socket). `scripts/verify/energia.sh` ahora falla si `sshd`,
`tailscaled` o NetworkManager no están activos, o si queda VRAM ocupada.

**Por qué no hay auto-encendido al 10 %.** Con la silla y la voz adentro, entrar
solo al 10 % mataría la sesión del agente sin que el usuario lo haya pedido. El
modo es un interruptor explícito (tecla/menú). La salida al enchufar sí sigue
automática.

**Por qué se conserva una válvula.** `POWER_EXTREME_KEEP_SEAT=1` deja viva la
silla: sirve para probar el modo sin matar la sesión desde la que se prueba (lo
usé para verificar todo lo demás) y para quien quiera seguir hablando con el
agente mientras ahorra.

**Resultado medido (batería, sesión arriba).** RAM 7.8 GB → **3.2 GB**; VRAM
1178 MiB → **2 MiB**; 27 servicios de usuario, 11 timers y 5 servicios del
sistema abajo. SSH, Tailscale y red siguen activos.

Verificación: `scripts/verify/energia.sh`. Doc: `docs/energia-laptop-82y5.md` §8.

## 2026-10-22 — Modo ahorro extremo: apagar el stack propio, y la voz en CPU

**Contexto.** El guard de energía solo tocaba perfil, ASPM, NMI watchdog, una
parte del brillo y syncthing. Con el stack propio arriba (wake word escuchando
siempre, Ollama, Kokoro y Whisper en CUDA, lan-mouse, Sunshine, dos servidores
Node, agentes y timers cada pocos minutos) el piso seguía en ~27 W. El usuario
pidió un modo de batería "extremo, que restrinja hasta todos los procesos en
segundo plano".

**Qué se eligió.** Un interruptor explícito (`power-extreme.sh on|off|toggle`)
que apaga por lista blanca al revés: 25 servicios de usuario, 11 timers/paths y
5 servicios del sistema; brillo 25 %, LED del teclado off, pantalla 60 s/bloqueo
180 s, Wi-Fi power save forzado. Entra solo a ≤10 % de batería y sale solo al
enchufar. El estado de lo que estaba corriendo se registra antes de parar nada,
así `off` restaura exacto.

Dos exclusiones deliberadas:
- **`rig-main-seat` se queda.** Hospeda la sesión del agente y es el canal para
  pedir que se salga del modo; si el modo entró solo al 10 %, matarla dejaba al
  usuario sin interlocutor. Cuesta ~0 en reposo.
- **`voice-daemon` se queda, en CPU.** La salida de voz es el canal de avisos.
  Para que no despierte la dGPU se le instala un drop-in con
  `CUDA_VISIBLE_DEVICES=` y se reinicia; Kokoro pasa a CPU (~0.4-0.8 s por
  frase). Sin eso, el primer aviso hablado dejaba la RTX 4060 despierta toda la
  sesión, que es justo lo que el modo intenta evitar.

**Por qué no tocar el engine de `voice`.** La config tiene motor por idioma y
por perfil; cambiarla dejaba perfiles apuntando a Kokoro igual y, si algo se
interrumpía, quedaba el usuario con otra voz. El drop-in es una sola pieza,
reversible y no toca la config vivo versionada.

**Descartado.** `acpi_call _OFF` / `remove` de la dGPU: irreversible hasta
reiniciar y rompe juegos/streaming (§4.1 del doc de energía). Bajar el techo de
frecuencia: medido, no ahorra (§4.13). Apagar `rig-main-seat`: ver arriba.
También se descartó un daemon que re-aplique Wi-Fi power save tras cada
reconexión de NetworkManager: el guard lo repone al cambiar de fuente y el
verificador lo reporta si se cae.

**Resultado medido.** 26.6 W → 20.8 W (-22 %) con la pantalla encendida al 25 %.
La dGPU sigue activa por Hyprland/hyprpaper (`/dev/nvidia0` abierto): sacarla
pide `AQ_DRM_DEVICES` y reiniciar el compositor, fuera del alcance de un toggle
en caliente.

Verificación: `scripts/verify/energia.sh` (sección "extremo"). Doc:
`docs/energia-laptop-82y5.md` §8.

## 2026-10-20 — Un reinicio corta el buzón de "dime" (lo viejo no se repite)

**Contexto.** El usuario reinició el equipo, dijo "dime" y Omar le leyó una
ráfaga de mensajes de la sesión anterior. El TTL por edad (`dime_max_age_min`,
30 min) no alcanzaba: si los mensajes habían llegado minutos antes de apagar,
seguían siendo "recientes" y se leían como si fueran de ahora.

**Qué se eligió.** El corte es la **hora de arranque del sistema**
(`/proc/stat`, `btime`). `voice dime` descarta los pendientes con `ts` anterior
al arranque: no los borra, los marca `heard` + `expired` con
`expired_reason: "reboot"`, así siguen visibles con `voice messages` (el
usuario los quiere "por si acaso") pero no se leen. Lo que llegó después del
arranque se lee normal. Si no queda nada, en vez de "No hay mensajes
pendientes" dice "No hay mensajes nuevos desde que prendiste".

**Por qué btime y no un servicio de arranque.** No hace falta un estado que se
limpie ni un hook de systemd: leer `btime` es idempotente y no puede quedar
desincronizado (si el proceso arranca tarde, el corte sigue siendo correcto).
Correr `dime` dos veces no cambia nada, y un mensaje nuevo nunca se descarta.

**Descartado.** Un archivo con el `boot_id` que se renueva en el primer `dime`:
habría que escribir estado y decidir cuándo rotarlo, sin ganar nada. También se
descartó vaciar el buzón en el arranque: perdería los mensajes que llegan
entre prender el equipo y el primer "dime".
Verificación: `scripts/verify/voz-dime.sh` (corte por reinicio + historial
conservado).

## 2026-10-20 — Un espacio del escritorio por agente (`espacios`)

**Qué se eligió.** Cada sesión de pi reclama un espacio de Hyprland propio
(11..20, fuera de la rotación del usuario) y todo lo que abre —navegador, video,
visor— nace ahí, sin foco. La pieza es la **clase de ventana**: el agente pone
`agente-<slug>` y una única regla de Hyprland por agente
(`hl.window_rule{name="espacios-<slug>", match={class="^agente-<slug>$"},
workspace="<ws> silent", no_focus=true, suppress_event="activate"}`) la manda a
su espacio. Para apps que no dejan fijar la clase, `espacios abrir` espera la
ventana nueva, comprueba que sea del agente (clase o `PI_AGENTE` en su
`/proc/<pid>/environ`) y la mueve, devolviendo el workspace activo si Hyprland lo
siguió. El agente hereda un directorio de atajos en el `PATH` (`xdg-open`,
`brave`, `kitty`, `mpv`, …) porque nadie se acuerda de usar el comando correcto.
`oa-agent` ahora exporta `PI_AGENTE_WS` y su regla es `silent`: sus sesiones
siguen en el espacio que ya les había asignado. El sonido queda afuera a
propósito: avisos y voz son globales.

**Por qué.** El usuario trabajo con varios agentes a la vez y cada ventana que
abrían le robaba el foco. Los lanzadores ya existentes (`oa-agent`) sólo
aislaban la ventana inicial, no lo que el agente abría después.

**Descartado.** Un daemon que escuche el socket2 de Hyprland y atribuya ventanas
subiendo por `/proc` hasta el agente: se rompe con apps que se daemonizan o se
re-parentan a PID 1, con activaciones por D-Bus y con los singletons del usuario
(Chromium reutiliza el proceso existente y nunca hereda el entorno del agente),
y una ventana en el lugar equivocado es intermitente y difícil de depurar. Los
lanzadores con clase cubren lo mismo sin daemon. También se descartó atribuir
por `pid` en `hyprctl clients`: no es confiable en clientes Wayland nativos.
Verificación: `scripts/verify/espacios.sh` (corre sin escritorio, con
`ESPACIOS_SIN_ESC=1`).

## 2026-10-20 — "dime" avisa con la campana; la espera del micrófono estaba al revés

**Contexto.** Dos mensajes sonaron sin la campana de aviso. No era el buzón: eran
mensajes reales que se leyeron con un `voice dime`. Y al arreglar la señal
apareció otro defecto: `wait_mic_free` esperaba **mientras el micrófono estaba
libre** (la pregunta `micguard --busy` devuelve 0 cuando está libre y el loop
seguía con el valor invertido), así que cualquier reproducción directa podía
quedar colgada 3 minutos.

**Elegido.**

- `dime` llama a `chime --now` antes de leer: primer plano y sin antirrebote, la
  campana es la señal explícita de "te voy a leer". El aviso de llegada sigue
  con antirrebote (una ráfaga = una campana).
- `mic_libre()` (0 = libre) reemplaza el nombre engañoso: `wait_mic_free` usa
  `while ! mic_libre`, y los caminos directos (sin daemon, repeat, inbox, play)
  ya no esperan de más ni hablan con el micrófono tomado.

**Descartado.**

- Bajar el antirrebote del aviso de llegada: una ráfaga de agentes sonaría como
  una alarma. El antirrebote se queda; la señal de lectura es la que suena.
- Que `dime` lea sin campana: el usuario pidió explícitamente el aviso primero.

## 2026-10-19 — El buzón de "dime" es un buffer con edad, no un archivo

**Contexto.** La campana acumulaba mensajes sin límite. Si no decías "dime" en
un rato, te encontrabas leyendo avisos de hace hora y media de tickets que ya
estaban cerrados. Y además `mark-heard` marcaba por `ts`: dos mensajes en el
mismo milisegundo se marcaban juntos.

**Elegido.**

- TTL: más viejo que `[tts] dime_max_age_min` (30 min) se **descarta solo**
  (marcado `expired` en el registro, no se borra del historial).
- Tope del buffer: `[tts] dime_keep` (20); al llegar uno nuevo se tiran los más
  viejos. El buzón nunca crece sin control.
- Tope por lectura: `[tts] dime_max` (6) para un backlog viejo;
  `[tts] dime_max_recent` (12) si todo lo pendiente llegó hace menos de
  `[tts] dime_fresh_min` (15 min). Así una ráfaga reciente se lee de una y un
  backlog viejo no se vuelve un audiolibro.
- Los mensajes nuevos llevan `id` y se marcan por `id`; `ts` queda de respaldo
  para registros viejos.

**Descartado.**

- Borrar los mensajes directamente: se pierde la traza. Se marcan escuchados +
  `expired`.
- Una ventana fija "desde el último dime": la edad desde la llegada es más
  simple y cubre el caso (si no lo pediste, ya no importa).
- Un resumen con modelo local para el backlog viejo: descartado antes; acá se
  resuelve descartando, no resumiendo.

## 2026-10-19 — Los mensajes suenan en campana; "dime" los lee

**Contexto.** Cada mensaje de un agente se hablaba al llegar (o con un híbrido
que igual interrumpía). El usuario quiere un Jarvis: aviso discreto, y la voz
sólo cuando la pide. Speech-to-speech no: es caro y no hace falta.

**Elegido.**

- Nueva entrega `bell` (alias de `mailbox`, ahora la default): campana + mensaje
  al buzón con autor. La campana tiene antirrebote de 8 s (una ráfaga = un
  aviso) y espera a que el micrófono quede libre (`micguard`), igual que la voz.
- `voice dime [N]`: lee los pendientes en orden de llegada,
  `"<agente> dice: <mensaje>"`, con la voz/color de cada agente, tope de 5 y
  texto recortado a 420 caracteres; si quedan, lo dice. `--quiet-empty` para la
  hotword (silencio si no hay nada).
- Hotword `dime` en `~/.local/share/omar/hotwords.json` con
  `launch voice dime --quiet-empty`: cero código nuevo en Omar.
- Se corrigió `pending_messages`: devolvía los pendientes al revés (el último
  primero) pese a que el buzón y `play-inbox` prometen orden de llegada.

**Descartado.**

- Reproducir un resumen con un modelo local: proyecto aparte; la lectura
  secuencial con tope ya resuelve el caso. Si algún día se quiere resumen, va
  como feature separada.
- Un estado nuevo en Omar para "hay mensajes": el buzón de `voice` ya es la
  fuente de verdad y no hay que duplicarlo.
- Exigir "Omar, dime": "dime" a secas es más Jarvis y con la guarda de "sólo si
  hay pendientes" no molesta.

## 2026-10-19 — El TTS nunca habla encima de un dictado

**Contexto.** Estando en dictado, el aviso hablado del cierre de un agente se
solapó con la grabación: el micrófono captó la voz sintética y lo dictado salió
mezclado (y, al revés, Omar podía oír su propio eco). La causa es que había dos
relojes: Omar ya se apartaba del micrófono (`mic-busy`), pero el daemon de TTS
no miraba ese turno y hablaba cuando llegaba el mensaje.

**Elegido.**

- Una sola pregunta compartida, `linux/voice/micguard.py`: ¿hay dictado? Lee el
turno que ya publican `omar dictate` y `handy-dictado` (`mic-busy` y
  `dictate.pid`), valida el PID (vivo, cmdline de dictado, caducidad de 5 min) y,
  como red de seguridad, ve por PipeWire un `handy`/`voxtype` que grabe por su
  cuenta. Se cachea 1 s para no pagar `pactl` en cada vuelta.
- El **daemon** es el único punto de reproducción: antes de sintetizar espera (la
  frase queda en la cola, no se pierde) y durante el `pw-play` revisa cada
  250 ms. Si empieza un dictado, corta y reencola la frase (máx. 3 veces).
- Anota `spoken.log` con la hora **real** del audio: si la frase esperó, el oído
  de Omar no debe tomar su eco como voz propia.
- Los caminos directos del CLI (sin daemon, `repeat`, `inbox play`, `play`,
  `history play`) esperan al dictado antes de sonar.

**Descartado.**

- Bajar el volumen del TTS durante el dictado: sigue entrando al micrófono.
- Descartar el mensaje si hay dictado: el aviso del agente se perdería.
- Preguntar por “cualquier captura del micrófono” (llamadas, grabadores): es más
  agresivo de lo pedido y obliga a mantener una lista de excepciones.
- Duplicar la regla en cada herramienta de dictado: en cuanto aparece una nueva,
  vuelve el bug.

## 2026-10-19 — `liberar`: cerrar lo que no arrancó con el sistema

**Contexto.** Hacía falta una palabra en la terminal para soltar memoria y
procesos que quedaron dando vueltas sin reiniciar sesión ni tocar el escritorio.
El riesgo obvio es matar de más: el systemd de usuario, la barra, el audio o la
propia terminal desde donde se ejecuta el comando.

**Elegido.**

- Clasificar por **cgroup v2**, sin `ps` ni `pgrep` (que en esta máquina están
  tapados por busybox en `~/bin`): solo se mira `user.slice/user-<uid>.slice`.
- Se considera "arranca solo" la unidad cuyo proceso más viejo empezó dentro de
  la ventana (`LIBERAR_VENTANA`, 300 s) de un **ancla**: el `btime` del arranque
  o el inicio de una `session-*.scope` (cada login). Son las dos únicas cosas
  que se conservan sin discutir.
- Los `*.scope` (apps lanzadas a mano) son siempre candidatos; los `.service`
  viejos se respetan, y `liberar -s` baja también esos servicios con
  `systemctl --user stop` (no `kill`, así no los revive el `Restart=`).
- Nunca se toca la **cadena de ancestros de la terminal actual ni su subárbol**
  (si corre dentro de tmux, protege todo el servidor tmux): el resultado tiene
  que verse en la misma ventana.
- `~/.config/liberar/keep.conf` (regex contra cmdline, ejecutable y nombre de
  unidad) es el override humano; los patrones se evalúan **a nivel de unidad**:
  si un solo proceso de la unidad está protegido, no se para la unidad entera.
- `-n` lista y suma RSS antes de matar: es un comando destructivo, así que el
  antes/después se muestra siempre.

**Descartado.**

- `loginctl terminate-user` / `systemctl --user exit`: tira la sesión gráfica
  entera y no se puede ver el resultado.
- Filtrar por antigüedad del proceso o por nombre de app (`matar todo menos
  brave`): no distingue un servidor de usuario de una app abierta, y envejece
  mal.
- `pkill`/`killall` por patrón: mata procesos del sistema y de otras sesiones.

## 2026-10-19 — El crash se diagnostica solo y queda como ticket del rig

**Contexto.** El watcher de Omarchy (`omarchy-crash-watch`) avisaba el crash con
un toast "Click to diagnose with AI": el diagnóstico solo corría si el dueño
hacía click, y no quedaba ticket, traza ni evidencia. Si el aviso se perdía, el
crash se perdía con él. Se quiere que arranque solo y quede visible en el rig
para hacerle seguimiento.

**Elegido.**

- Un watcher propio (`linux/bin/omarchy-crash-autodiagnose`) reemplaza al de
  Omarchy por **drop-in de systemd**, para no editar `/usr/share/omarchy` (se
  pisa en cada `omarchy update`). Conserva la señal (journal `MESSAGE_ID` de
  systemd-coredump), el dedupe por programa, el filtro por usuario y el toggle
  `crash-capture-off`.
- Cada crash abre un **ticket `CRASH-<pid>-<epoch>`** en el proyecto `infra` y
  corre el diagnóstico con **`opencode run` headless** (el mismo agente que ya
  usa el rig), probando **solo modelos free** de OpenCode Zen en orden y pasando
  al siguiente ante 429. Cierra el ticket con evidencia, sesión y evento.
- El diagnóstico se desprende con `systemd-run --user` (unit transitorio) para
  sobrevivir a un reinicio del watcher.
- El método sigue en la skill `diagnose-crash`; el prompt la nombra en vez de
  duplicar pasos.

**Descartado.**

- Diagnóstico con Pi headless: los modelos free de Pi que responden son solo
  `opencode-go/longcat-2.5-preview-free` y `cat-jam-free` (el resto da 403
  `FreeTierError` o 400 "unavailable"), y las trazas de Pi no entran en el
  tablero de tickets del rig. OpenCode da muchos más modelos free y el ticket
  nativo del rig.
- Habilitar `pi-model-fallback` global: el fallback vive en el propio script
  (lista de modelos free), sin cambiar el comportamiento de todas las sesiones.
- Lanzar el diagnóstico en una silla tmux interactiva: nunca cierra sola, así
  que el ticket no se podría cerrar solo. `opencode run` headless sí termina.

## 2026-10-18 — Un worktree por agente, y dos flujos por proyecto

**Contexto.** Varios agentes trabajando en el mismo repo compartían carpeta y
rama: se pisaban archivos, un `git add -A` se llevaba trabajo ajeno y el árbol
quedaba sucio sin dueño (pasó en foldertinder: 55 archivos sin commitear en
`master`, dos stashes de "dead-batch" y un worktree viejo convivendo). El usuario
quiere que cada agente tenga su versión del código, pero sin imponer una rama de
desarrollo en proyectos donde no la necesita.

**Elegido.**

- `~/.pi/agent/worktrees.json` (versionado acá) declara el flujo de cada
  proyecto: `main` (base y merge en la rama principal), `developing` (base y
  merge en la rama de desarrollo) o `directo` (se edita en el lugar, sin
  worktree: dotfiles). Lo no listado usa `flujoPorDefecto = main`.
- `extensions/worktrees.ts` hace cumplir la regla: reglas en el system prompt de
  cada turno, bloqueo de `write`/`edit` y de los comandos bash que escriben en la
  copia principal, un worktree automático por subagente y la tool `worktree`
  (`abrir` / `lista` / `cerrar`, que mergea y limpia).
- La decisión pura (flujos, rutas, detección de comandos que escriben) vive en
  `extensions/lib/ramas.ts` con tests; lo impuro (git) en la extensión.
- `rig work new` lee la misma config para elegir la rama base.
- Escape hatch: `/worktrees libre` o `PI_SIN_WORKTREES=1`, para operaciones
  puntuales sobre la copia principal.

**Descartado.**

- Forkear el ejemplo `subagent` de pi para inyectarle worktrees: se
  desactualiza con cada versión de pi. En cambio, la extensión muta la llamada a
  `subagent` en `tool_call` y le cambia el `cwd` a cada tarea.
- Dejar la regla solo como consejo en el prompt: ya se probó y los agentes
  igual editan la copia principal cuando apura.
- Crear una rama `developing` nueva en `zentr0`: ya tiene `dev`, así que la
  config apunta ahí en vez de inventar historia.
- Un `.env`/flag por repo dentro de cada proyecto: la config central es un solo
  lugar para los dos consumidores (pi y rig).

## 2026-10-17 — Un solo visor del pensamiento y tareas con id

**Contexto.** El widget de `conversar.ts` mostraba el pensamiento en vivo, pero
pi también dibujaba el bloque nativo en el transcript: se leía dos veces. El
ritmo fijo no alcanzaba cuando el modelo pensaba muy rápido y los cortes
mostraban fragmentos de código o frases partidas. Además no había forma de
saber qué tarea estaba haciendo cada agente ni de reconstruir cómo llegó a la
solución.

**Elegido.**

- El widget es el único visor en vivo. El bloque nativo se oculta con
  `hideThinkingBlock: true`; `Ctrl+T` lo muestra si hace falta.
- Encabezado en una fila: `agente × título · id`. Se publica también en el
  título de la ventana para herdr/la barra.
- Ritmo adaptativo: 150 ms/palabra cómodo, 100 ms cuando la cola supera 40
  palabras; si igual sobra, se descartan las oraciones viejas.
- El texto pasa por helpers puros (`lib/pensamiento.ts`): saca fences, ANSI,
  URLs y code inline ilegible, y descarta fragmentos que terminan en conector.
- Las tareas viven en `rig.ts`: id `T-XXXXXX`, título automático, trace de
  pedidos, herramientas, resultados y pensamientos, más el enlace a la sesión
  completa. Continuaciones cortas se anexan a la tarea; un pedido distinto abre
  otra.
- Los helpers viven en `extensions/lib/` (sin `index.ts`) para que pi no los
  cargue como extensión.

**Descartado.**

- Frenar el render nativo del pensamiento: pi no expone una velocidad de
  streaming; el widget es la única capa que se puede dosificar.
- Copiar el texto completo del pensamiento a `tareas.json`: duplicaría la
  sesión y crecería sin control. Se guarda un resumen por mensaje y el enlace
  al archivo de sesión.
- Que el modelo tenga que crear la tarea a mano en cada turno: costo y olvidos.
  Se captura sola; el modelo solo la renombra o anota si hace falta.

## 2026-10-18 — El cerebro de voz pasa de Pi a Hermes

**Contexto.** Omar (el asistente de voz, wake word "omar") resolvía lo que no
era comando fijo con Pi headless (`voice-pi`) a través de `pi_shim.py`. El
usuario usa Hermes como harness y quiere que Omar corra ahí, con el mismo
modelo que ya usa Hermes (`deepseek-v4.1-flash` de opencode-go), cubierto por
su plan y sin costo por token.

**Elegido.**

- `linux/bin/voice-hermes`: `hermes -z` dentro de `linux/voice/pi-brain/`, con
  `--toolsets terminal` (muchos menos esquemas: el prompt baja de ~46 KB a lo
  mínimo) y el `AGENTS.md` del cerebro, que Hermes ya carga por CWD.
- `pi_shim.py` apunta a `voice-hermes` por defecto. `VOICE_BRAIN_BIN` manda;
  `VOICE_PI_BIN` queda por compatibilidad con configs viejas.
- `voice think` y `omar ask` llaman a `voice-hermes`. `voice-pi` sigue
  existiendo como variante explícita.
- El guard de comandos destructivos (`pi-brain/guard/`) se comparte: los
  symlinks de `omarchy`/`systemctl`/`reboot` siguen haciendo la confirmación
  hablada sin importar el harness.
- El modelo no se fija en el script: es el default de `~/.hermes/config.yaml`,
  para que haya una sola fuente de verdad. `VOICE_HERMES_MODEL` y
  `VOICE_HERMES_PROVIDER` permiten pisarlo.
- `voice-pi-shim.service` conserva el nombre (histórico) para no migrar links,
  timers ni la config de Omar.

**Descartado.**

- `deepseek-v4.1-flash-free` de OpenCode Zen: es el mismo modelo gratis, pero
  su capa gratuita sólo atiende al cliente de OpenCode (`HTTP 403: free tier
  can only be used from within OpenCode` desde Hermes y desde `pi`). No es una
  opción real fuera de esa app.
- Renombrar el servicio a `voice-brain-shim.service`: obliga a migrar enlaces y
  unidades por un nombre, sin ganar nada funcional.
- Un script genérico con ramas Pi/Hermes: más código para una sola decisión de
  harness. Si mañana vuelve a cambiar, se agrega otro `voice-*` y se cambia
  `VOICE_BRAIN_BIN`.

## 2026-10-18 — Pi arranca en pensamiento `low`

**Contexto.** El nivel de razonamiento quedaba en `high` al reanudar sesiones y
para sesiones nuevas, lo que encarece y demora el trabajo de todos los días sin
que el usuario lo haya pedido.

**Elegido.** `defaultThinkingLevel: "low"` y
`modelThinkingLevels: {"deepseek/deepseek-flash": "low"}` en
`linux/pi/agent/settings.json`. Las sesiones ya abiertas conservan su nivel
hasta que se cambie con `/thinking`; las nuevas arrancan en `low`.

**Descartado.** Forzar `--thinking low` en cada invocación: no cubre las
sesiones interactivas y duplica la config.

## 2026-10-18 — El cerebro de voz arranca gratis

**Contexto.** El usuario quiere empezar desde lo más barato (gratis) y pagar
sólo si no alcanza, nunca al revés. Hermes venía con
`deepseek-v4.1-flash` (opencode-go): barato, pero pago.

**Elegido.**

- En `~/.hermes/config.yaml`: primario **`cat-jam-free`** y cadena de respaldo
  **`beam-free`** y **`longcat-2.5-preview-free`**, los tres gratis del plan
  opencode-go. Omar hereda ese default.
- Medidos con tareas reales del cerebro (foco, ventanas del workspace 5,
  volumen, multi-paso en dry-run): `cat-jam-free` y `beam-free` 3–5 s y
  `longcat-2.5-preview-free` 13–18 s; los tres usan herramientas y aciertan.
  `cat-jam-free` primario por balance calidad/latencia, `beam-free` de respaldo
  rápido y `longcat` por si hace falta más cabeza.
- `scripts/verify/cerebro.sh` falla si el modelo primario o un respaldo dejan
  de ser gratis: la regla "nunca pagar primero" queda chequeada.
- `VOICE_HERMES_MODEL` no está fijado: cambiar de modelo es editar la config de
  Hermes, un solo lugar.

**Descartado.**

- `deepseek-v4.1-flash` como primario: más capaz, pero es exactamente el orden
  que el usuario no quiere.
- Un respaldo pago: gastaría solo, sin que el usuario lo pida. Si los gratis no
  alcanzan, se decide entonces, no de antemano.

## 2026-10-19 — La actividad de los agentes va a una bodega unificada (NDJSON + SQLite)

**Contexto.** Los agentes se hablan, abren tickets y dejan eventos, pero todo
queda en archivos sueltos sin IDs estables entre sí: el buzón de correo
(`~/.local/state/rig/correo`), el feed de eventos, los dos tableros de tickets
(rig y pi) y las sesiones de pi. Se quiere guardar todo junto para poder subirlo
alguna vez a la nube y leerlo desde varias aplicaciones.

**Elegido.**

- Un log **append-only en NDJSON** (`~/.local/share/rig/db/unificado.ndjson`) como
  fuente de verdad y unidad de réplica: idempotente, con id determinista por
  hecho, sin cursores que se rompan cuando un archivo muta (el buzón reescribe
  `leido` in-place y los tickets se reescriben enteros, así que se releen enteros
  y se deduplica por id).
- **SQLite reconstruible** (`rig.db`, con FTS5) como vista de consulta, no como
  fuente. Se puede borrar y regenerar del NDJSON.
- Los archivos originales **siguen siendo la fuente de escritura**: no se reescribe
  rig para que use una base.
- `sync` se corre al mandar un mensaje, al tocar un ticket y desde un timer
  opcional de systemd; no hay daemon.
- Contenido crudo de sesiones y `opencode.db` quedan afuera: se indexa metadata
  y se referencia la ruta.

**Descartado.**

- API HTTP propia, outbox/CDC y esquema cloud desde el arranque: no hay
  consumidor todavía, y se agregan después sin cambiar la ingesta.
- Ingerir `opencode.db` (3,6 GB): acopla a un esquema ajeno y cambiante, y es la
  fuente de menor valor para este objetivo.
- Postgres/Supabase ya: SQLite no sirve multi-escritor en la nube, pero el NDJSON
  es el formato de importación cuando haga falta. Ver `docs/bodega-agentica.md`.

## 2026-10-19 — El cerebro de voz vive con la sesión gráfica

**Contexto.** El 2026-10-19 a las 04:25 la sesión gráfica se reinició (logout/
login) y `voice-pi-shim.service` no volvió: quedó `inactive (dead)` con el
proceso terminado por SIGTERM en el teardown. Estuvo 9 horas caído y Omar
contestaba "no pude resolver eso" — el `fetch` al `127.0.0.1:11435` fallaba y el
error solo se logueaba. Dos causas juntas: la unidad era `WantedBy=
default.target` (sin `PartOf=graphical-session.target`, así que el reinicio de la
sesión no la levantaba) y `Restart=on-failure` no revive un TERM externo.

**Elegido.**

- `After=`/`PartOf=`/`WantedBy=graphical-session.target`, igual que
  `voice-daemon`: el cerebro vuelve solo cuando vuelve la sesión.
- `Restart=always` + `StartLimitIntervalSec=0`: si el proceso muere por una
  señal externa, systemd lo levanta; sin tope de reintentos.
- La unidad entra en `enabled-laptop.txt` para que `install-user-units.sh` la
  enlace al repo (symlink). Antes era una copia suelta y driftaba en silencio.
- `scripts/verify/cerebro.sh` ya avisaba del drift del `AGENTS.md` del cerebro;
  se copió el del repo. La copia viva decía `omar ticket …`, que no existe:
  el CLI de tickets es `omar-hub`.

**Descartado.**

- Un healthcheck externo con timer que reinicie el puente: systemd ya puede
  hacerlo desde la unidad, sin proceso extra ni latencia.
- Dejar el puente en `default.target` y atarlo por `Wants=` desde `omar-listen`:
  mezcla ciclo de vida de sesión con ciclo de vida de usuario.

## 2026-10-19 — Cortar la voz la calla, no la degrada

**Contexto.** Con la tecla física de Windows `present-remote toggle` cierra a
Omar, que manda `voice stop`. El daemon hacía `pkill -f pw-play` y el
`synth_and_play` tomaba el playback muerto como "falló el motor", así que
reintentaba la MISMA frase con piper y después espeak: en vez de silencio se
oía otra voz, peor. Además el `pkill` por patrón se llevaba earcons, chimes y
cualquier otro `pw-play` (y hasta un shell cuyo comando mencionara el patrón).

**Elegido.**

- Un contador de generación (`_play_epoch`) que sube en `stop`; `_play` lo mira
  y devuelve `cancelled` en vez de `error`. En `synth_and_play`, `cancelled`
  corta la cadena de motores; `error` sigue cayendo a piper/espeak como antes.
- Se chequea el epoch antes de sintetizar y antes de reproducir: si el corte
  llega durante la síntesis, la frase se descarta (no suena después).
- El playback se corta por **PID** (`_current_play.terminate()`), no con
  `pkill -f`. `voice repeat` usa un patrón anclado (`^pw-play .*Voice TTS`).

**Descartado.**

- `pkill -f "Voice TTS"`: más acotado que `pw-play`, pero seguía matando
  procesos ajenos que mencionaran el texto (medido: mató el shell del test).
- Marcar el corte con un archivo con vencimiento: ventana arbitraria, decide
  por tiempo lo que ya se sabe por generación.

## 2026-10-19 — Cancelar la voz responde en el acto (y calla aunque Omar esté apagado)

**Contexto.** Medido el recorrido de la tecla de Windows: `voice-key-listener`
tenía un antirrebote de 800 ms que **descartaba la segunda pulsación**, así que
"cerrar y que se calle" no hacía nada hasta apretar otra vez. `present-remote`
decidía con `qs ipc` (dos intentos, ~60-150 ms), cerraba la UI antes de avisar
al oído, y la señal iba por `systemctl kill` (un proceso extra). Peor: si Omar
estaba apagado y hablaba un aviso de otro agente, la tecla **prendía a Omar** y
la voz seguía sonando; había que apretar de nuevo para callarla.

**Elegido.**

- Una pulsación, una acción: se elimina el antirrebote por tiempo; el "down"
  repetido al mantener ya lo cubre el flag por pulsación.
- La píldora se lee de `pill-open` (el archivo que publica el propio QML y que
  el glow ya usa). `qs ipc` queda como respaldo si el archivo no existe.
- Si no hay Omar activo pero `speaking.json` está vigente, la tecla/`Escape`
  cortan el audio (`voice stop`) en vez de prender a Omar.
- Cerrar: `SIGUSR2` por `listen.pid` + `kill(2)` (validando la línea de
  comandos del PID) y `voice stop` en paralelo; UI y limpieza de PTT después,
  con topes cortos (1,0 / 0,6 / 0,3 s) para no trabar la próxima pulsación.

**Descartado.**

- Sólo adelantar la señal y esperar al loop de Omar: medido ~80 ms extra; el
  `voice stop` directo baja la pulsación→silencio a ~60 ms.
- Depender de `status.json` para saber si Omar está despierto: lo publica
  también el dictado y llega con retardo; `pill-open` es el estado de la
  superficie que el usuario ve.
- Un antirrebote más corto (100-200 ms): sigue perdiendo pulsaciones rápidas y
  no aporta nada que el flag de pulsación no resuelva.


## 2026-10-19 — El presupuesto de RAM se mide y se verifica, no se estima

**Problema.** El core residente de la máquina (sistema + escritorio + voz +
visión) se iba a ~5,8 GB sin que nadie pudiera decir cuánto pesaba cada parte ni
cuándo se pasaba del límite. Las discusiones sobre "Omar pesa demasiado" se
hacían con `free -h`, que no distingue core de satélites ni memoria privada de
compartida.

**Decisión.**

1. `linux/bin/res-budget` mide con **PSS** (`smaps_rollup`), no con RSS: RSS
   cuenta dos veces cada página compartida y hace que dos procesos que comparten
   los mismos pesos inflen el número. Clasifica por la **unidad systemd del
   cgroup**, que es más fiable que adivinar por `cmdline`.
2. El presupuesto aplica sólo al **core** (kernel + sistema + escritorio + voz +
   visión). Los satélites (agentes, editores, navegadores, servidores de
   desarrollo) son de demanda y no cuentan.
3. `res-budget.timer` lo corre cada 15 min y avisa por notificación si el core
   excede el límite. `RES_BUDGET_MB` lo cambia sin tocar código.

**Medido la primera vez que corrió.** Core 5,8 GB de 8,2 GB: kernel 564 MB,
escritorio 399 MB, sistema 81 MB, visión 516 MB y **voz 4,3 GB (74 % del core)**.
El límite no lo rompe el core: lo rompen los satélites.

**Descartado.**

- Medir con RSS: sobrecuenta la memoria compartida y no permite comparar entre
  configuraciones.
- Presupuesto sobre "toda la RAM usada": mezcla core con trabajo del usuario y
  no dice nada accionable.
- Un umbral en `res-reap` en vez de un medidor propio: `res-reap` mide
  `MemAvailable`, que es un síntoma, no una causa.

## 2026-10-19 — `shell.json` por máquina (fin del ping-pong del auto-sync)

**Problema.** La pantalla de la laptop parpadeaba: pasaba un instante a escala 1
y volvía a 2, y alguna vez quedaba chica. La causa encadenada: (1) las dos
máquinas exportaban **el mismo** `linux/config/omarchy/shell.json`, y `jq -S`
ordena claves pero **no arrays**, así que el orden de los widgets de la barra
oscilaba; (2) cada oscilación generaba commit de autosync → pull en la otra
máquina → `omarchy-sync.sh import` → `omarchy-restart-shell`; (3) al recrearse
la barra, el plugin `better-displays-pro` corre `restore-after-reload` 3 s
después del arranque y reaplica el layout con `hl.monitor`, o sea un mode set
sobre eDP-2 (2880x1800@120 scale 2) que se ve como el parpadeo.

**Elegido.**

- Cada máquina escribe `linux/config/omarchy/shell.<machine>.json`
  (`~/.config/machine-type`) y lo importa de ahí. `shell.json` queda solo como
  fallback de instalación nueva: el código ya tenía el override por máquina,
  pero el archivo nunca se creó, así que todo caía al compartido.
- `import` calcula una huella de lo que el shell carga de verdad (`shell.json`,
  `shell.toml`, `bar/`, `extensions/`, `plugins/`) y **no reinicia** el shell si
  el import no la cambió. Antes reiniciaba siempre, incluso cuando el pull solo
  traía fondos o docs.

**Descartado.**

- Canonicalizar el array de widgets con `jq` para que ambas máquinas exporten
  bytes iguales: el orden de la barra es una decisión del usuario, no ruido; y
  cualquier widget nuevo volvería a desincronizarlo.
- Quitar `omarchy-restart-shell` del import: sin reinicio no se aplican cambios
  reales de barra/plugins.
- Tocar el plugin `better-displays-pro` (es plugin git, no vive en el repo): la
  reaplicación del layout es su diseño; el problema era la frecuencia.

## 2026-10-20 — El auto-sync distingue red de conflicto (no más agentes inútiles)

**Problema.** Cada tanto aparecía el aviso crítico "Dotfiles: conflicto de
sync — Un agente headless va a intentar resolverlo" y despertaba un agente Pi
completo. En el log no había conflictos: `git pull` moría con `Recv failure:
Connection reset by peer`, `Error in the HTTP2 framing layer` o `TLS connect
error`. El script trataba **cualquier** fallo del `pull` como conflicto de
rebase. Dos causas concretas:

1. Se usaba `git pull`, que **vuelve a hacer fetch** justo después de que el
   `git fetch` ya había funcionado. La red entraba de nuevo en el camino
   crítico, y su fallo se confundía con contenido en conflicto.
2. `git_net` (el reintento por HTTP/1.1) se usaba en `fetch` y `push`, pero no
   en el `pull`; y el `push` también escalaba al resolutor cuando fallaba por
   red, aunque el commit ya estuviera hecho.

**Elegido.**

- El paso de integración es un `git rebase --rebase-merges --autostash`
  contra `origin/$BRANCH`, el ref que se acaba de descargar: sin red no hay
  fallo de red posible.
- Si el rebase falla, se distingue: `conflicto_real` (archivos sin fusionar o
  rebase a medio hacer) escala al resolutor con aviso crítico; cualquier otra
  cosa se registra como WARN y se reintenta en el ciclo siguiente.
- `git_net` guarda el último error en `GIT_NET_ERR` y `net_error` lo clasifica.
  Un `push` que falla por red deja el commit local y no despierta a nadie.

**Descartado.**

- Mirar el texto del error del `pull` para detectar red: con `git pull` el
  error puede venir del fetch, del rebase o del autostash, y el mensaje es
  ambiguo. Quitando la red del paso desaparece la ambigüedad.
- Silenciar solo la notificación: el agente headless se seguía lanzando (hasta
  900 s de `pi` por un corte de red).
- Reintentar el `pull` completo con HTTP/1.1: vuelve a descargar lo que ya está
  en `origin/$BRANCH`.

## Motor de movimiento: una fuente de tokens, tres primitivas y un laboratorio

**Contexto.** Cada widget animaba a mano: duraciones literales, apariciones y
desapariciones con `visible: false`, ningún vocabulario común entre la barra,
los plugins y las apps. El objetivo es calidad de software de alto nivel
(morphs, persistencia, nada que se corte de golpe) sin reimplementarla en cada
widget.

**Elegido.**

- `motion.json` como única fuente de duraciones, curvas, escalonado y resortes.
  Lo lee `Tokens.qml` (singleton) y lo lee cualquier app futura; sin codegen y
  sin build step.
- Tres primitivas v1: **Reveal** (entrada/salida pareadas, contenido montado),
  **Morph** (una línea de tiempo con escalonado y barrido direccional, drag y
  asentado) y **Frames** (frames parejos al display para canvas). **Shared**
  (persistencia entre superficies) queda para v2.
- `Morph.advance(ms)` es línea de tiempo pura: el `FrameAnimation` la alimenta
  con el tiempo real y los tests la llaman a mano. El verificador de movimiento
  es determinista y no depende del render.
- El motor se **vendoriza** como subdirectorio del consumidor porque Quickshell
  rechaza imports que suben de directorio (`Reveal is not a type`). Un script
  único copia y el verificador falla si una copia se desvía.
- El laboratorio (`eztvn.motion`) es el criterio de aceptación visual. El
  interruptor maestro se prueba ahí de verdad, con `hyprctl` incluido.

**Descartado.**

- Codegen de tokens a QML/CSS: un archivo JSON leído al inicio alcanza.
- Un reloj global: cada morph tiene su línea de tiempo; un reloj compartido
  termina animando cosas que no lo pidieron.
- Empezar por la persistencia cross-window: en Wayland depende de un overlay
  `layer-shell` exacto sobre otras superficies y pelea con las animaciones del
  compositor. Antes va un spike de un día con criterio de corte explícito.
- Migrar los 38 lugares con duraciones literales de una vez: se migran por
  impacto visual y cada carpeta tocada pasa el verificador.

## Fábrica de ideas: capturar en vez de perder

**Contexto.** El usuario piensa en voz alta todo el tiempo ("¿se podría usar un
teléfono viejo como cerebro y dejar el portátil de pantalla?"). Esas ideas se
contestaban en el chat y se perdían con la sesión. También quería poder
revisarlas después, abrir conversaciones alrededor de una idea y descartar las
que no van. Necesita memoria externa, no que el agente decida por él.

**Elegido.**

- **Un archivo Markdown por idea** en `~/.local/share/pi/ideas/`, con
  frontmatter (id, estado, etiquetas, fechas, origen) y cuerpo con la idea, qué
  la haría funcionar, dudas y **conversación append-only** (fecha + agente).
  Nada de base de datos: el usuario lo abre con `cat` y el agente lo lee igual.
- **Un CLI, dos consumidores**: `linux/bin/ideas` (node, sin dependencias) es la
  única implementación; la extensión `ideas.ts` la invoca por `execFileSync` y
  expone la tool `idea` + los comandos `/ideas` y `/idea`. Cero lógica duplicada.
- **Captura automática por system prompt**, no por pedido: la extensión inyecta
  la regla en `before_agent_start` (igual que `rig.ts`). Si el mensaje es una
  idea o pregunta especulativa, se guarda antes de responder. Preguntar
  "¿querés que lo guarde?" rompe el flujo y la idea se pierde.
- **Descartar no borra.** El estado pasa a `descartada` con el motivo escrito y
  la idea queda fuera del listado por defecto (`--todas` la muestra). Se puede
  reabrir sin perder la conversación; descartar es una decisión, no una pérdida.
- **`ideas charlar IDEA-XXXX`** abre una sesión de pi con el archivo de la idea
  como contexto: es el puente entre "idea guardada" y "conversación en torno a
  ella", que es lo que el usuario pidió.
- **Verificador determinista** `scripts/verify/ideas.sh`: corre el CLI completo
  sobre un directorio temporal (nunca toca las ideas reales) y comprueba además
  que la extensión declare tool, comandos y regla, y que la skill cargue.

**Descartado.**

- **Guardar las ideas dentro de `tareas.json`/`trazas`**: una idea no tiene
  dueño, ni estado de trabajo, ni pasos. Mezclarla con los tickets ensucia las
  dos cosas y el usuario no las encuentra.
- **Base de datos o app aparte**: más superficie, más migraciones, y el usuario
  quiere ver las ideas en la terminal y en el editor.
- **Que el agente pregunte antes de capturar**: la respuesta útil se demora y la
  idea se pierde cuando el usuario cambia de tema. Se captura, se contesta, y si
  no le interesaba, se descarta con un motivo.
- **Capturar tareas**: "arreglá el bug del panel" es un ticket; convertirlo en
  idea llena la fábrica de ruido y le quita sentido a la lista.
- **Borrar ideas**: el valor de la fábrica es la colección. Sin la idea
  descartada y su motivo, se vuelve a discutir lo mismo en tres meses.

## 2026-10-30 — Suspender con la grilla abierta ya no deja el teclado muerto

**Problema.** Al volver de suspensión el escritorio quedaba sin atajos: no se
podía cambiar de workspace, ni mover/redimensionar ventanas, ni usar los gestos
con Súper. `hyprctl submap` respondía `hyprexpo` sin que hubiera grilla en
pantalla. El compositor (no el overview) conserva el submap al suspender; el
overview sí muere, así que su cierre normal —que restaura el submap— nunca
ocurre. Con `submap=hyprexpo`, todos los binds del escritorio son ocultados por
el submap y sólo queda el `catchall` que lo resetea, lo que hace que el primer
atajo se "pierda" y el resto parezca deshabilitado.

**Elegido.**

- `system-sleep/keyd-resume.sh`: después de reiniciar keyd, cerrar el overview
  si quedó abierto (`hyprexpo.expo("cancel")`), esperar a que termine su
  animación y recién entonces `hl.dsp.submap("reset")`. El orden importa: el
  plugin restaura el submap que capturó al abrir y puede volver a pisarlo.
- El reset se hace `setpriv --reuid=<uid>` sobre cada instancia de Hyprland viva
  en `/run/user/*/hypr/*` (con `timeout 5`): el hook corre como root, sin el
  entorno del usuario. `runuser -u '#uid'` no acepta uids numéricos.
- `asistente/scripts/tecla.sh`: al reconectar `keyd monitor` (keyd se reinicia
  en cada resume) mandar `soltar`. Si la tecla estaba apretada y el `up` se
  perdió, el asistente quedaba escuchando para siempre.

**Descartado.**

- **Resetear el submap sólo con un bind manual**: el usuario tendría que saber
  que existe y acordarse justo cuando ningún atajo responde.
- **Parchear el plugin para que nunca restaure `hyprexpo`**: también
  corresponde, pero exige rebuild y reiniciar Hyprland, y no cubre los otros
  submaps (`dictado`, `moonlight`) que tampoco deben sobrevivir a un suspend.
- **Resetear en el hook `pre`**: todavía hay que dejar que el cierre del
  overview corra después del resume; en `pre` el compositor se congela.
