#!/usr/bin/env python3
"""scroll-momentum.py — Glide de rueda estilo MX Master en cualquier mouse.

Agarra (EVIOCGRAB) los mouses reales detectados en /dev/input, reenvía
todo sin cambios (movimiento, botones) y solo intercepta la rueda:
tras un flick rápido inyecta una cola de notches con retardo creciente
(decaimiento exponencial) via /dev/uinput → efecto momentum/glide.

- Notch lento (deliberado) = passthrough puro, sin cola.
- Flick rápido = cola de N notches, más largo cuanto más rápido.
- Notch en dirección opuesta = cancela la cola al instante.

Python stdlib puro (sin evdev). Tuning por env vars:
  SM_TAIL_MAX (12)  SM_TAIL_MIN (3)  SM_START_MS (10)  SM_GROWTH (1.6)
  SM_FLICK_MS (160) SM_RATCHET_MS (260) SM_DEVICE (substring de nombre)
Uso: scroll-momentum.py [--no-wait] [--print]
  --no-wait  no espera la sesión de Hyprland
  --print    debug: no agarra nada, solo imprime eventos de rueda
"""
import glob
import os
import re
import select
import signal
import struct
import sys
import time
from collections import deque
from fcntl import ioctl

# ── Config ────────────────────────────────────────────────────────────
def _i(n, d):
    return int(os.environ.get(n, d))

TAIL_MAX = _i("SM_TAIL_MAX", 12)       # notches de cola en flick rápido
TAIL_MIN = _i("SM_TAIL_MIN", 3)        # notches de cola en flick lento
START_MS = _i("SM_START_MS", 10)       # retardo inicial de la cola
GROWTH = float(os.environ.get("SM_GROWTH", "1.6"))  # factor de decaimiento
FLICK_MS = _i("SM_FLICK_MS", 160)      # < esto = flick
RATCHET_MS = _i("SM_RATCHET_MS", 260)  # > esto = notch deliberado, sin cola
DEV_SUBSTR = os.environ.get("SM_DEVICE", "")

NO_WAIT = "--no-wait" in sys.argv
DEBUG = "--print" in sys.argv

# ── Constantes evdev/uinput ───────────────────────────────────────────
IE = struct.Struct("=llHHi")  # input_event (64-bit, 24 bytes)
EV_SYN, EV_KEY, EV_REL, EV_ABS, EV_MSC, EV_SW, EV_LED, EV_SND = 0, 1, 2, 3, 4, 5, 6, 7
REL_X, REL_Y, REL_HWHEEL, REL_WHEEL = 0, 1, 6, 8
REL_WHEEL_HI_RES = 11
KEY_MAX, REL_MAX, MSC_MAX = 767, 15, 7
LED_MAX, SW_MAX, SND_MAX = 15, 7, 2
BTN_MOUSE_FIRST = 0x110

_EVIOCGNAME = (2 << 30) | (256 << 16) | (0x45 << 8) | 0x06
def EVIOCGBIT(ev, ln):
    return (2 << 30) | (ln << 16) | (0x45 << 8) | (0x20 + ev)
EVIOCGRAB = 0x40044590
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_RELBIT = 0x40045566
UI_SET_MSCBIT = 0x40045568
UI_SET_LEDBIT = 0x40045569
UI_SET_SNDBIT = 0x4004556A
UI_SET_SWBIT = 0x4004556D
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502

SKIP_RE = re.compile(
    r"dotool|keyd|virt|passthrough|keyboard|kbd|consumer|system control"
    r"|sleep|power|button|rfkill|video|touchpad|trackpoint|synaptics"
    r"|wacom|tablet|joystick|gamepad", re.I)

log = lambda *a: print(*a, flush=True)


def dev_name(fd):
    buf = bytearray(256)
    n = ioctl(fd, _EVIOCGNAME, buf)
    return buf[:n].decode(errors="replace").strip("\x00")


def dev_bits(fd, ev, ln):
    buf = bytearray(ln)
    n = ioctl(fd, EVIOCGBIT(ev, ln), buf)
    return int.from_bytes(buf[:n], "little")


def find_mice():
    """Devuelve [(path, name, hires)] de los mouses reales con REL_WHEEL."""
    out = []
    for path in sorted(glob.glob("/dev/input/event*")):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            name = dev_name(fd)
            if DEV_SUBSTR and DEV_SUBSTR.lower() not in name.lower():
                continue
            if not name or SKIP_RE.search(name):
                continue
            rel = dev_bits(fd, EV_REL, 16)
            if not (rel >> REL_WHEEL) & 1:
                continue
            absb = dev_bits(fd, EV_ABS, 96)
            if absb & 1:  # ABS_X → touchpad/joystick/etc
                continue
            hires = bool((rel >> REL_WHEEL_HI_RES) & 1)
            out.append((path, name, hires))
        except OSError:
            pass
        finally:
            os.close(fd)
    return out


def setup_uinput():
    ui = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    for ev in (EV_SYN, EV_KEY, EV_REL, EV_MSC, EV_SW, EV_LED, EV_SND):
        ioctl(ui, UI_SET_EVBIT, ev)
    for r in range(REL_MAX + 1):
        ioctl(ui, UI_SET_RELBIT, r)
    for k in range(1, KEY_MAX + 1):
        ioctl(ui, UI_SET_KEYBIT, k)
    for m in range(MSC_MAX + 1):
        ioctl(ui, UI_SET_MSCBIT, m)
    for s in range(SW_MAX + 1):
        ioctl(ui, UI_SET_SWBIT, s)
    for l in range(LED_MAX + 1):
        ioctl(ui, UI_SET_LEDBIT, l)
    for sn in range(SND_MAX + 1):
        ioctl(ui, UI_SET_SNDBIT, sn)
    ident = struct.pack("=80sHHHHi256I", b"scroll-momentum-virt",
                        0x03, 0x1234, 0x5678, 1, 0, *([0] * 256))
    os.write(ui, ident)
    ioctl(ui, UI_DEV_CREATE)
    return ui


def wait_hyprland():
    """Espera sesión Hyprland: evita agarrar el mouse en GDM pre-login."""
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return
    run = "/run/user/%d/hypr" % os.getuid()
    while True:
        if glob.glob(run + "/*/socket2.sock") or glob.glob(run + "/*/socket.sock"):
            time.sleep(1)
            return
        time.sleep(2)


def main():
    if not NO_WAIT and not DEBUG:
        wait_hyprland()

    mice = find_mice()
    if not mice:
        log("scroll-momentum: no encontré mouse con REL_WHEEL; salgo")
        return 1
    for p, n, h in mice:
        log("scroll-momentum: %s (%s)%s" % (n, p, " [hi-res]" if h else ""))

    sources = []  # (fd, name, hires)
    for p, n, h in mice:
        fd = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
        if not DEBUG:
            ioctl(fd, EVIOCGRAB, 1)
        sources.append((fd, n, h))

    ui = None if DEBUG else setup_uinput()

    hires_by_fd = {fd: h for fd, _, h in sources}
    pending = []        # [(due_monotonic, code, value)] ordenada por due
    last_notch = 0.0
    last_dir = 0
    hist = deque(maxlen=24)  # timestamps de notches recientes

    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def emit(code, val):
        now = time.time()
        os.write(ui, IE.pack(int(now), int(now * 1e6) % 1000000, EV_REL, code, val))
        os.write(ui, IE.pack(int(now), int(now * 1e6) % 1000000, EV_SYN, 0, 0))

    def wheel(code, val):
        """Flick detectado → programa cola de momentum. Devuelve True si
        el evento original ya se manejó (se reenvía aparte)."""
        nonlocal last_notch, last_dir
        now = time.monotonic()
        d = 1 if val > 0 else -1
        if d != last_dir:
            pending.clear()
            last_dir = d
            last_notch = now
            return False  # notch de frenado: sin cola
        interval = (now - last_notch) * 1000
        last_notch = now
        if interval > RATCHET_MS:
            return False  # notch deliberado: passthrough puro
        hist.append(now)
        f = max(0.0, min(1.0, (RATCHET_MS - interval) / RATCHET_MS))
        count = TAIL_MIN + round((TAIL_MAX - TAIL_MIN) * f)
        count = min(count + max(0, len(hist) - 2) * 2, TAIL_MAX + 6)
        t = now
        for i in range(count):
            t += min(START_MS / 1000 * (GROWTH ** i), 0.5)
            pending.append((t, code, val))
        pending.sort(key=lambda x: x[0])
        return False

    try:
        while running:
            now = time.monotonic()
            # cap 0.25s: garantiza re-chequear running/pendientes (y
            # desbloquea tras SIGTERM pese al retry EINTR de PEP 475)
            timeout = 0.25
            if pending and not DEBUG:
                timeout = min(0.25, max(0.0, pending[0][0] - now))
            r, _, _ = select.select([fd for fd, _, _ in sources], [], [], timeout)
            now = time.monotonic()
            while pending and pending[0][0] <= now:
                _, code, val = pending.pop(0)
                emit(code, val)
            for fd in r:
                try:
                    data = os.read(fd, 768)
                except BlockingIOError:
                    continue
                if not data:
                    raise EOFError("dispositivo perdido")
                for off in range(0, len(data) - 23, 24):
                    _, _, typ, code, val = IE.unpack_from(data, off)
                    if typ == EV_REL and val != 0 and (
                        (hires_by_fd.get(fd) and code == REL_WHEEL_HI_RES)
                        or (not hires_by_fd.get(fd) and code == REL_WHEEL)):
                        if DEBUG:
                            log("wheel %s %+d" % (
                                "HI_RES" if code == REL_WHEEL_HI_RES else "notch", val))
                        else:
                            wheel(code, val)
                    if not DEBUG:
                        os.write(ui, data[off:off + 24])
    except EOFError as e:
        log("scroll-momentum: %s; salgo (systemd reinicia)" % e)
        return 1
    finally:
        if ui is not None:
            ioctl(ui, UI_DEV_DESTROY)
            os.close(ui)
        for fd, _, _ in sources:
            os.close(fd)  # cierra → kernel libera el grab
    log("scroll-momentum: fin limpio")
    return 0


if __name__ == "__main__":
    sys.exit(main())
