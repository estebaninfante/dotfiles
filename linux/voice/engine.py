#!/usr/bin/env python3
# engine.py — capas compartidas del sistema de voz.
#
# Separacion de capas:
#   - tts/: router por-idioma (kokoro principal, piper, espeak-ng fallback)
#   - stt/: Handy (whisper local via Vulkan/CPU — sin compilar CUDA)
#   - daemon/: cola + reproduccion (daemon.py)
#   - cli/: voice (linux/bin/voice)
#
# Este modulo solo contiene: carga de config, estado por-maquina, deteccion
# de GPU/energia, selector de dispositivo Handy y resolucion del router TTS.
# Sin logica de audio.
#
# Uso como modulo:  from engine import load_config, detect, ...
# Uso como script:  engine.py detect | status | devices | accelerator

import json
import os
import shutil
import subprocess
import sys
import time
import zlib
from contextlib import contextmanager

import fcntl

HOME = os.path.expanduser("~")

CONFIG_DIR = os.environ.get("VOICE_CONFIG_DIR", os.path.join(HOME, ".config", "voice"))
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.toml")
STATE_FILE = os.environ.get(
    "VOICE_STATE_FILE", os.path.join(HOME, ".local", "state", "voice", "state.json")
)
CACHE_DIR = os.environ.get("VOICE_CACHE_DIR", os.path.join(HOME, ".cache", "voice"))
MACHINE_FILE = os.path.join(HOME, ".config", "machine-type")

# Registro de mensajes entregados al usuario (voz + notificaciones) y sus
# WAVs, para repasarlos desde el widget de la barra. Vive en XDG data (no en
# cache): es informacion que el usuario quiere conservar.
HISTORY_DIR = os.environ.get(
    "VOICE_HISTORY_DIR", os.path.join(HOME, ".local", "share", "voice", "tts")
)
HISTORY_RECORDINGS = os.path.join(HISTORY_DIR, "recordings")
HISTORY_MAX = int(os.environ.get("VOICE_HISTORY_MAX", "200"))

# × idioma: engine_<lang>=motor, voice_<lang>=voz.
# es → chatterbox (multilingue, calidad SOTA, voice cloning)
# en → chatterbox (multilingue, calidad SOTA, voice cloning)
# Fallback: piper/kokoro si chatterbox no disponible.
DEFAULTS = {
    "tts": {"enabled": True, "lang": "es", "mode": "summary",
            "volume": 1.0,
            "engine_es": "chatterbox", "voice_es": "default",
            "engine_en": "chatterbox", "voice_en": "default",
            "profiles": {}, "auto_profiles": True,
            "duck": True},
    "stt": {"accelerator": "auto", "model": "whisper-medium", "lang": "es"},
    "wake": {"accelerator": "auto", "model": "", "gpu_command": ""},
    "power": {"cpu_on_battery": True, "gpu_on_ac": True},
}

# Voces de reparto automático: si un proceso se identifica con `--source X` y no
# existe `[tts.profiles.X]`, se le asigna de forma estable una de estas según el
# hash del nombre. Así cada agente suena distinto sin configurar nada, y la
# asignación no cambia entre llamadas. El tono (`pitch`, en semitonos) permite
# sacar varias "personalidades" de una misma voz.
AUTO_VOICE_POOL = {
    "es": [
        {"engine": "kokoro", "voice": "em_alex", "pitch": 0.0},
        {"engine": "kokoro", "voice": "em_santa", "pitch": 0.0},
        {"engine": "piper", "voice": "es_MX-claude-high", "pitch": 0.0},
        {"engine": "kokoro", "voice": "ef_dora", "pitch": 0.0},
        {"engine": "kokoro", "voice": "em_alex", "pitch": 1.5},
        {"engine": "kokoro", "voice": "em_santa", "pitch": -1.5},
        {"engine": "kokoro", "voice": "ef_dora", "pitch": 1.5},
        {"engine": "kokoro", "voice": "ef_dora", "pitch": -1.5},
    ],
    "en": [
        {"engine": "kokoro", "voice": "af_heart", "pitch": 0.0},
        {"engine": "kokoro", "voice": "af_bella", "pitch": 0.0},
        {"engine": "kokoro", "voice": "af_nicole", "pitch": 0.0},
        {"engine": "kokoro", "voice": "bf_emma", "pitch": 0.0},
        {"engine": "kokoro", "voice": "af_heart", "pitch": -1.5},
        {"engine": "kokoro", "voice": "af_bella", "pitch": 1.5},
    ],
}


def _parse_toml(path: str) -> dict:
    """Mini parser TOML suficiente para config.toml (secciones + clave=valor).

    Las secciones anidadas con punto (`[tts.profiles.pi]`) se guardan como
    diccionarios anidados, para que cada proceso pueda tener su propio perfil
    de voz sin duplicar el router por-idioma.
    """
    cfg: dict = {}
    node = cfg
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    node = cfg
                    for part in line[1:-1].strip().split("."):
                        part = part.strip()
                        if part:
                            node = node.setdefault(part, {})
                    continue
                if "=" in line:
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.split("#", 1)[0].strip()   # quitar comentario inline
                    if val.lower() in ("true", "false"):
                        val = val.lower() == "true"
                    elif val.startswith('"') and val.endswith('"'):
                        val = val[1:-1]
                    elif val.isdigit():
                        val = int(val)
                    if isinstance(node, dict):
                        node[key] = val
    except OSError:
        pass
    return cfg


def _deep_update(base: dict, patch: dict) -> None:
    """Fusiona `patch` en `base` recursivamente (los dicts se anidan)."""
    for k, v in patch.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            _deep_update(base[k], v)
        else:
            base[k] = v


def _norm_tree(obj):
    """Aplica _norm_val a las hojas de un dict anidado."""
    if isinstance(obj, dict):
        return {k: _norm_tree(v) for k, v in obj.items()}
    return _norm_val(obj)


def load_config() -> dict:
    """Config mergeda: defaults <- config.toml <- state.json (overrides)."""
    cfg = json.loads(json.dumps(DEFAULTS))
    file_cfg = _parse_toml(CONFIG_FILE)
    for sec, vals in file_cfg.items():
        _deep_update(cfg.setdefault(sec, {}), vals)
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            state = json.load(fh)
        for sec, vals in state.items():
            if isinstance(vals, dict):
                _deep_update(cfg.setdefault(sec, {}), vals)
    except (OSError, json.JSONDecodeError):
        pass
    return cfg


def _norm_val(v):
    """Normaliza strings 'true'/'false'/'1'/'0' a bool/int para state.json."""
    if isinstance(v, str):
        low = v.strip().lower()
        if low in ("true", "1"):
            return True
        if low in ("false", "0"):
            return False
    return v


def save_state(patch: dict) -> None:
    """Merge `patch` (formato json, posiblemente anidado) en state.json."""
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    state = {}
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            state = json.load(fh)
    except (OSError, json.JSONDecodeError):
        pass
    _deep_update(state, _norm_tree(patch))
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
    os.replace(tmp, STATE_FILE)


def remove_profile(name: str) -> bool:
    """Quita un perfil de state.json (los de config.toml, si quedan, siguen)."""
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            state = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return False
    profs = state.get("tts", {}).get("profiles", {})
    if name not in profs:
        return False
    profs.pop(name, None)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
    os.replace(tmp, STATE_FILE)
    return True


# ── Deteccion de hardware / energia ─────────────────────────────────────
def detect() -> dict:
    machine = "desktop"
    try:
        with open(MACHINE_FILE, "r", encoding="utf-8") as fh:
            machine = fh.read().strip() or "desktop"
    except OSError:
        pass

    nvidia = os.path.exists("/dev/nvidia0")

    battery_paths = []
    supply_dir = "/sys/class/power_supply"
    if os.path.isdir(supply_dir):
        for name in os.listdir(supply_dir):
            p = os.path.join(supply_dir, name)
            if os.path.isdir(p) and os.path.exists(os.path.join(p, "type")):
                with open(os.path.join(p, "type"), "r") as fh:
                    if fh.read().strip() == "Battery":
                        battery_paths.append(p)

    has_battery = len(battery_paths) > 0
    on_ac = True if not has_battery else None
    ac_online = os.path.join(supply_dir, "AC", "online")
    if os.path.exists(ac_online):
        with open(ac_online, "r") as fh:
            on_ac = fh.read().strip() == "1"
    if on_ac is None:
        for p in battery_paths:
            bat = os.path.join(p, "online")
            if os.path.exists(bat):
                with open(bat, "r") as fh:
                    on_ac = fh.read().strip() == "1"
                break

    try:
        r = subprocess.run(["upower", "-i", "/org/freedesktop/UPower/devices/DisplayDevice"],
                            capture_output=True, text=True, timeout=5)
        for line in r.stdout.splitlines():
            if "state" in line and "discharging" in line:
                on_ac = False
    except Exception:
        pass

    return {
        "machine": machine,
        "nvidia": nvidia,
        "has_battery": has_battery,
        "on_ac": on_ac if on_ac is not None else True,
    }


# ── STT: selector de dispositivo Handy (Vulkan GPU / CPU) ───────────────
def handy_devices() -> list[dict]:
    """Parse `handy --list-devices`. Devuelve [{index, kind, name, vram}]."""
    out: list[dict] = []
    try:
        r = subprocess.run(["handy", "--list-devices"],
                           capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return out
    for line in r.stdout.splitlines():
        line = line.strip()
        if not line.startswith("index=") or "kind=" not in line:
            continue
        fields = dict(
            part.split("=", 1) for part in line.split()
            if "=" in part
        )
        if "index" in fields and "kind" in fields:
            out.append({
                "index": int(fields["index"]),
                "kind": fields["kind"],
                "name": fields.get("name", "").strip("'"),
                "vram": fields.get("vram", ""),
            })
    return out


def choose_handy_device(configured: str = None, info: dict = None) -> dict:
    """Selector de dispositivo STT efectivo (Handy).
    configured: auto | gpu | cpu.
    Devuelve {index:int|None, accelerator:'gpu'|'cpu'}.
    - gpu → primer dispositivo kind=vulkan (NVIDIA); si no hay, cpu.
    - cpu → primer dispositivo kind=cpu.
    - auto→ gpu si (sin bateria /desktop/, o en AC, o gpu_on_ac); si no cpu.
    """
    cfg = load_config()
    if configured is None:
        configured = cfg.get("stt", {}).get("accelerator", "auto")
    cpu_on_battery = cfg.get("power", {}).get("cpu_on_battery", True)
    gpu_on_ac = cfg.get("power", {}).get("gpu_on_ac", True)
    if info is None:
        info = detect()

    devs = handy_devices()
    gpu_dev = next((d for d in devs if d["kind"] == "vulkan"), None)
    cpu_dev = next((d for d in devs if d["kind"] == "cpu"), None)

    if configured == "cpu":
        return {"index": cpu_dev["index"] if cpu_dev else None, "accelerator": "cpu"}
    if configured == "gpu":
        if gpu_dev:
            return {"index": gpu_dev["index"], "accelerator": "gpu"}
        return {"index": cpu_dev["index"] if cpu_dev else None, "accelerator": "cpu"}
    # auto
    use_gpu = gpu_dev is not None and (
        (info["has_battery"] and info["on_ac"] and gpu_on_ac)
        or (info["has_battery"] and not info["on_ac"] and not cpu_on_battery)
        or not info["has_battery"]
    )
    if use_gpu:
        return {"index": gpu_dev["index"], "accelerator": "gpu"}
    return {"index": cpu_dev["index"] if cpu_dev else None, "accelerator": "cpu"}


# ── Wake-word: selector de motor ASR (GPU / CPU) ───────────────────────
def choose_wake_accelerator(cfg: dict = None) -> str:
    """Motor del wake-word ('gpu' | 'cpu') segun config y energia.

    auto: GPU si hay NVIDIA y estas en AC (o no hay bateria); en bateria, CPU.
    Espeja la logica del STT (Handy) para no competir por la GPU a bateria.
    """
    if cfg is None:
        cfg = load_config()
    accel = str(cfg.get("wake", {}).get("accelerator", "auto")).lower()
    if accel == "cpu":
        return "cpu"
    info = detect()
    if not info["nvidia"]:
        return "cpu"
    if accel == "gpu":
        return "gpu"
    return "gpu" if info["on_ac"] else "cpu"


def wake_settings(cfg: dict = None) -> dict:
    if cfg is None:
        cfg = load_config()
    w = cfg.get("wake", {})
    model = w.get("model") or os.path.join(
        HOME, ".local", "share", "voice", "asr", "vosk-model-small-es-0.42")
    return {
        "accelerator": choose_wake_accelerator(cfg),
        "model": os.path.expanduser(str(model)),
        "gpu_command": str(w.get("gpu_command", "") or ""),
    }


# ── TTS: router por-idioma ──────────────────────────────────────────────
def tts_command(cfg: dict = None, lang: str = None) -> dict:
    """Devuelve {engine, voice, lang, mode, enabled} efectivos para `lang`.
    Motor y voz por-idioma: cfg.tts['engine_<lang>'] / cfg.tts['voice_<lang>'],
    con respaldo al prefijo generico engine/voice si el lang-prefijo falta.
    """
    if cfg is None:
        cfg = load_config()
    t = cfg.get("tts", {})
    enabled = bool(t.get("enabled", True))
    mode = t.get("mode", "summary")
    if lang is None:
        lang = t.get("lang", "es")
    engine = t.get("engine_" + lang) or t.get("engine", "piper")
    voice = t.get("voice_" + lang) or (
        "es_MX-claude-high" if lang == "es" else "af_heart")
    return {"engine": engine, "voice": voice, "lang": lang, "mode": mode, "enabled": enabled}


def resolve_voice(cfg: dict = None, profile: str = "", voice: str = "",
                  engine: str = "", lang: str = "") -> dict:
    """Voz/engine/lang/tono/velocidad efectivos para un mensaje concreto.

    Prioridad: flags explicitos > perfil nombrado (`[tts.profiles.<name>]`) >
    reparto automatico (si `tts.auto_profiles`) > router por-idioma global. Asi
    cada proceso pide su propia voz sin tocar el default de los demas:
    `voice say --source pi "..."`. `pitch` son semitonos y `speed` un factor
    de tempo (1.0 = igual).
    """
    if cfg is None:
        cfg = load_config()
    t = cfg.get("tts", {})
    base_lang = lang or t.get("lang", "es")
    base = tts_command(cfg, base_lang)
    prof = t.get("profiles", {}).get(profile) if profile else None
    if not isinstance(prof, dict):
        prof = {}
        if profile and bool(t.get("auto_profiles", True)):
            pool = AUTO_VOICE_POOL.get(base_lang) or AUTO_VOICE_POOL["en"]
            prof = dict(pool[zlib.crc32(profile.encode("utf-8")) % len(pool)])
    if isinstance(prof, dict):
        engine = engine or prof.get("engine", "")
        voice = voice or prof.get("voice", "")
        base_lang = lang or prof.get("lang", "") or base_lang
    return {
        "engine": engine or base["engine"],
        "voice": voice or base["voice"],
        "lang": base_lang,
        "pitch": _to_float(prof.get("pitch"), 0.0),
        "speed": _to_float(prof.get("speed"), 1.0),
    }


def _to_float(value, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def tts_volume(cfg: dict = None) -> float:
    """Volumen relativo del TTS (0.0-1.0) aplicado SOBRE el volumen general de
    salida. No es un volumen independiente: 1.0 = igual que el general, y si
    bajas el general baja tambien. Acepta 0.6 o '60%'."""
    if cfg is None:
        cfg = load_config()
    raw = str(cfg.get("tts", {}).get("volume", 1.0)).strip()
    try:
        if raw.endswith("%"):
            return max(0.0, min(1.0, float(raw[:-1]) / 100.0))
        return max(0.0, min(1.0, float(raw)))
    except (TypeError, ValueError):
        return 1.0


def find_piper_model(voice: str) -> str | None:
    """Localiza el .onnx de una voz piper en los dirs habituales."""
    dirs = [
        os.environ.get("PIPER_VOICES_DIR", ""),
        "/usr/share/piper-voices",
        os.path.join(HOME, ".local", "share", "tts", "piper", "voices"),
    ]
    for d in dirs:
        if not d or not os.path.isdir(d):
            continue
        candidate = os.path.join(d, voice, voice + ".onnx")
        if os.path.isfile(candidate):
            return candidate
    return None


def list_piper_voices() -> list[str]:
    dirs = [
        os.environ.get("PIPER_VOICES_DIR", ""),
        "/usr/share/piper-voices",
        os.path.join(HOME, ".local", "share", "tts", "piper", "voices"),
    ]
    found: list[str] = []
    for d in dirs:
        if not d or not os.path.isdir(d):
            continue
        for root, _, files in os.walk(d):
            for f in files:
                if f.endswith(".onnx"):
                    name = os.path.basename(root)
                    if name and name not in found:
                        found.append(name)
    return sorted(found)


def status_text() -> str:
    cfg = load_config()
    info = detect()
    t_es = tts_command(cfg, "es")
    t_en = tts_command(cfg, "en")
    stt = choose_handy_device(cfg["stt"]["accelerator"], info)
    lines = [
        "voice system",
        f"  machine    : {info['machine']}",
        f"  battery    : {'si' if info['has_battery'] else 'no'}"
        f" | {'AC' if info['on_ac'] else 'BATERIA'}",
        f"  nvidia gpu : {'si' if info['nvidia'] else 'no'}",
        f"  tts es     : {t_es['engine']} | voz={t_es['voice']} | "
        f"mode={cfg['tts']['mode']} | vol={tts_volume(cfg):.2f} | "
        f"{'ON' if t_es['enabled'] else 'OFF'}",
        f"  tts en     : {t_en['engine']} | voz={t_en['voice']}",
        f"  entrega    : {cfg['tts'].get('delivery', 'direct')}"
        f" | chime={'on' if str(cfg['tts'].get('chime', True)).lower() not in ('false','0') else 'off'}"
        f" | pendientes={pending_count()}",
        f"  stt        : accelerator={cfg['stt']['accelerator']} "
        f"(efectivo: {stt['accelerator']} idx={stt['index']}) | "
        f"model={cfg['stt']['model']} | lang={cfg['stt'].get('lang', 'es')}",
        f"  daemon     : {daemon_alive()}",
    ]
    return "\n".join(lines)


def daemon_alive() -> bool:
    pid_file = os.path.join(CACHE_DIR, "daemon.pid")
    try:
        with open(pid_file, "r") as fh:
            pid = int(fh.read().strip())
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


# ── Registro de mensajes (voz + notificaciones) ────────────────────────
# Una linea JSON por mensaje entregado al usuario, mas viejo primero. Dos
# clases: `kind="voice"` (ademas hay WAV en recordings/ para reproducirlo tal
# cual) y `kind="notify"` (notificacion de escritorio capturada; al repetir se
# sintetiza). El tope evita que crezca sin limite: al superarlo se borran las
# mas viejas junto con sus WAV. Toda lectura tolera lineas corruptas.
MESSAGES_INDEX = os.path.join(HISTORY_DIR, "messages.jsonl")
LEGACY_HISTORY_INDEX = os.path.join(HISTORY_DIR, "history.jsonl")
# Ventana en la que una notificacion y su version hablada (mismo texto) se
# funden en una sola entrada. Es amplia porque el TTS puede tardar en arrancar
# (p. ej. kokoro en frio ~13 s) despues de mostrar la notificacion.
MESSAGE_MERGE_MS = int(os.environ.get("VOICE_MESSAGE_MERGE_MS", "120000"))
# Ventana corta para no duplicar dos notificaciones identicas (swaync y el
# registro explicito de `voice notify`).
MESSAGE_DEDUP_MS = int(os.environ.get("VOICE_MESSAGE_DEDUP_MS", "12000"))


def _messages_read() -> list:
    records = []
    path = MESSAGES_INDEX
    if not os.path.exists(path) and os.path.exists(LEGACY_HISTORY_INDEX):
        path = LEGACY_HISTORY_INDEX  # migracion transparente del historial viejo
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(rec, dict) and rec.get("text"):
                    records.append(rec)
    except OSError:
        pass
    return records


def _messages_write(records: list) -> None:
    os.makedirs(HISTORY_DIR, exist_ok=True)
    tmp = MESSAGES_INDEX + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        for rec in records:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    os.replace(tmp, MESSAGES_INDEX)


@contextmanager
def _messages_lock():
    """Exclusión entre procesos para el ciclo leer-modificar-escribir del
    registro: el daemon y el puente de notificaciones pueden escribir a la vez.
    """
    os.makedirs(HISTORY_DIR, exist_ok=True)
    fh = open(os.path.join(HISTORY_DIR, "messages.lock"), "a+")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fh, fcntl.LOCK_UN)
        fh.close()


def _messages_prune(records: list) -> list:
    """Conserva las ultimas HISTORY_MAX entradas y borra los WAV sobrantes."""
    if HISTORY_MAX <= 0:
        keep, drop = [], records
    else:
        keep, drop = records[-HISTORY_MAX:], records[:-HISTORY_MAX]
    for rec in drop:
        path = rec.get("file")
        if path and os.path.isfile(path):
            try:
                os.remove(path)
            except OSError:
                pass
    return keep


def _store_wav(wav: str) -> str | None:
    """Mueve un WAV temporal a recordings/ y devuelve su ruta final."""
    try:
        os.makedirs(HISTORY_RECORDINGS, exist_ok=True)
    except OSError:
        return None
    ts = int(time.time() * 1000)
    dest = os.path.join(HISTORY_RECORDINGS, f"tts-{ts}.wav")
    suffix = 0
    while os.path.exists(dest):
        suffix += 1
        dest = os.path.join(HISTORY_RECORDINGS, f"tts-{ts}-{suffix}.wav")
    try:
        shutil.move(wav, dest)
    except OSError:
        return None
    return dest


def record_message(text: str, source: str = "", kind: str = "notify",
                   wav: str | None = None, engine: str = "", voice: str = "",
                   lang: str = "", app: str = "", title: str = "",
                   heard: bool = True) -> dict | None:
    """Anota un mensaje entregado al usuario (hablado o notificado).

    Si `kind="voice"` y hay un WAV, se guarda para reproducirlo tal cual. Una
    notificacion y su version hablada con el mismo texto dentro de
    `MESSAGE_MERGE_MS` se funden en una sola entrada (gana la hablada, que
    conserva el audio). `heard=False` lo deja pendiente para el buzon (aun no
    escuchado).
    """
    text = " ".join((text or "").split()).strip()
    if not text:
        return None
    now = int(time.time() * 1000)

    with _messages_lock():
        records = _messages_read()

        for rec in reversed(records[-20:]):
            if rec.get("text") != text:
                continue
            age = now - int(rec.get("ts", 0))
            if wav:
                # Voz: si hay una notificacion reciente con el mismo texto, se
                # le adjunta el audio en vez de duplicar (ventana amplia).
                if age <= MESSAGE_MERGE_MS and not rec.get("file"):
                    dest = _store_wav(wav)
                    if dest:
                        rec.update({"kind": "voice", "engine": engine,
                                    "voice": voice, "lang": lang, "file": dest,
                                    "heard": heard})
                        _messages_write(records)
                return rec
            # Notificacion: no duplicar si ya existe (voz o notificacion).
            if age <= MESSAGE_DEDUP_MS or rec.get("file"):
                return rec
            break

        rec = {"ts": now, "text": text, "kind": kind, "source": source,
               "heard": bool(heard)}
        if app:
            rec["app"] = app
        if title:
            rec["title"] = title
        if kind == "voice":
            rec.update({"engine": engine, "voice": voice, "lang": lang})
            if wav:
                dest = _store_wav(wav)
                if dest:
                    rec["file"] = dest
        _messages_write(_messages_prune(records + [rec]))
        return rec


def record_history(wav: str, text: str, engine: str = "", voice: str = "",
                   lang: str = "", source: str = "voice") -> dict | None:
    """Compatibilidad: registra una frase hablada con su WAV."""
    if not wav or not os.path.isfile(wav):
        return None
    return record_message(text, source=source, kind="voice", wav=wav,
                          engine=engine, voice=voice, lang=lang)


def load_messages(limit: int | None = None) -> list:
    """Mensajes mas reciente primero (voz + notificaciones)."""
    records = _messages_read()
    if limit is not None and limit >= 0:
        records = records[-limit:] if limit else []
    return list(reversed(records))


def message_at(index: int) -> dict | None:
    """Entrada `index` del registro (1 = la mas reciente)."""
    records = load_messages()
    if index < 1 or index > len(records):
        return None
    return records[index - 1]


def load_history(limit: int | None = None) -> list:
    """Solo las frases habladas (con WAV), mas reciente primero."""
    records = [r for r in _messages_read() if r.get("file")]
    if limit is not None and limit >= 0:
        records = records[-limit:] if limit else []
    return list(reversed(records))


def history_wav(index: int) -> str | None:
    """Ruta del WAV de la entrada hablada `index` (1 = la mas reciente)."""
    records = load_history()
    if index < 1 or index > len(records):
        return None
    path = records[index - 1].get("file")
    return path if path and os.path.isfile(path) else None


# ── Buzon de voz (mensajes pendientes de escuchar) ──────────────────────
def _is_pending(rec: dict) -> bool:
    return rec.get("heard") is False


def pending_messages(limit: int | None = None) -> list:
    """Mensajes sin escuchar, mas antiguo primero (orden de lectura)."""
    recs = [r for r in _messages_read() if _is_pending(r)]
    if limit is not None and limit >= 0:
        recs = recs[-limit:] if limit else []
    return list(reversed(recs))


def pending_count() -> int:
    return sum(1 for r in _messages_read() if _is_pending(r))


def mark_heard(ts: int | None = None) -> int:
    """Marca como escuchados todos los pendientes (ts=None) o uno solo."""
    with _messages_lock():
        recs = _messages_read()
        n = 0
        for r in recs:
            if _is_pending(r) and (ts is None or int(r.get("ts", 0)) == ts):
                r["heard"] = True
                n += 1
        if n:
            _messages_write(recs)
        return n


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "detect":
        print(json.dumps(detect(), indent=2))
    elif cmd == "devices":
        for d in handy_devices():
            print(f"index={d['index']} kind={d['kind']} name={d['name']} vram={d['vram']}")
    elif cmd == "accelerator":
        d = choose_handy_device()
        print(f"{d['accelerator']} {d['index']}")
    elif cmd == "wake-accelerator":
        print(choose_wake_accelerator())
    elif cmd == "wake-model":
        print(wake_settings()["model"])
    elif cmd == "wake-gpu-command":
        print(wake_settings()["gpu_command"])
    elif cmd == "wake-status":
        s = wake_settings()
        print(f"wake: accel={s['accelerator']} model={s['model']} "
              f"gpu={'si' if s['gpu_command'] else 'no'}")
    elif cmd == "voices":
        print("\n".join(list_piper_voices()))
    elif cmd == "history":
        args = [a for a in sys.argv[2:] if a != "--json"]
        as_json = "--json" in sys.argv[2:]
        limit = int(args[0]) if args and args[0].isdigit() else None
        records = load_history(limit)
        if as_json:
            print(json.dumps(records, ensure_ascii=False))
        else:
            for i, rec in enumerate(records, 1):
                stamp = time.strftime("%Y-%m-%d %H:%M",
                                      time.localtime(rec["ts"] / 1000))
                snippet = " ".join(str(rec.get("text", "")).split())[:80]
                print(f"{i:>3}  {stamp}  {snippet}")
    elif cmd == "history-wav" and len(sys.argv) >= 3:
        path = history_wav(int(sys.argv[2]))
        if path:
            print(path)
        else:
            sys.exit(1)
    elif cmd == "messages":
        args = [a for a in sys.argv[2:] if a != "--json"]
        as_json = "--json" in sys.argv[2:]
        limit = int(args[0]) if args and args[0].isdigit() else None
        records = load_messages(limit)
        if as_json:
            print(json.dumps(records, ensure_ascii=False))
        else:
            for i, rec in enumerate(records, 1):
                stamp = time.strftime("%Y-%m-%d %H:%M",
                                      time.localtime(rec["ts"] / 1000))
                mark = "voz" if (rec.get("kind") == "voice" or rec.get("file")) else "notif"
                snippet = " ".join(str(rec.get("text", "")).split())[:80]
                print(f"{i:>3}  {stamp}  [{mark:>5}]  {snippet}")
    elif cmd == "message-index" and len(sys.argv) >= 3:
        rec = message_at(int(sys.argv[2]))
        if rec:
            print(json.dumps(rec, ensure_ascii=False))
        else:
            sys.exit(1)
    elif cmd == "pending-count":
        print(pending_count())
    elif cmd == "pending":
        args = [a for a in sys.argv[2:] if a != "--json"]
        as_json = "--json" in sys.argv[2:]
        limit = int(args[0]) if args and args[0].isdigit() else None
        records = pending_messages(limit)
        if as_json:
            print(json.dumps(records, ensure_ascii=False))
        else:
            for i, rec in enumerate(records, 1):
                stamp = time.strftime("%d/%m %H:%M",
                                      time.localtime(rec["ts"] / 1000))
                src = rec.get("source") or rec.get("app") or "?"
                snippet = " ".join(str(rec.get("text", "")).split())[:80]
                print(f"{i:>3}  {stamp}  {src:<12}  {snippet}")
    elif cmd == "mark-heard":
        ts = None
        if "--ts" in sys.argv:
            ts = int(sys.argv[sys.argv.index("--ts") + 1])
        print(mark_heard(ts))
    elif cmd == "record-message":
        args = sys.argv[2:]
        source = text = app = title = ""
        pending = False
        i = 0
        while i < len(args):
            flag = args[i]
            if flag in ("--source", "--text", "--app", "--title") and i + 1 < len(args):
                val = args[i + 1]
                if flag == "--source": source = val
                elif flag == "--text": text = val
                elif flag == "--app": app = val
                elif flag == "--title": title = val
                i += 2
                continue
            if flag == "--pending":
                pending = True
            i += 1
        if text:
            record_message(text, source=source or "voice", kind="notify",
                           app=app, title=title, heard=not pending)
    elif cmd == "notify-ingest":
        # La invoca swaync (scripts.exec) con la notificacion en el entorno.
        # Silenciosa y a prueba de fallos: nunca rompe la cadena de swaync.
        summary = os.environ.get("SWAYNC_SUMMARY", "").strip()
        body = os.environ.get("SWAYNC_BODY", "").strip()
        app = os.environ.get("SWAYNC_APP_NAME", "").strip()
        parts = []
        if summary and summary != app:
            parts.append(summary)
        if body:
            parts.append(body)
        text = " ".join(parts) if parts else summary
        if text:
            record_message(text, source=app or "sistema", kind="notify",
                           app=app, title=summary)
    elif cmd == "record-notify":
        app, title, body = "", "", ""
        rest = sys.argv[2:]
        while rest:
            flag = rest.pop(0)
            if flag == "--app" and rest:
                app = rest.pop(0)
            elif flag == "--title" and rest:
                title = rest.pop(0)
            elif flag == "--body" and rest:
                body = rest.pop(0)
        text = " ".join(x for x in (title, body) if x)
        if text:
            record_message(text, source=app or "voice", kind="notify",
                           app=app, title=title)
    elif cmd == "resolve":
        profile, voice, engine, lang = "", "", "", ""
        rest = sys.argv[2:]
        while rest:
            flag = rest.pop(0)
            val = rest.pop(0) if rest else ""
            if flag == "--profile":
                profile = val
            elif flag == "--voice":
                voice = val
            elif flag == "--engine":
                engine = val
            elif flag == "--lang":
                lang = val
        r = resolve_voice(profile=profile, voice=voice, engine=engine, lang=lang)
        print("\t".join((r["engine"], r["voice"], r["lang"],
                         f"{r['pitch']:.3f}", f"{r['speed']:.3f}")))
    elif cmd == "profiles":
        cfg = load_config()
        profs = cfg.get("tts", {}).get("profiles", {}) or {}
        rows = [{"name": name, **resolve_voice(cfg=cfg, profile=name)}
                for name in sorted(profs)]
        if "--all" in sys.argv:
            seen = {}
            for m in load_messages():
                s = m.get("source") or m.get("app") or ""
                if s and s not in profs and s not in seen:
                    seen[s] = resolve_voice(cfg=cfg, profile=s)
            for name in sorted(seen):
                rows.append({"name": name, **seen[name], "auto": True})
        if "--json" in sys.argv:
            print(json.dumps(rows, ensure_ascii=False))
        else:
            for r in rows:
                tag = "auto" if r.get("auto") else "perfil"
                extra = ""
                if r["pitch"]:
                    extra += f"  pitch={r['pitch']:+g}"
                if abs(r["speed"] - 1.0) > 1e-3:
                    extra += f"  speed={r['speed']:g}"
                print(f"  {r['name']:<14} [{tag:>6}]  {r['engine']:<9} "
                      f"{r['voice']:<22} {r['lang']}{extra}")
    elif cmd == "profile-show" and len(sys.argv) >= 3:
        r = resolve_voice(profile=sys.argv[2])
        print(f"{sys.argv[2]}: engine={r['engine']} voz={r['voice']} "
              f"lang={r['lang']} pitch={r['pitch']:+g} speed={r['speed']:g}")
    elif cmd == "profile-set":
        if len(sys.argv) < 3:
            sys.exit(2)
        name = sys.argv[2]
        fields, rest = {}, sys.argv[3:]
        while rest:
            flag = rest.pop(0)
            val = rest.pop(0) if rest else ""
            key = {"--voice": "voice", "--engine": "engine",
                   "--lang": "lang", "--pitch": "pitch",
                   "--speed": "speed"}.get(flag)
            if key:
                fields[key] = val
        if not fields:
            sys.exit(2)
        save_state({"tts": {"profiles": {name: fields}}})
        r = resolve_voice(profile=name)
        print(f"perfil {name}: engine={r['engine']} voice={r['voice']} "
              f"lang={r['lang']} pitch={r['pitch']:+g} speed={r['speed']:g}")
    elif cmd == "profile-remove":
        if len(sys.argv) < 3 or not remove_profile(sys.argv[2]):
            sys.exit(1)
        print(f"perfil {sys.argv[2]} eliminado (de state.json)")
    elif cmd == "set" and len(sys.argv) >= 4:
        save_state({sys.argv[2]: {sys.argv[3]: sys.argv[4]}})
        print(f"{sys.argv[2]}.{sys.argv[3]} = {sys.argv[4]}")
    else:
        print(status_text())