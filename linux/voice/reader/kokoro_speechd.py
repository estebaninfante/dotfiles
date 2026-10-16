#!/usr/bin/env python3
"""Cliente de kokoro-server para speech-dispatcher.

Lee el texto de stdin, pide la síntesis al servidor y reproduce el PCM
resultante con aplay. Se invoca desde el módulo genérico kokoro.conf
(ver scripts/setup-kokoro-reader.sh).
"""
import argparse
import fcntl
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import time

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/kokoro-{os.getuid()}"
SOCKET_PATH = os.path.join(RUNTIME, "kokoro-tts.sock")
SPAWN_LOCK = os.path.join(RUNTIME, "kokoro-tts.spawn.lock")
SERVER = shutil.which("kokoro-server") or os.path.expanduser("~/.local/bin/kokoro-server")
PLAYER = ["aplay", "-q", "-f", "S16_LE", "-r", "24000", "-c", "1", "-"]
START_TIMEOUT = 90


def try_connect(timeout: float = 0.5) -> socket.socket:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(SOCKET_PATH)
    sock.settimeout(None)
    return sock


def ensure_server() -> socket.socket:
    try:
        return try_connect()
    except OSError:
        pass

    os.makedirs(RUNTIME, exist_ok=True)
    with open(SPAWN_LOCK, "w") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        try:
            return try_connect()
        except OSError:
            pass
        subprocess.Popen(
            ["setsid", SERVER],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.time() + START_TIMEOUT
        while time.time() < deadline:
            try:
                return try_connect(1.0)
            except OSError:
                time.sleep(0.3)
    raise SystemExit("kokoro-server no respondió a tiempo")


def recv_exact(sock: socket.socket, length: int):
    chunks = []
    remaining = length
    while remaining > 0:
        data = sock.recv(remaining)
        if not data:
            return None
        chunks.append(data)
        remaining -= len(data)
    return b"".join(chunks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--voice", default="")
    parser.add_argument("--rate", type=float, default=0.0)
    parser.add_argument("--volume", type=float, default=100.0)
    args = parser.parse_args()

    text = sys.stdin.read().strip()
    if not text:
        return

    conn = ensure_server()
    request = json.dumps({
        "text": text,
        "voice": args.voice,
        "rate": args.rate,
        "volume": args.volume,
    })
    conn.sendall(request.encode("utf-8") + b"\n")

    player = subprocess.Popen(PLAYER, stdin=subprocess.PIPE)
    try:
        while True:
            header = recv_exact(conn, 4)
            if header is None:
                break
            size = struct.unpack(">I", header)[0]
            if size == 0:
                break
            pcm = recv_exact(conn, size)
            if pcm is None:
                break
            player.stdin.write(pcm)
            player.stdin.flush()
    except (BrokenPipeError, ConnectionResetError, OSError):
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass
        try:
            player.stdin.close()
        except OSError:
            pass
        player.wait()


if __name__ == "__main__":
    main()
