# Sistema de voz local (Linux/wayland)

Infraestructura de voz 100% local para interactuar verbalmente con el
ordenador. Integrada con **OpenCode**. Capas separadas y reutilizables.

```
MICROFONO
   │
   ▼
STT (Handy, GPU Vulkan / CPU)
   │
   ▼
voice-daemon (orquestador)  ◄── FIFO/socket + CLI `voice`
   │                              ▲ Pi · OpenCode · barra · notificaciones (swaync)
   │
   ▼
TTS Router (por idioma): kokoro → piper → espeak-ng
   │
   ▼
AUDIO (PipeWire / pw-play)
```

## Capas

| Capa | Archivo | Responsabilidad |
|------|---------|-----------------|
| Config | `linux/voice/engine.py` + `~/.config/voice/config.toml` | defaults, detector hardware, router TTS por idioma, selector STT |
| Daemon | `linux/voice/daemon.py` | cola TTS, dedup, playback, fallback de motores |
| TTS neural | `linux/voice/kokoro.py` (+ env `voice-kokoro`) | Kokoro-82M (mejor calidad) |
| TTS ligero | piper (voces), espeak-ng (fallback último) | fallback / batería |
| STT | `linux/voice/stt.py` | wrapper de `handy --transcribe-file` |
| CLI | `linux/bin/voice` | comandos (status, speak, listen, benchmark...) |
| OpenCode | `~/.config/opencode/plugins/voice/plugin.js` | resumen al terminar, permiso, error, inyección de voz |
| Puente notificaciones | `linux/config/swaync/config.json` (script `voice ingest-notify`) | legado: swaync ya no corre; ver «Captura de notificaciones» |
| Widget barra | `omarchy/plugins/eztvn.pi-tts` | interruptor TTS, volumen, registro de mensajes y repetir |

Toda configuración vive en el repo (`~/dotfiles`). Los destinos
(`~/.config/voice`, `~/.local/bin/voice`, `~/.local/bin/voice-daemon`) son
symlinks generados por home-manager (`nixos/home.nix`).

## Paquetes (nixos/modules/packages.nix)

- `piper-tts`, `espeak-ng`, `sox` — TTS ligero + grabación (`rec`).
- `piperVoices` — voces piper fetchurl (es_MX-claude-high, es_MX-ald-medium,
  es_ES-davefx-medium, en_US-amy-medium) a `/run/current-system/sw/share/piper-voices`.
- `voice-kokoro` — env python con `kokoro` (torch CPU). Modelo
  `hexgrad/Kokoro-82M` se descarga al primer uso (`~/.cache/huggingface`).
- `handyPackage` — **STT** (Handy + whisper-medium Q8, GPU Vulkan). Ya estaba instalado.
- No hay CUDA/faster-whisper/unfree: STT GPU usa **Vulkan** de Handy (sin compilar nada).

## Modelos de voz

### TTS
- **Kokoro-82M** (principal EN, calidad A): voces EN `af_heart`, `af_bella`,
  `af_nicole`, `bf_emma`; ES `ef_dora` (mujer), `em_alex`/`em_santa` (hombre).
  Español de Kokoro es limitado (3 voces, sin grado de calidad).
- **Piper** (principal ES): `es_MX-claude-high`, `es_MX-ald-medium`,
  `es_ES-davefx-medium`; EN `en_US-amy-medium`. Español piper es fuerte.
- **espeak-ng**: fallback extremo (robot, pero ligero y offline).

### STT (Handy)
- `whisper-medium` (Q8) instalado, multilingual (bueno para ES). GPU vía Vulkan.
- Otros: `nemotron-3.5-asr`, `parakeet-tdt-v3`. Ver `voice model list`.

## TTS Router por idioma

Cada idioma tiene su motor y voz (`config.toml` + `engine.py`):

```toml
[tts]
enabled = true
lang = "es"            # idioma por defecto
mode  = "summary"      # summary | full
engine_es = "piper"    # voz ES principal
voice_es  = "es_MX-claude-high"
engine_en = "kokoro"   # voz EN principal
voice_en  = "af_heart"
```

Al hablar: `tts_command(lang)` devuelve `{engine,voice}` por idioma. El
daemon construye una **cadena de fallback** `engine → piper → espeak`; si
el principal falla, baja de nivel. Conmutación entre motores sin tocar las
aplicaciones que solo hacen `voice speak`.

## Configuración / estado

- Config (committed, symlink a `~/.config/voice/config.toml`): defaults.
- Estado runtime (`~/.local/state/voice/state.json`): sobreescrituras locales
  por máquina (fuera del repo). `voice set stt accelerator gpu` escribe aquí.
- Registro de mensajes (`~/.local/share/voice/tts/`): WAVs + `messages.jsonl`
  de todo lo que se habló o notificó (ver más abajo).

## Registro de mensajes del sistema

Cada mensaje que el sistema le entrega al usuario queda en
`~/.local/share/voice/tts/`, en `messages.jsonl` (una línea JSON por mensaje)
y los audios en `recordings/tts-*.wav`. Hay dos clases:

- `kind="voice"`: además hay WAV en `recordings/` y se reproduce tal cual.
- `kind="notify"`: notificación de escritorio capturada por el puente de
  swaync (ver abajo); al repetirla se sintetiza.

Una notificación y su versión hablada con el mismo texto (dentro de
`VOICE_MESSAGE_MERGE_MS`, 120 s) se funden en una sola entrada que conserva el
audio. Se conservan las **últimas 200**; `VOICE_HISTORY_MAX` cambia el tope y
`VOICE_HISTORY_DIR` la ruta. (El antiguo `history.jsonl` se migra solo la
primera vez.)

El widget de barra `eztvn.pi-tts` lista los mensajes (con un icono por tipo),
reproduce cualquiera con un clic, tiene «Repetir última» y muestra un contador
(badge) de mensajes pendientes; el volumen relativo se ajusta ahí mismo o con
`voice volume`.

```bash
voice messages [--json] [N]  # registro unificado (más reciente primero)
voice repeat                 # repite el último mensaje
voice repeat 3               # repite los últimos 3 (en orden cronológico)
voice repeat --index 2       # repite el mensaje 2 (1 = el más reciente)
voice history [--json] [N]   # solo las frases habladas (compatibilidad)
voice history play 1         # reproduce el WAV de la entrada 1
voice history clear          # vacía índice y WAVs
```

## Identidad de cada agente (nombre, rol y color)

Cada agente tiene **nombre**, **rol** y **color**, y ese color es el mismo en
*todas* las superficies: los subtítulos del glow, el fondo del panel de tmux, el
icono de la barra y las notificaciones. Así se reconoce quién habla de un
vistazo. La fuente única es `linux/voice/identity.py`:

- El color se deriva del **nombre** (hash estable) si no hay uno fijado, con la
  misma idea que el reparto automático de voces: un agente nuevo ya nace con su
  color y nunca cambia.
- El **rol** es la función (`main`, `audio`, `dotfiles`, `general`, …). Si el
  nombre coincide con un rol conocido, ese es su rol; si no, sale de
  `PI_AGENT_ROLE`. El rol da color por defecto a los agentes de esa función.
- El daemon publica `name`, `role` y `color` en `speaking.json` junto al texto
  que habla; el glow y la barra lo leen y pintan con ese color.

```bash
voice identity main --json     # {name, role, color, voice}
voice color audio              # hex del agente
voice color audio --tint       # versión oscura (fondo de panel)
voice color puma --set '#ff8800'   # fijar a mano
voice role lucas backend       # ver/fijar el rol
voice agents                   # tabla de identidades fijadas
```

El registro vive en `~/.local/state/voice/agents.json` (por-máquina, no se
versiona). En Pi, el nombre automático registra el color en el panel de tmux
(`@agent_color`, `@agent_role`) y pinta su fondo, así la terminal entera del
agente lleva su color. Ver `conversar.ts`.

## Entrega de mensajes

`[tts] delivery` decide cómo entrega `avisar` el mensaje de un agente:

- **`bell` (por defecto):** los mensajes de los agentes **nunca se hablan
  solos**. Suena la campana (`[tts] chime`, una sola vez por ráfaga) y el
  mensaje queda en el buzón con su autor. Cuando querés, decís **"dime"** (o
  `voice dime`): **suena la campana** (la señal de "te lo leo") y después Omar
  lee la cola en orden, `"<agente> dice: <mensaje>"`, y avisa si quedan más.
  Nada se habla encima del dictado.

  El buzón es un **buffer acotado**, no un archivo que crece para siempre:
  combina cantidad y tiempo. Lo más viejo que `[tts] dime_max_age_min` (30 min)
  se descarta solo —para cuando lo escuchás, ese ticket ya se cerró—; el buffer
  nunca guarda más de `[tts] dime_keep` (20) y tira los más viejos; y por lectura
  lee `[tts] dime_max` (6) si el backlog es viejo, o `[tts] dime_max_recent` (12)
  si **todo** llegó hace menos de `[tts] dime_fresh_min` (15 min).

  Un **reinicio corta el hilo**: lo que estaba pendiente antes de apagar la
  máquina no se lee en la sesión nueva (queda guardado en `voice messages`,
  marcado como expirado por reinicio). Si no hay nada nuevo, "dime" avisa
  "No hay mensajes nuevos desde que prendiste" en lugar de repetir la cola
  anterior. Lo que llega después del arranque se lee normal.
- **`hybrid`:** suena el aviso sutil (`[tts] chime`), espera
  `[tts] hybrid_pause` segundos (1.5) y **recién habla**. Te da un momento para
  prestar atención sin que la voz te caiga encima de golpe. No acumula nada en
  el buzón: el mensaje igual queda en el registro. Si la voz está apagada cae
  al buzón para no perderlo. Mientras habla **pausa la música/video**
  (`[tts] duck`, vía `playerctl`) y **acalla cualquier otro audio** que
  `playerctl` no maneje (video del navegador, apps sin MPRIS) muteando sus
  streams por PipeWire; al terminar reanuda y restaura todo. No baja el volumen
  del sink, así la voz no se opaca.
- **`mailbox`:** igual que `bell` (alias): no lo habla en el momento
  (interrumpir molesta y encima no se escucha). Lo deja en el **buzón** con su autor y suena solo el aviso sutil. El
  contador aparece en la barra; escuchás cuando querés, en orden, y cada mensaje
  queda marcado como escuchado. Al leerlo dice de quién es (`Mensaje de Pi. …`) y
  usa la voz de ese agente.
- **`direct`:** habla al instante (interrumpe).

```bash
voice delivery                # ver modo de entrega
voice delivery hybrid         # aviso + pausa + voz (por defecto)
voice delivery direct         # volver a hablar al instante
voice delivery mailbox        # acumular
voice inbox                   # listar pendientes
voice inbox count             # cuántos hay
voice play-inbox              # escuchar todos los pendientes
voice inbox clear             # marcar todo como escuchado
```

## Wake word ("dime")

Para no usar el atajo, `talk-command` escucha continua y dispara por palabra
clave. Las palabras viven en `~/.config/talk-command/config.yaml`:

- **"dime"** (alias: leeme, buzón, contestadora, correo) → `voice play-inbox`.
- **"cuántos mensajes"** → dice la cantidad pendiente.

El motor ASR lo elige `voice-asr-stream` ([wake] en `config.toml`):
**GPU si hay `gpu_command` y estás en AC**, **CPU con Vosk** si no (o a
batería). Es liviano, no toca la VRAM que usan los motores TTS. La pata CPU se
prepara una vez con `scripts/setup-wake.sh` (venv + `vosk` + modelo chico es).

```bash
python3 ~/dotfiles/linux/voice/engine.py wake-status   # motor/modelo elegido
systemctl --user status talk-command.service           # escucha continua
systemctl --user stop  talk-command.service            # pausar (o el widget)
```

Para GPU real (audio.cpp/Voxtral Realtime) instalá `audiocpp_cli` + un GGUF y
definí `[wake] gpu_command`; el selector lo preferirá en AC y caerá a Vosk en
batería o si falta.

## Asistente (Hermes headless)

Cuando la frase **no es un comando fijo**, el cerebro es **Hermes** corriendo
headless en una sola pasada (`hermes -z`), con sólo el toolset `terminal`:
entiende tu escritorio (Hyprland Lua, `wpctl`, `playerctl`, las CLIs
`voice`/`omar`) y hace la tarea. Su guía vive en
`linux/voice/pi-brain/AGENTS.md`.

- `voice think "<texto>"` — manda el texto a Hermes y habla la respuesta.
- `voice ptt` — push-to-talk: graba, transcribe (Handy) y responde con Hermes.
- En Omar, el cerebro se enchufa sin tocar su código con
  `linux/voice/pi_shim.py` (servicio `voice-pi-shim.service`, nombre histórico):
  traduce el protocolo de Ollama al agente headless. Así las reglas van primero
  y, si no hay comando fijo, responde Hermes.
- Teclas: **Caps Lock = Super** (via `layer(meta)` en keyd). La **tecla física
de Windows** queda remapeada a **F13** y **alterna Omar** on/off en Hyprland.
`SUPER+ALT+P` sigue siendo push-to-talk explícito (una frase).

El modelo del cerebro es el que tenga Hermes configurado
(`~/.hermes/config.yaml`). Hoy arranca barato: primario **gratis**
(`cat-jam-free`) y la cadena de respaldo también gratis (`beam-free`,
`longcat-2.5-preview-free`), todos del plan opencode-go. La idea es empezar
desde lo barato y pagar sólo si hace falta, nunca al revés. `VOICE_HERMES_MODEL`
y `VOICE_HERMES_PROVIDER` lo pisan sin tocar la config.
La variante Pi sigue disponible: `VOICE_BRAIN_BIN=voice-pi` (o correr
`voice-pi` a mano), con `VOICE_PI_MODEL=ollama/qwen3.5:4b` para un modelo local.

La latencia típica del cerebro es ~5–6 s (arranque de Hermes + modelo + tools).
Para bajarla: una sesión persistente o un modelo más chico.

## Captura de notificaciones (legado swaync)

> **Ojo:** Omarchy 4 ya no usa swaync (el shell de quickshell es el dueno de
> `org.freedesktop.Notifications`), asi que este enganche **no corre** hoy. Lo
> que si queda en el registro es lo que emite `voice notify` / `voice avisar`,
> y los avisos de escritorio de los scripts via `notify`. Capturar las
> notificaciones de otras apps pide un plugin del shell: pendiente.

Para que «repetir» incluya lo que el sistema notifica (no solo lo que habla un
agente), `linux/config/swaync/config.json` enganchaba cada notificacion:

```json
"scripts": {
  "voice-log": { "exec": "/home/eztvn/.local/bin/voice ingest-notify", "run-on": "receive" }
}
```

swaync pasa la notificación en el entorno (`SWAYNC_SUMMARY`, `SWAYNC_BODY`,
`SWAYNC_APP_NAME`…); `voice ingest-notify` solo la registra, nunca habla ni
falla. Cualquier notificación de cualquier programa queda así en el registro.

## Servicio systemd (usuario)

`voice-daemon` corre como `systemd --user` (unidad en `nixos/home.nix`,
`graphical-session.target`). La cola TTS vive en el daemon (dedup, playback).

```bash
systemctl --user start   voice-daemon
systemctl --user status  voice-daemon
journalctl --user -u voice-daemon -f
```

`voice daemon status|start|stop|restart` es el atajo.

## Comandos (CLI `voice`)

```
voice status                 estado: TTS/STT/daemon/hardware
voice speak "hola"           genera y reproduce (por idioma actual)
voice say "hola"             alias de speak
voice avisar "texto"         notificación + voz + registro (agentes)
voice notify --app A "txt"   notificación sola (queda en el registro)
voice messages [--json] [N]  registro unificado (voz + notificaciones)
voice repeat [N]             repetir los últimos mensajes (--index M)
voice send --agent N --text "..."   habla con la voz de ese agente
voice listen                 graba (silencio auto-stop) → STT → copia
voice test                   frase de prueba
voice stop                   corta cola TTS
voice engine [motor]         engine por idioma actual (kokoro|piper|espeak)
voice voice [voz]            cambia voz del idioma actual
voice voices                 lista voces disponibles (piper + notas kokoro)
voice lang es|en             idioma por defecto
voice mode summary|full      resumen corto vs lectura completa
voice accelerator [auto|gpu|cpu]  selector STT Handy
voice model list|set        modelos STT instalados / actual
voice transcribe <wav>       STT a un archivo
voice benchmark [eng] [lang] benchmark TTS (kokoro/piper/espeak)
voice daemon start|stop|restart|status
voice tts on|off             activa/desactiva salida hablada
voice volume [0.0-1.0|NN%]   volumen relativo de la voz sobre el general
voice history [--json] [N]   últimas frases (más reciente primero)
voice history play <N>       reproduce la entrada N del historial
voice play <wav>             reproduce un WAV del historial
```

## Hotkey

`SUPER + I` (Hyprland, `hyprland.lua`): mantener mientras hablas. La
grabación se corta sola tras ~0.9 s de silencio (sox `rec`), con segundo
pulsado para cortar y timeout de 15 s. No hay wake-word por ahora; la
arquitectura del daemon lo permite añadir después.

Cuando OpenCode está corriendo, `voice listen` inyecta la transcripción en
la sesión activa (plugin ve `~/.cache/voice/to-opencode.json`).

### Repetir

- `SUPER + ALT + V` — repite el último mensaje (voz o notificación).
- `SUPER + ALT + SHIFT + V` — repite los últimos 3.
- En el widget de la barra: botón «Repetir última», tecla `L`, o clic en
  cualquier mensaje de la lista.

## GPU / batería

- **STT**: Handy usa GPU (Vulkan) por defecto en desktop; `accelerator=auto`
  prefiere CPU en laptop a batería (si `cpu_on_battery`). Forzar con
  `voice accelerator gpu|cpu`.
- **TTS**: Kokoro-82M corre ~realtime en CPU; la calidad es idéntica en CPU y
  GPU (82M, no merece la pena GPU para TTS). GPUs (RTX 3070/4060) solo si
  quieres latencia mínima en STT o modelos TTS mayores en el futuro.

## Activar/desactivar

- TTS hablado fuera: `voice tts off` (la notificación visual OpenCode sigue).
- GPU STT: `voice accelerator gpu`. Volver a auto: `voice accelerator auto`.
- Todo offline tras la primera descarga (Kokoro-82M + modelos Handy).
  Sin cloud para las funciones de voz (Handy post-procesado es opcional).

## Cambiar voces / modelos

- TTS: `voice voice es_MX-ald-medium` (piper) o `voice voice ef_dora` (kokoro).
  Por idioma: `voice lang en; voice voice af_bella`.
- STT: `voice model list`, `voice model set <full_id>` (requiere instalado en
  Handy; descarga desde la app/gui Handy).

## Depuración

- Daemon: `journalctl --user -u voice-daemon -f`, log en `~/.cache/voice/`.
- STT: `voice transcribe ~/.cache/voice/listen.wav`.
- TTS aislado: `voice speak "hola"` (daemon apagado → modo directo).
- Plugin OpenCode: log en `/tmp/opencode/voice.log`.

## Benchmarks

`voice benchmark` mide tiempo total, RAM pico, CPU y VRAM de cada motor
(kokoro/piper/espeak × es/en). Decide qué motor principal usar por idioma.
Resultado en tabla.

## Añadir una integración nueva

Cualquier proceso usa el sistema con el CLI `voice` (no depende de Pi ni de
ningún agente):

```bash
voice avisar --source mi-app "Listo, terminé lo que pediste."   # notifica + habla + registra
voice notify --app mi-app --title "Aviso" "texto"               # solo notifica
voice say "texto"                                               # solo habla
voice repeat                                                    # repite el último mensaje
```

### Voz por proceso (personalidad)

Cada agente o proceso se identifica al hablar con `--source <nombre>` (Pi,
agents, opencode...). Si existe `[tts.profiles.<nombre>]`, esa es su voz;
si no, con `auto_profiles = true` se le asigna **automáticamente** una voz
estable y distinta según el nombre: cada agente suena igual siempre y se
distingue de los demás sin configurar nada.

Además de `voice`/`engine`/`lang`, un perfil admite `pitch` (semitonos,
−12..12) y `speed` (factor de tempo); el daemon los aplica con `sox` después
de sintetizar, así una misma voz base puede dar varias “personalidades”:

```toml
[tts.profiles.Pi]
engine = "kokoro"
voice  = "em_alex"        # masculina

[tts.profiles.agents]
engine = "kokoro"
voice  = "ef_dora"
pitch  = 1.5              # misma voz, tono propio
speed  = 1.05
```

```bash
voice profiles --all                 # perfiles + voces automáticas usadas
voice profile show Pi                # ver la voz efectiva de un agente
voice profile set Pi --voice em_alex --engine kokoro --pitch 0
voice profile test Pi                # la escuchás
voice profile remove Pi              # quita el override del estado
voice profile auto off               # desactiva el reparto automático

# por llamada, sin perfil:
voice say --source agents "Hola desde la plataforma"
voice avisar --voice ef_dora --engine kokoro --lang es "Otra voz"
voice say --no-record ...            # no guardar en el registro
voice say --force ...                # hablar aunque tts.enabled esté en false
```

`voice profile set` guarda en `state.json` (por máquina), no en el repo; los
defectos viven en `config.toml`. El comando `voice profile test` habla una
frase de muestra para reconocerla.

### API de bajo nivel (daemon)

El CLI es la forma recomendada. Para integraciones que ya hablan el protocolo,
el FIFO sigue disponible:

```json
{"text": "mensaje", "engine": "kokoro", "voice": "af_heart", "lang": "en", "pitch": 0, "speed": 1.0, "source": "mi-app", "key": "dedupe", "record": false}
```

`~/.cache/voice/tts.fifo`, una línea JSON por petición. `voice synth` (socket
`~/.cache/voice/synth.sock`) sintetiza a un WAV sin reproducir, útil para
plataformas que quieren el audio y lo reproducen ellas. La cola, el fallback y
el dedup los gestiona el daemon.