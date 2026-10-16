#!/usr/bin/env python3
"""Lector standalone de PDF/texto con Kokoro (voz local).

Se usa a través del wrapper `kokoro-read` (ver linux/bin/kokoro-read y
scripts/setup-kokoro-reader.sh).

Uso:
  kokoro-read <archivo.pdf|archivo.txt> [--voice V] [--speed S] [--with-refs]

Controles (también via kokoro-ctl):
  señales:  SIGUSR1 pausa/continuar | SIGUSR2 siguiente | SIGURG anterior | SIGTERM salir
  teclado (si corre en una terminal): espacio = pausa, n = siguiente, b = anterior, q = salir
"""
import argparse, os, queue, re, signal, subprocess, sys, threading, warnings
warnings.filterwarnings("ignore")
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

CONFIG = os.path.expanduser("~/.config/kokoro-reader/voice")

def log(*a):
    print(*a, file=sys.stderr, flush=True)

# ---------- extracción y limpieza de texto ----------

def extract_text(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    if path.lower().endswith(".pdf"):
        out = subprocess.run(["pdftotext", path, "-"], capture_output=True, text=True)
        if out.returncode != 0:
            sys.exit(f"pdftotext falló: {out.stderr.strip()}")
        return out.stdout
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()

def clean(raw: str, with_refs: bool) -> list[str]:
    paras, cur = [], []
    for line in raw.splitlines():
        s = line.strip()
        if not s or s == "\x0c":
            if cur: paras.append(" ".join(cur)); cur = []
            continue
        if re.fullmatch(r"\d{1,4}", s):            # números de página
            continue
        if re.fullmatch(r"\d{4}[-/]\d{1,2}[-/]\d{1,2}", s):  # fecha del encabezado
            continue
        if cur and cur[-1].endswith("-"):          # guion de corte de línea
            cur[-1] = cur[-1][:-1] + s
        else:
            cur.append(s)
    if cur: paras.append(" ".join(cur))

    # encabezados/pies repetidos en cada página (running heads)
    from collections import Counter
    counts = Counter(p for p in paras if len(p) < 70)
    seen, kept = set(), []
    for p in paras:
        if len(p) < 70 and counts[p] >= 3:
            if p in seen:
                continue
            seen.add(p)
        kept.append(p)
    paras = kept

    if not with_refs:  # cortar en "References"
        for i, p in enumerate(paras):
            if i > len(paras) * 0.4 and re.match(r"(?i)^references\b|^bibliography\b", p):
                paras = paras[:i]
                break

    out = []
    for p in paras:
        p = re.sub(r"\[[\d,\s–\-]+\]", "", p)          # citas [12]
        p = re.sub(r"https?://\S+|www\.\S+", "", p)    # URLs
        p = re.sub(r"\s+", " ", p).strip()
        if len(p) < 3:
            continue
        if re.match(r"^(Figure|Table|Fig\.|Algorithm)\s*\d+", p):  # pies de figura/tabla
            continue
        letters = sum(c.isalpha() for c in p)
        if len(p) > 60 and letters / len(p) < 0.55:    # tablas / ecuaciones
            continue
        out.append(p)
    return out

def chunk(paragraphs: list[str], maxlen=350) -> list[str]:
    chunks = []
    for p in paragraphs:
        sents = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9\"“(])", p)
        buf = ""
        for s in sents:
            if len(buf) + len(s) + 1 > maxlen and buf:
                chunks.append(buf); buf = s
            else:
                buf = f"{buf} {s}".strip()
        if buf:
            chunks.append(buf)
    return chunks

# ---------- reproductor ----------

class Player:
    CMD = ["aplay", "-q", "-f", "S16_LE", "-r", "24000", "-c", "1", "-"]

    def __init__(self):
        self.proc = None
        self.paused = False
        self.open()

    def open(self):
        self.proc = subprocess.Popen(self.CMD, stdin=subprocess.PIPE)

    def write(self, data: bytes):
        try:
            self.proc.stdin.write(data)
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError):
            pass

    def restart(self):
        try: self.proc.kill()
        except Exception: pass
        self.paused = False
        self.open()

    def toggle_pause(self):
        sig = signal.SIGCONT if self.paused else signal.SIGSTOP
        try:
            os.kill(self.proc.pid, sig)
            self.paused = not self.paused
            log("⏸  pausa" if self.paused else "▶  sigue")
        except Exception:
            pass

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=3)
        except Exception:
            try: self.proc.kill()
            except Exception: pass

# ---------- programa principal ----------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--voice", default=None)
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--with-refs", action="store_true")
    args = ap.parse_args()

    voice = args.voice
    if not voice and os.path.exists(CONFIG):
        voice = open(CONFIG).read().strip()
    voice = voice or "am_liam"

    chunks = chunk(clean(extract_text(args.input), args.with_refs))
    if not chunks:
        sys.exit("No encontré texto legible.")
    n = len(chunks)
    log(f"📄 {n} fragmentos | voz: {voice} | velocidad: {args.speed}")

    from kokoro import KPipeline
    import numpy as np
    pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")

    player = Player()
    q = queue.Queue(maxsize=3)
    state = {"next": 0, "gen": 0, "quit": False, "cur": 0}

    def synth(i):
        parts = []
        for _gs, _ps, audio in pipe(chunks[i], voice=voice, speed=args.speed):
            if state["quit"]:
                return None
            a = np.asarray(getattr(audio, "numpy", lambda: audio)(), dtype=np.float32)
            parts.append(a)
        if not parts:
            return b""
        a = np.concatenate(parts)
        return (np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes()

    def producer():
        while not state["quit"]:
            i = state["next"]
            if i is None or i >= n:
                q.put((state["gen"], None, None))
                return
            g = state["gen"]
            pcm = synth(i)
            if state["quit"]:
                return
            if g != state["gen"]:
                continue                      # hubo salto: releyo state["next"]
            q.put((g, i, pcm))
            if state["next"] == i:
                state["next"] = i + 1

    def drain():
        while True:
            try: q.get_nowait()
            except queue.Empty: return

    def on_pause(sig, frm):
        player.toggle_pause()
    def on_next(sig, frm):
        state["gen"] += 1
        state["next"] = min(state["cur"] + 1, n)
        drain(); player.restart()
    def on_back(sig, frm):
        state["gen"] += 1
        state["next"] = max(state["cur"] - 1, 0)
        drain(); player.restart()
    def on_quit(sig, frm):
        state["quit"] = True
        player.restart()
        try: q.put_nowait((state["gen"], None, None))
        except queue.Full: pass
    signal.signal(signal.SIGUSR1, on_pause)
    signal.signal(signal.SIGUSR2, on_next)
    signal.signal(signal.SIGURG, on_back)
    signal.signal(signal.SIGTERM, on_quit)
    signal.signal(signal.SIGINT, on_quit)

    if sys.stdin.isatty():
        def keys():
            import termios, tty
            fd = sys.stdin.fileno()
            old = termios.tcgetattr(fd)
            try:
                tty.setcbreak(fd)
                while not state["quit"]:
                    c = sys.stdin.read(1)
                    if c == " ": on_pause(None, None)
                    elif c in "nl": on_next(None, None)
                    elif c == "b": on_back(None, None)
                    elif c == "q": on_quit(None, None); break
            except Exception:
                pass
            finally:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
        threading.Thread(target=keys, daemon=True).start()

    threading.Thread(target=producer, daemon=True).start()

    while not state["quit"]:
        g, i, pcm = q.get()
        if pcm is None:
            break
        if g != state["gen"] or not pcm:
            continue
        state["cur"] = i
        log(f"[{i+1}/{n}]")
        player.write(pcm)

    player.close()
    log("👋 lectura terminada" if not state["quit"] else "👋 saliendo")

if __name__ == "__main__":
    main()
