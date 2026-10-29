# Hablar con mis agentes

Documento de objetivo, estado y problema. No es un plan de implementación:
es la foto que hay que acordar antes de tocar nada. Si algo de acá está mal,
se corrige este archivo, no el código.

Última revisión: 2026-10-29

---

## 1. La meta

**Quiero hablar con mis agentes como hablo con una persona.** Cualquier agente,
lanzado desde cualquier lado (pi, Claude, opencode, hermes, una terminal
cualquiera), en cualquier momento del día, mientras hago otra cosa.

No quiero:

- un notificador que me avisa cuando algo termina;
- un asistente que solo entiende órdenes del escritorio;
- un dictado que escribe en la ventana enfocada;
- un botón que hay que apretar para cada frase.

Quiero una **conversación**: yo hablo, él contesta, lo interrumpo, le pregunto
sobre lo que dijo, le pido que repita, que vaya más despacio, que se explique, y
todo eso se siente como seguir una charla, no como operar un aparato.

### Criterios de "esto está terminado"

Se puede dar por logrado cuando, sin tocar el teclado:

1. Le hablo a un agente que está corriendo en una terminal y me contesta en voz
   alta en menos de ~2 s desde que termino la frase.
2. Lo interrumpo a mitad de una respuesta y **deja de hablar en el acto**, sin
   perder lo que faltaba.
3. Le pregunto "¿qué dijiste?" o "repetí lo último" y me contesta al instante,
   sin volver a consultar al agente.
4. Le digo "más despacio" y cambia el ritmo **desde ahí**, no la próxima vez.
5. Tengo dos agentes trabajando y **solo me habla el que estoy escuchando**; el
   otro deja el mensaje y me avisa con la campana.
6. Le pregunto "¿en qué va?" mientras trabaja y me contesta con lo que está
   haciendo, sin esperar a que termine.
7. Todo lo anterior funciona igual con un agente que no sabe que existo (un CLI
   que nunca integré).

---

## 2. Escenas de uso (así se ve cuando funciona)

- Estoy en la cocina con los audífonos. Le hablo a Claude, que está corriendo
  los tests en la terminal del escritorio. Me dice "van dos de cinco". Le
  pregunto "¿cuál falló?" y me lo dice mientras sigue corriendo.
- Pi termina una tarea larga y empieza a explicarme. A los diez segundos lo
  corto: "pará, eso ya lo sé, decime el resultado". Se calla, y me dice el
  resultado, sin repetir lo anterior.
- Tengo tres agentes. Uno de dotfiles, uno de audio, uno de research. Digo
  "audio, ¿en qué quedamos?" y va a ese. Los otros dos, cuando terminan, solo
  tocan la campana.
- Salgo a caminar. Digo "main, ¿cómo va el ticket 93?" y me resume. Digo
  "dale, seguí" y retoma.

---

## 3. Principios (no negociables)

1. **Un solo dueño del micrófono y del parlante.** Un proceso. Todos los demás
   le piden. Nunca dos cosas hablando ni dos grabando.
2. **El agente tiene la verdad.** Lo que el agente dijo, se dice tal cual. No
   hay otro modelo en el medio reescribiéndolo.
3. **La conversación existe mientras el agente trabaja.** Puedo hablar *del*
   trabajo sin interrumpir *el* trabajo.
4. **Mismo trato para cualquier harness.** Lo específico de cada agente vive en
   un adaptador chico; el resto del sistema no sabe qué es pi ni qué es Claude.
5. **La voz no se autoinvoca.** Ningún agente habla solo si no está en foco:
   primero la campana, después la voz cuando la pido.

---

## 4. Situación actual: qué hay hoy

Todo esto está en la máquina y funcionando (verificado el 2026-10-29).

### 4.1 Audio y sistema

| Pieza | Dónde | Estado |
|---|---|---|
| Audio del sistema | PipeWire | andando; parlante y micrófono Bluetooth en uso |
| STT batch | `handy` (whisper-medium Q8, Vulkan) | andando |
| STT rápido | `omar-whisper.service` (faster-whisper en CUDA) | corriendo |
| STT streaming | `voice-asr-stream` (Vosk) | existe, se usa para wake word |
| Wake word | `talk-command.service`, KWS sherpa-onnx (OmniVoz) | corriendo |
| Grabación PTT | `voice listen`, `SUPER+I`, `SUPER+ALT+P` | andando |

### 4.2 Salida de voz (TTS)

| Pieza | Dónde | Estado |
|---|---|---|
| Daemon de voz | `voice-daemon.service` | corriendo: cola, dedup, playback, fallback |
| Motores | Kokoro-82M, Chatterbox, Piper, espeak | andando; servidores persistentes |
| Voces/identidad | `linux/voice/identity.py`, `agents.json` | andando: voz, rol y color por agente |
| Superficie Omar | `omar-surface.service` | corriendo: se declara "un solo dueño del bloque al pie: glow, píldora, dictado y TTS" |
| Glow / píldora | `omar-glow.service`, `omar-pill.service` | corriendo |
| Cerebro de voz | `voice-pi-shim.service` → Hermes headless | corriendo (latencia 5–6 s) |

### 4.3 Superficies del escritorio (Omarchy / quickshell)

Plugins vivos en `~/.config/omarchy/plugins/`:
`eztvn.pi-tts` (interruptor y registro de voz), `eztvn.mic`, `eztvn.modo-voz`,
`eztvn.asistente`, `eztvn.audio`, `eztvn.osd`, `omar.status`,
`talk-command.status`.

### 4.4 Agentes y enganches

| Pieza | Dónde | Qué hace |
|---|---|---|
| `tts-summary.ts` | `linux/pi/agent/extensions/` | tool `avisar` + resumen de respaldo al terminar |
| `conversar.ts` | idem | tool `hablar`, latido, identidad del panel |
| `rig.ts` | idem | tareas `T-XXXXXX` y trace |
| Plugin de voz de opencode | `~/.config/opencode/plugins/voice/` | resumen al terminar, inyección |
| Bus `agente` | `~/developing/voz-agentes/agente` | `preguntar/esperar/responder/pensar` |
| Sillas | `rig seats` (`main-seat`, `rig-main-seat.service`) | agentes en tmux |
| Puente Discord | `rig-discord-bot.service` | hablar con `main` desde el teléfono |
| Registro | `~/.local/state/rig/events.jsonl`, `voice messages`, bodega `rig db` | trazabilidad |

### 4.5 Proyectos relacionados en `~/developing`

`omar` (control del escritorio por voz + shell), `voz-agentes` (bus y
experimentos de conversación), `asistente`, `fluidez`, `speeedy`,
`speeedy-hub`, `px0`, `protolab`, `alcaide`, `agentes-platform`, `pi-desktop`,
`zentr0`.

Scripts propios en `linux/bin/`: `voice*`, `omar-*`, `tts*`, `handy-dictado`,
`voice-agent`, `voice-asr-stream`, `voice-duck`, `voice-hermes`, `voice-pi`,
`voice-kokoro`, `voice-key-listener`, `voice-omarchy-index`.

---

## 5. El problema

**En una frase:** la voz está puesta **al final del turno del agente** y hay
**varios dueños** del micrófono y del parlante. Eso da un notificador, nunca una
conversación.

Desglosado en lo que se siente:

1. **Es un aviso, no una charla.** El agente termina, sintetiza, reproduce, se
   acabó. No existe el final de turno "ahora te escucho".
2. **No puedo interrumpir.** Mientras habla, el micrófono es de otro. No hay
   quien me oiga.
3. **Se fragmentó.** Pi me responde dos o tres veces. Claude no, porque no tiene
   ninguno de esos enganches. El síntoma es del desorden, no de pi.
4. **No hay a quién preguntarle.** Lo que dijo queda como un WAV y una línea de
   texto: no hay turno, ni posición, ni "esto es lo que dije". Entonces
   "¿por qué?", "repetí", "más despacio" no tienen contra qué resolverse.
5. **Varios agentes se pisan.** Una sola cola global: el que termina te habla
   encima del que estás escuchando.
6. **Se siente que empiezo de cero.** Cuatro intentos, cuatro puntas distintas,
   ninguna conversación.

### Causa raíz

Omar, VoiceListen, OmniVoz y el bus `agente` **no fueron cuatro intentos de lo
mismo**: fueron cuatro puntas distintas (control del escritorio, dictado, wake
word, agentes) y cada una se llevó su propio dueño del micrófono, su router y su
camino de TTS. Ninguna arrancó desde "conversación con agentes", así que ninguna
convergió. No falta una pieza nueva: **sobran tres**.

La ley que faltó, y que este documento pone por escrito: *el audio es un
privilegio de uno solo*.

---

## 6. Lo que NO se va a hacer

- **No** empezar otro proyecto desde cero. Se consolida sobre lo que ya anda.
- **No** meter otro modelo entre el agente y mi oído.
- **No** reescribir el TTS: los motores andan.
- **No** borrar Omar, OmniVoz ni el shell. Dejan de tener voz propia; siguen
  existiendo.
- **No** arreglar el síntoma de "responde tres veces" antes de tener el dueño
  único: se arregla solo cuando hay un solo camino de salida.

---

## 7. Decisiones pendientes

1. Cuál es **el** dueño: `voice-daemon` (motor de audio) o `omar-surface`
   (superficie). Hay que elegir uno, no los dos.
2. Si la conversación es **un agente en foco a la vez** o varios hilos con
   cambio por nombre.
3. Si el adaptador universal es **tmux/PTY** (sirve para cualquier CLI) o se
   empieza por los enganches nativos (solo pi/opencode).
4. Si "pará" **corta la voz** o **aborta el turno** del agente (son dos cosas
   distintas, con costos distintos).

---

## 8. Anexo: archivos clave

| Ruta | Qué es |
|---|---|
| `linux/voice/daemon.py` | cola y reproducción de TTS |
| `linux/voice/engine.py` | config, router de motores, selector de STT/wake |
| `linux/voice/identity.py` | nombre, rol, color y voz de cada agente |
| `linux/voice/kokoro_server.py`, `chatterbox_server.py` | motores persistentes |
| `linux/voice/micguard.py` | quién tiene el micrófono (dictado) |
| `linux/voice/stt.py`, `asr_vosk.py` | transcripción batch y streaming |
| `linux/voice/README.md` | manual del sistema de voz actual |
| `linux/pi/agent/extensions/tts-summary.ts` | `avisar`: el agente habla al terminar |
| `linux/pi/agent/extensions/conversar.ts` | `hablar`, latido, identidad en el panel |
| `linux/pi/agent/extensions/rig.ts` | tareas y trace |
| `docs/pi-latido.md` | widget de pensamiento en vivo |
| `docs/main-bridge.md` | puente Discord y escalado al humano |
| `docs/bodega-agentica.md` | registro unificado de la actividad de agentes |
| `docs/agents.md` | registro de agentes y skills |
| `~/developing/voz-agentes/` | bus `agente` (README, ESTADO, ROADMAP) |
| `~/developing/omar/` | control del escritorio por voz |
