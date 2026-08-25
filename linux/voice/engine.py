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
import subprocess
import sys

HOME = os.path.expanduser("~")

CONFIG_DIR = os.environ.get("VOICE_CONFIG_DIR", os.path.join(HOME, ".config", "voice"))
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.toml")
STATE_FILE = os.environ.get(
    "VOICE_STATE_FILE", os.path.join(HOME, ".local", "state", "voice", "state.json")
)
CACHE_DIR = os.environ.get("VOICE_CACHE_DIR", os.path.join(HOME, ".cache", "voice"))
MACHINE_FILE = os.path.join(HOME, ".config", "machine-type")

# × idioma: engine_<lang>=motor, voice_<lang>=voz.
# es → piper (es_MX-claude-high suena mejor que el es de kokoro, que es thin).
# en → kokoro (af_heart, calidad A).
DEFAULTS = {
    "tts": {"enabled": True, "lang": "es", "mode": "summary",
            "engine_es": "piper", "voice_es": "es_MX-claude-high",
            "engine_en": "kokoro", "voice_en": "af_heart"},
    "stt": {"accelerator": "auto", "model": "whisper-medium", "lang": "es"},
    "power": {"cpu_on_battery": True, "gpu_on_ac": True},
}


def _parse_toml(path: str) -> dict:
    """Mini parser TOML suficiente para config.toml (solo secciones + clave=valor)."""
    cfg: dict = {}
    section = None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1].strip()
                    cfg.setdefault(section, {})
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
                    if section is not None:
                        cfg[section][key] = val
    except OSError:
        pass
    return cfg


def load_config() -> dict:
    """Config mergeda: defaults <- config.toml <- state.json (overrides)."""
    cfg = json.loads(json.dumps(DEFAULTS))
    file_cfg = _parse_toml(CONFIG_FILE)
    for sec, vals in file_cfg.items():
        cfg.setdefault(sec, {}).update(vals)
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            state = json.load(fh)
        for sec, vals in state.items():
            if isinstance(vals, dict):
                cfg.setdefault(sec, {}).update(vals)
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
    """Merge `patch` (formato json) en state.json."""
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    state = {}
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            state = json.load(fh)
    except (OSError, json.JSONDecodeError):
        pass
    for sec, vals in patch.items():
        if isinstance(vals, dict):
            merged = {}
            for k, v in vals.items():
                merged[k] = _norm_val(v)
            state.setdefault(sec, {}).update(merged)
        else:
            state[sec] = _norm_val(vals)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
    os.replace(tmp, STATE_FILE)


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


def find_piper_model(voice: str) -> str | None:
    """Localiza el .onnx de una voz piper en los dirs habituales."""
    dirs = [
        os.environ.get("PIPER_VOICES_DIR", ""),
        "/run/current-system/sw/share/piper-voices",
        "/nix/var/nix/profiles/default/share/piper-voices",
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
        "/run/current-system/sw/share/piper-voices",
        "/nix/var/nix/profiles/default/share/piper-voices",
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
        f"mode={cfg['tts']['mode']} | {'ON' if t_es['enabled'] else 'OFF'}",
        f"  tts en     : {t_en['engine']} | voz={t_en['voice']}",
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
    elif cmd == "voices":
        print("\n".join(list_piper_voices()))
    elif cmd == "set" and len(sys.argv) >= 4:
        save_state({sys.argv[2]: {sys.argv[3]: sys.argv[4]}})
        print(f"{sys.argv[2]}.{sys.argv[3]} = {sys.argv[4]}")
    else:
        print(status_text())