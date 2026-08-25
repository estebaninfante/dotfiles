#!/usr/bin/env python3
# engine.py — capas compartidas del sistema de voz.
#
# Separacion de capas:
#   - tts/: piper (default), kokoro (opcional), espeak-ng (fallback ligero)
#   - stt/: faster-whisper (cpu default, cuda opcional)
#   - daemon/: cola + reproduccion (daemon.py)
#   - cli/: voice (linux/bin/voice)
#
# Este modulo solo contiene: carga de config, estado por-maquina, deteccion
# de GPU/energia y resolucion del backend de STT. Sin logica de audio.
#
# Uso como modulo:  from engine import load_config, detect, ...
# Uso como script:  engine.py detect | status

import json
import os
import shutil
import sys

HOME = os.path.expanduser("~")

CONFIG_DIR = os.environ.get("VOICE_CONFIG_DIR", os.path.join(HOME, ".config", "voice"))
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.toml")
STATE_FILE = os.environ.get(
    "VOICE_STATE_FILE", os.path.join(HOME, ".local", "state", "voice", "state.json")
)
CACHE_DIR = os.environ.get("VOICE_CACHE_DIR", os.path.join(HOME, ".cache", "voice"))
MODEL_DIR = os.environ.get("VOICE_MODEL_DIR", os.path.join(HOME, ".local", "share", "voice", "models"))
MACHINE_FILE = os.path.join(HOME, ".config", "machine-type")

DEFAULTS = {
    "tts": {"enabled": True, "engine": "piper", "voice_es": "es_MX-claude-high",
            "voice_en": "en_US-amy-medium", "lang": "es", "mode": "summary"},
    "stt": {"backend": "cpu", "model": "small", "lang": "es"},
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
                    val = val.strip()
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
            state.setdefault(sec, {}).update(vals)
        else:
            state[sec] = vals
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
    for p in battery_paths:
        ac_file = os.path.join(supply_dir, "AC", "online")
        if os.path.exists(ac_file):
            with open(ac_file, "r") as fh:
                on_ac = fh.read().strip() == "1"
            break
        bat = os.path.join(p, "online")  # algunos kernels: battery/online
        if os.path.exists(bat):
            with open(bat, "r") as fh:
                on_ac = fh.read().strip() == "1"
            break

    try:
        import subprocess
        r = subprocess.run(["upower", "-i", "/org/freedesktop/UPower/devices/DisplayDevice"],
                            capture_output=True, text=True, timeout=5)
        for line in r.stdout.splitlines():
            if "state" in line and "discharging" in line:
                on_ac = False
            if "percentage" in line and "missing" not in line and has_battery:
                pass
    except Exception:
        pass

    return {
        "machine": machine,
        "nvidia": nvidia,
        "has_battery": has_battery,
        "on_ac": on_ac if on_ac is not None else True,
    }


def choose_stt_backend(configured: str = None, info: dict = None) -> str:
    """Backend STT efectivo segun config + energia + GPU.
    - cpu          → cpu siempre (respetando cpu_on_battery)
    - cuda         → cuda si hay NVIDIA; si no, cpu (warning en stderr)
    - auto         → cuda si NVIDIA y (desktop o AC o gpu_on_ac); si no cpu
    """
    cfg = load_config() if configured is None else None
    if configured is None:
        configured = (cfg or {}).get("stt", {}).get("backend", "cpu")
        cpu_on_battery = (cfg or {}).get("power", {}).get("cpu_on_battery", True)
        gpu_on_ac = (cfg or {}).get("power", {}).get("gpu_on_ac", True)
    else:
        cfg = load_config()
        cpu_on_battery = cfg.get("power", {}).get("cpu_on_battery", True)
        gpu_on_ac = cfg.get("power", {}).get("gpu_on_ac", True)

    if info is None:
        info = detect()

    if configured == "cpu":
        return "cpu"
    if configured in ("cuda", "auto"):
        if not info["nvidia"]:
            return "cpu"
        if configured == "cuda":
            return "cuda"
        # auto
        if info["has_battery"] and not info["on_ac"] and cpu_on_battery:
            return "cpu"
        if info["has_battery"] and info["on_ac"] and not gpu_on_ac:
            return "cpu"
        return "cuda"
    return "cpu"


# ── Resolucion del motor TTS ────────────────────────────────────────────
def tts_command(cfg: dict = None) -> dict:
    """Devuelve {engine, voice, lang, mode, enabled} efectivos."""
    if cfg is None:
        cfg = load_config()
    t = cfg.get("tts", {})
    enabled = bool(t.get("enabled", True))
    engine = t.get("engine", "piper")
    lang = t.get("lang", "es")
    mode = t.get("mode", "summary")
    voice = t.get("voice_" + lang, t.get("voice_es", "es_MX-claude-high"))
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
    t = tts_command(cfg)
    backend = choose_stt_backend(cfg["stt"]["backend"], info)
    lines = [
        "voice system",
        f"  machine    : {info['machine']}",
        f"  battery    : {'si' if info['has_battery'] else 'no'}"
        f" | {'AC' if info['on_ac'] else 'BATERIA'}",
        f"  nvidia gpu : {'si (' + (os.popen('nvidia-smi --query-gpu=name --format=csv,noheader').read().strip() if os.path.exists('/usr/bin/nvidia-smi') or os.path.exists('/run/current-system/sw/bin/nvidia-smi') else '') + ')' if info['nvidia'] else 'no'}",
        f"  tts        : {t['engine']} | voz={t['voice']} | lang={t['lang']} | "
        f"mode={t['mode']} | {'ON' if t['enabled'] else 'OFF'}",
        f"  stt        : backend={cfg['stt']['backend']} (efectivo: {backend}) | "
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
    elif cmd == "backend":
        print(choose_stt_backend())
    elif cmd == "voices":
        print("\n".join(list_piper_voices()))
    elif cmd == "set" and len(sys.argv) >= 4:
        save_state({sys.argv[2]: {sys.argv[3]: sys.argv[4]}})
        print(f"{sys.argv[2]}.{sys.argv[3]} = {sys.argv[4]}")
    else:
        print(status_text())