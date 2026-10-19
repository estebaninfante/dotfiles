#!/usr/bin/env python3
"""identity.py — identidad estable de cada agente: nombre, rol y color.

Fuente única de verdad para que TODAS las piezas hablen del mismo agente con el
mismo nombre y el mismo color: la voz (`voice`/daemon), los subtítulos del glow,
el fondo del panel de tmux, la barra y las notificaciones. Así el usuario
reconoce quién le habla de un vistazo, sin configurar nada.

El color se deriva del **nombre** (hash estable) cuando no hay uno fijado: un
agente nuevo ya nace con su color y nunca cambia. Se puede fijar a mano, por
nombre o por rol, en el registro de la máquina
(`$XDG_STATE_HOME/voice/agents.json`), que NO se versiona.

Rol: la función del agente ("main", "audio", "dotfiles", "general", ...). El
nombre es la identidad (`main`, `puma`, `zen`); el rol dice de qué se ocupa. El
rol también puede dar color por defecto a los agentes de esa función.

Uso:
  voice identity [nombre] [--role R] [--claim] [--pane %id] [--json]
                                                # nombre, rol, color, voz
                                                # --claim: color unico entre vivos
  voice color [nombre]                          # hex del agente
  voice color [nombre] --tint [--amount 0.16]   # variante oscura para fondos
  voice role <nombre> [rol]                     # ver/fijar rol
  voice color <nombre> --set <#hex>             # fijar color
  voice identity check                          # colores repetidos entre vivos
  voice agents                                  # tabla de identidades
"""
from __future__ import annotations

import colorsys
import json
import os
import subprocess
import sys
import zlib
from contextlib import contextmanager

try:  # Linux; en otra plataforma el reclamo igual funciona sin lock
    import fcntl
except ImportError:  # pragma: no cover
    fcntl = None  # type: ignore[assignment]

HOME = os.path.expanduser("~")
STATE_FILE = os.environ.get(
    "VOICE_AGENTS_FILE",
    os.path.join(HOME, ".local", "state", "voice", "agents.json"),
)

# Paleta curada: tonos vivos y legibles sobre fondo oscuro. Es la misma familia
# que usa el glow como respaldo, así todo el sistema combina. El color se toma
# por hash del nombre, pero al arrancar un agente se RECLAMA uno libre: nunca
# hay dos agentes vivos con el mismo color (ver `claim`).
PALETTE = [
    "#7aa2f7",  # azul
    "#9ece6a",  # verde
    "#ff9e64",  # naranja
    "#f7768e",  # rojo/rosa
    "#bb9af7",  # violeta
    "#7dcfff",  # cian
    "#e0af68",  # ámbar
    "#73daca",  # turquesa
    "#a6e3a1",  # menta
    "#89dceb",  # celeste
    "#f9e2af",  # crema
    "#eba0ac",  # rosa pálido
    "#b4befe",  # lavanda
    "#94e2d5",  # aqua
    "#c6a0f6",  # lila
    "#ffd866",  # dorado
    "#ff7a85",  # coral
    "#d7a6ff",  # orquídea
    "#c3e88d",  # lima
    "#9ad0ff",  # azul claro
    "#b2f2bb",  # verde claro
    "#ff9dcf",  # magenta
    "#a3e4d7",  # aguamarina
    "#f5c2e7",  # rosa lila
]

# Roles conocidos -> color por defecto. Fijar por rol sirve para que varios
# agentes de la misma función (p. ej. dos "audio") compartan familia; fijar por
# nombre manda sobre esto.
ROLE_COLORS = {
    "main": "#7aa2f7",
    "general": "#7dcfff",
    "audio": "#ff9e64",
    "dotfiles": "#9ece6a",
    "frontend": "#bb9af7",
    "backend": "#73daca",
    "datos": "#e0af68",
    "data": "#e0af68",
    "voz": "#c6a0f6",
    "voice": "#c6a0f6",
    "investigacion": "#f7768e",
    "investigador": "#f7768e",
    "ops": "#a6e3a1",
    "infra": "#89dceb",
}

DEFAULT_ROLE = "general"


def _load() -> dict:
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            data.setdefault("agents", {})
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {"version": 1, "agents": {}}


def _save(data: dict) -> None:
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp = f"{STATE_FILE}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False, sort_keys=True)
    os.replace(tmp, STATE_FILE)


@contextmanager
def _lock():
    """Serializa el reclamo de color entre agentes que arrancan a la vez.

    Sin lock, dos agentes nuevos podrían leer la misma lista de colores libres
    y quedarse con el mismo. El lock vive al lado del registro y dura
    milisegundos.
    """
    if fcntl is None:
        yield
        return
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(f"{STATE_FILE}.lock", "a+", encoding="utf-8") as fh:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)


def _entry(name: str) -> dict:
    got = _load().get("agents", {}).get(name)
    return got if isinstance(got, dict) else {}


def hash_index(name: str, size: int) -> int:
    """Índice estable en [0, size). Mismo criterio que el reparto de voces."""
    if not name:
        return 0
    return zlib.crc32(name.encode("utf-8")) % max(1, size)


def _norm_hex(value: str) -> str:
    v = str(value or "").strip()
    if not v:
        return ""
    if not v.startswith("#"):
        v = "#" + v
    if len(v) == 4:  # #abc -> #aabbcc
        v = "#" + "".join(ch * 2 for ch in v[1:])
    if len(v) == 7 and all(ch in "0123456789abcdefABCDEF" for ch in v[1:]):
        return v.lower()
    return ""


def color_for(name: str, role: str = "") -> str:
    """Color estable del agente: fijado a mano > nombre con rol conocido >
    rol fijado a mano > hash del nombre.

    El rol *sugerido* (p. ej. la carpeta del proyecto) no cambia el color: así
    dos agentes del mismo proyecto se distinguen por su nombre. Solo un color
    fijado a mano o un rol guardado en el registro lo pisan.
    """
    entry = _entry(name)
    explicit = _norm_hex(entry.get("color", ""))
    if explicit:
        return explicit
    n = str(name or "").strip().lower()
    if n in ROLE_COLORS:
        return ROLE_COLORS[n]
    stored_role = str(entry.get("role") or "").strip().lower()
    if stored_role in ROLE_COLORS:
        return ROLE_COLORS[stored_role]
    return PALETTE[hash_index(name, len(PALETTE))]


# ── agentes vivos: un color por agente ─────────────────────────────────
def _tmux(*args: str) -> str:
    """Corre tmux sin romper si no hay servidor (fuera de tmux devuelve "")."""
    try:
        out = subprocess.run(
            ["tmux", *args], capture_output=True, text=True, timeout=1.5
        )
        return out.stdout if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def live_panes(exclude_pane: str = "") -> list[dict]:
    """Agentes vivos = paneles de tmux con @agent_name.

    Devuelve panel, nombre, rol y color. Si el panel todavía no tiene color
    (recién arrancó), se reserva el que le tocaría por identidad: así otro
    agente no se lo lleva en la ventana entre el arranque y el pintado.
    `exclude_pane` deja afuera al que está reclamando (su color puede ser de
    una corrida anterior).
    """
    raw = _tmux(
        "list-panes",
        "-a",
        "-F",
        "#{pane_id}\t#{@agent_name}\t#{@agent_role}\t#{@agent_color}",
    )
    panes: list[dict] = []
    for line in raw.splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        pane, name, role, color = (p.strip() for p in parts[:4])
        if not name or (exclude_pane and pane == exclude_pane):
            continue
        c = _norm_hex(color) or color_for(name, role)
        panes.append({"pane": pane, "name": name, "role": role, "color": c.lower()})
    return panes


def _hsl_hex(hue: float, sat: float, light: float) -> str:
    r, g, b = colorsys.hls_to_rgb((hue % 360) / 360.0, light, sat)
    return f"#{int(r * 255):02x}{int(g * 255):02x}{int(b * 255):02x}"


def color_candidates():
    """Colores distintos en orden: primero la paleta curada y después tonos
    generados con el ángulo áureo. Alcanza para cualquier cantidad de agentes
    vivos sin repetir un color exacto."""
    seen: set[str] = set()
    for c in PALETTE:
        c = c.lower()
        if c not in seen:
            seen.add(c)
            yield c
    for i in range(1, 720):
        hue = (i * 137.508) % 360
        sat = 0.55 + 0.15 * (i % 3)
        light = 0.56 + 0.09 * (i % 2)
        c = _hsl_hex(hue, sat, light)
        if c not in seen:
            seen.add(c)
            yield c


def free_color(used) -> str:
    """Primer color que no esté en `used` (comparación normalizada)."""
    taken = {str(c).strip().lower() for c in used if c}
    for c in color_candidates():
        if c not in taken:
            return c
    raise RuntimeError("identity: no quedan colores libres")


def claim(name: str, role: str = "", pane: str | None = None) -> dict:
    """Identidad con un color EXCLUSIVO entre los agentes vivos.

    Es lo que se usa al arrancar un agente. Mantiene el color si está libre y,
    si otro agente vivo ya lo tiene, toma el primero libre y lo guarda en el
    registro (así el nombre conserva ese color la próxima vez). El panel
    actual se marca dentro del lock: dos agentes que arrancan juntos no pueden
    quedarse con el mismo color.
    """
    # pane=None -> usar TMUX_PANE del entorno; pane="" -> no tocar ningún panel
    # (corridas headless o subagentes, que comparten el panel del padre).
    if pane is None:
        pane = os.environ.get("TMUX_PANE", "")
    pane = str(pane or "").strip()
    with _lock():
        ident = identity(name, role)
        others = live_panes(exclude_pane=pane)
        taken = {p["color"] for p in others if p.get("color")}
        current = str(ident.get("color") or "").lower()
        if current in taken:
            current = free_color(taken)
            data = _load()
            agents = data.setdefault("agents", {})
            entry = agents.setdefault(name, {})
            if not isinstance(entry, dict):
                entry = {}
                agents[name] = entry
            entry["color"] = current
            _save(data)
            ident["color"] = current
        if pane:
            _tmux("set-option", "-p", "-t", pane, "@agent_color", ident["color"])
        return ident


def live_duplicates() -> dict[str, list[str]]:
    """Colores repetidos entre agentes vivos (debe ser siempre vacío)."""
    by_color: dict[str, list[str]] = {}
    for pane in live_panes():
        by_color.setdefault(pane["color"], []).append(pane["name"])
    return {c: names for c, names in by_color.items() if len(names) > 1}


def role_for(name: str, fallback: str = "") -> str:
    entry = _entry(name)
    role = str(entry.get("role") or fallback or "").strip()
    # El nombre puede ser el rol (main, audio, dotfiles): si no hay uno fijado
    # y el nombre coincide con un rol conocido, ese es su rol.
    if not role and str(name or "").strip().lower() in ROLE_COLORS:
        role = str(name).strip().lower()
    return role or DEFAULT_ROLE


def voice_for(name: str, role: str = "") -> str:
    """Voz fijada (perfil) si la hay; vacío = reparto automático del daemon."""
    entry = _entry(name)
    return str(entry.get("voice") or "").strip()


def identity(name: str, role: str = "") -> dict:
    name = (name or "").strip()
    entry = _entry(name)
    r = role_for(name, role)
    return {
        "name": name,
        "role": r,
        "color": color_for(name, r),
        "voice": voice_for(name, r) or entry.get("voice", ""),
    }


# ── color helpers ───────────────────────────────────────────────────────
def hex_to_rgb(value: str) -> tuple[int, int, int]:
    v = _norm_hex(value) or "#000000"
    return int(v[1:3], 16), int(v[3:5], 16), int(v[5:7], 16)


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    r, g, b = (max(0, min(255, int(round(x)))) for x in rgb)
    return f"#{r:02x}{g:02x}{b:02x}"


def tint(value: str, amount: float = 0.16) -> str:
    """Mezcla el color con negro. Para fondos de panel: el color del agente se
    insinúa sin comerse el texto. amount = cuánto del color original queda."""
    amt = max(0.0, min(1.0, float(amount)))
    r, g, b = hex_to_rgb(value)
    return rgb_to_hex((r * amt, g * amt, b * amt))


def set_field(name: str, key: str, value: str) -> None:
    name = (name or "").strip()
    if not name:
        raise SystemExit("identity: falta el nombre")
    with _lock():
        data = _load()
        agents = data.setdefault("agents", {})
        entry = agents.setdefault(name, {})
        if not isinstance(entry, dict):
            entry = {}
            agents[name] = entry
        if key == "color":
            value = _norm_hex(value)
            if not value:
                raise SystemExit(f"identity: color inválido: {value}")
        if value in ("", None):
            entry.pop(key, None)
        else:
            entry[key] = value
        if not entry:
            agents.pop(name, None)
        _save(data)


def list_agents() -> list[dict]:
    data = _load()
    names = set(data.get("agents", {}).keys())
    return [identity(n) for n in sorted(names)]


# ── CLI ─────────────────────────────────────────────────────────────────
def _usage() -> str:
    return (
        "uso: identity.py {identity|color|role|agents|check|selftest} [args]\n"
        "  identity <nombre> [--role R] [--claim] [--pane %id] [--json]\n"
        "  color <nombre> [--tint] [--amount 0.16] | color <nombre> --set #hex\n"
        "  role <nombre> [rol]\n"
        "  agents [--json]\n"
        "  check                    # colores repetidos entre agentes vivos\n"
        "  selftest                 # verifica el reparto de colores\n"
    )


def _main(argv: list[str]) -> int:
    if not argv:
        print(_usage(), file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    # `voice identity check` / `selftest` son atajos de verificación.
    if cmd in ("identity", "id") and len(args) == 1 and args[0] in ("check", "duplicados", "selftest"):
        cmd, args = args[0], []
    if cmd in ("identity", "id"):
        name = ""
        role = ""
        as_json = False
        do_claim = False
        pane: str | None = None
        i = 0
        while i < len(args):
            a = args[i]
            if a == "--json":
                as_json = True
            elif a == "--claim":
                do_claim = True
            elif a == "--pane":
                i += 1
                pane = args[i] if i < len(args) else ""
            elif a == "--role":
                i += 1
                role = args[i] if i < len(args) else ""
            elif not name:
                name = a
            i += 1
        name = name or os.environ.get("PI_VOICE_AGENT", "") or "voice"
        ident = claim(name, role, pane) if do_claim else identity(name, role)
        if as_json:
            print(json.dumps(ident, ensure_ascii=False))
        else:
            print(f"{ident['name']}\t{ident['role']}\t{ident['color']}")
        return 0
    if cmd == "color":
        name = ""
        as_tint = False
        amount = 0.16
        set_value = None
        i = 0
        while i < len(args):
            a = args[i]
            if a == "--tint":
                as_tint = True
            elif a == "--amount":
                i += 1
                amount = args[i] if i < len(args) else 0.16
            elif a == "--set":
                i += 1
                set_value = args[i] if i < len(args) else ""
            elif not name:
                name = a
            i += 1
        if set_value is not None:
            set_field(name, "color", set_value)
            print(color_for(name))
            return 0
        name = name or os.environ.get("PI_VOICE_AGENT", "") or "voice"
        c = color_for(name)
        print(tint(c, amount) if as_tint else c)
        return 0
    if cmd == "role":
        if not args:
            print(_usage(), file=sys.stderr)
            return 2
        name = args[0]
        if len(args) >= 2:
            set_field(name, "role", args[1])
            print(role_for(name))
        else:
            print(role_for(name))
        return 0
    if cmd == "agents":
        rows = list_agents()
        if "--json" in args:
            print(json.dumps(rows, ensure_ascii=False))
            return 0
        if not rows:
            print("(sin agentes fijados; el color se deriva del nombre)")
            return 0
        for r in rows:
            print(f"{r['name']:<16} {r['role']:<12} {r['color']}  {r['voice']}")
        return 0
    if cmd in ("check", "duplicados"):
        panes = live_panes()
        dups = live_duplicates()
        if not dups:
            print(f"ok: {len(panes)} agente(s) vivo(s), colores únicos")
            return 0
        for color, names in sorted(dups.items()):
            print(f"repetido {color}: {', '.join(names)}")
        return 1
    if cmd == "selftest":
        # El reparto debe dar colores distintos para muchos agentes seguidos.
        used: set[str] = set()
        for _ in range(120):
            c = free_color(used)
            if c in used:
                print(f"FALLA: color repetido {c}")
                return 1
            used.add(c)
        # Y debe respetar los que ya están tomados.
        tomados = {"#7aa2f7", "#9ece6a", "#ff9e64"}
        if free_color(tomados) in tomados:
            print("FALLA: free_color devolvió un color tomado")
            return 1
        print(f"PASS identity ({len(used)} colores únicos)")
        return 0
    print(_usage(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
