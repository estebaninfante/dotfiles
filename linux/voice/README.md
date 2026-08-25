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
voice-daemon (orquestador)  ◄── FIFO ~/.cache/voice/tts.fifo
   │
   ├─► OpenCode (plugin voice: session.idle / permiso / error)
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
```

## Hotkey

`SUPER + I` (Hyprland, `hyprland.lua`): mantener mientras hablas. La
grabación se corta sola tras ~0.9 s de silencio (sox `rec`), con segundo
pulsado para cortar y timeout de 15 s. No hay wake-word por ahora; la
arquitectura del daemon lo permite añadir después.

Cuando OpenCode está corriendo, `voice listen` inyecta la transcripción en
la sesión activa (plugin ve `~/.cache/voice/to-opencode.json`).

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

Cualquier proceso puede pedir TTS escribiendo una línea JSON al FIFO
`~/.cache/voice/tts.fifo`:
```json
{"text": "mensaje", "engine": "kokoro", "voice": "af_heart", "lang": "en", "key": "dedupe"}
```
O simplemente llamando `~/.local/bin/voice speak "mensaje"`. La cola, el
fallback y el dedup los gestiona el daemon.