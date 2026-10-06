#!/usr/bin/env bash
set -uo pipefail

DOMAIN=ai-chats
SRC="$HOME/dotfiles/linux/ai-chats"
BIN_DIR="$HOME/dotfiles/linux/bin"
VENV="$HOME/ai-chats/.venv"
PY="$VENV/bin/python"
STORE="$HOME/ai-chats"
STAGING="$HOME/Downloads/AIChats"
MODEL_CACHE="$HOME/.cache/fastembed"
UNITS_SRC="$HOME/dotfiles/linux/system/systemd-user"
UNITS_DST="$HOME/.config/systemd/user"
SCRIPTS=(ai-chats-ingest ai-chats-embed ai-chats-search ai-chats-mcp)

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

targets=()
for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\t%s\n' "$DOMAIN"
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

if [ ! -x "$PY" ]; then
  fail "venv" "falta el interprete $PY"
  exit "$rc"
fi

if (cd "$SRC" && timeout 60 "$PY" -m ruff check .) >/dev/null 2>&1; then
  ok "lint:ruff" "limpio"
else
  fail "lint:ruff" "$(cd "$SRC" && timeout 60 "$PY" -m ruff check . 2>&1 | tail -n3 | tr '\n' ' ')"
fi

if (cd "$SRC" && timeout 60 "$PY" -m mypy .) >/dev/null 2>&1; then
  ok "lint:mypy" "sin errores"
else
  fail "lint:mypy" "$(cd "$SRC" && timeout 60 "$PY" -m mypy . 2>&1 | tail -n3 | tr '\n' ' ')"
fi

if pytest_out=$(cd "$SRC" && timeout 60 "$PY" -m pytest -q 2>&1); then
  ok "test:pytest" "$(printf '%s' "$pytest_out" | tail -n1)"
else
  fail "test:pytest" "$(printf '%s' "$pytest_out" | tail -n3 | tr '\n' ' ')"
fi

for name in "${SCRIPTS[@]}"; do
  src="$BIN_DIR/$name"
  link="$HOME/.local/bin/$name"
  if [ -f "$src" ] && [ -x "$src" ]; then
    ok "script:$name" "ejecutable"
  else
    fail "script:$name" "falta o sin bit x: $src"
    continue
  fi
  if [ "$(head -n1 "$src")" = "#!$PY" ]; then
    ok "shebang:$name" "venv"
  else
    fail "shebang:$name" "esperaba #!$PY"
  fi
  if [ -L "$link" ] && [ -x "$link" ]; then
    ok "symlink:$name" "$(readlink "$link")"
  else
    fail "symlink:$name" "symlink roto o ausente: $link"
  fi
done

for target in "${targets[@]}"; do
  case "$target" in
    *.py)
      if "$PY" -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))' "$target" 2>/dev/null; then
        ok "ast:$(basename "$target")" "parse ok"
      else
        fail "ast:$(basename "$target")" "sintaxis invalida"
      fi
      ;;
    *.sh)
      if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck "$target" >/dev/null 2>&1; then
          ok "shellcheck:$(basename "$target")" "limpio"
        else
          fail "shellcheck:$(basename "$target")" "$(shellcheck "$target" 2>&1 | head -n2 | tr '\n' ' ')"
        fi
      else
        skip "shellcheck:$(basename "$target")" "shellcheck no instalado"
      fi
      ;;
  esac
done

if selftest_out=$(timeout 40 "$HOME/.local/bin/ai-chats-ingest" --selftest 2>&1); then
  ok "selftest:ingest" "ok"
else
  fail "selftest:ingest" "$(printf '%s' "$selftest_out" | head -n2 | tr '\n' ' ')"
fi

if selftest_out=$(timeout 40 "$HOME/.local/bin/ai-chats-search" --selftest 2>&1); then
  ok "selftest:search" "ok"
else
  fail "selftest:search" "$(printf '%s' "$selftest_out" | head -n2 | tr '\n' ' ')"
fi

if selftest_out=$(timeout 90 "$HOME/.local/bin/ai-chats-embed" --selftest 2>&1); then
  ok "selftest:embed" "ok"
else
  fail "selftest:embed" "$(printf '%s' "$selftest_out" | head -n2 | tr '\n' ' ')"
fi

if selftest_out=$(timeout 40 "$HOME/.local/bin/ai-chats-mcp" --selftest 2>&1); then
  ok "selftest:mcp" "ok"
else
  fail "selftest:mcp" "$(printf '%s' "$selftest_out" | head -n2 | tr '\n' ' ')"
fi

for unit in ai-chats-sync.service ai-chats-sync.timer ai-chats-ingest.path; do
  if [ -f "$UNITS_DST/$unit" ] && [ -f "$UNITS_SRC/$unit" ]; then
    if cmp -s "$UNITS_SRC/$unit" "$UNITS_DST/$unit"; then
      ok "drift:$unit" "fuente == instalado"
    else
      fail "drift:$unit" "el instalado difiere de $UNITS_SRC/$unit"
    fi
  else
    fail "drift:$unit" "falta fuente o instalado"
  fi
done

if unit_out=$(systemd-analyze verify --user "$UNITS_DST/ai-chats-sync.service" "$UNITS_DST/ai-chats-sync.timer" "$UNITS_DST/ai-chats-ingest.path" 2>&1); then
  ok "unit:systemd-analyze" "verify limpio"
else
  fail "unit:systemd-analyze" "$(printf '%s' "$unit_out" | head -n2 | tr '\n' ' ')"
fi

for unit in ai-chats-sync.timer ai-chats-ingest.path; do
  if state=$(systemctl --user is-enabled "$unit" 2>/dev/null); then
    ok "unit:enabled:$unit" "$state"
  else
    fail "unit:enabled:$unit" "no habilitada"
  fi
  if state=$(systemctl --user is-active "$unit" 2>/dev/null); then
    ok "unit:active:$unit" "$state"
  else
    fail "unit:active:$unit" "inactiva"
  fi
done

if [ -d "$STORE" ]; then
  ok "layout:store" "$STORE"
else
  fail "layout:store" "falta $STORE"
fi
if [ -d "$STAGING" ]; then
  ok "layout:staging" "$STAGING"
else
  fail "layout:staging" "falta $STAGING"
fi

if [ -d "$MODEL_CACHE/models--intfloat--multilingual-e5-small" ]; then
  ok "model-cache" "modelo e5-small cacheado"
else
  fail "model-cache" "falta $MODEL_CACHE/models--intfloat--multilingual-e5-small"
fi

if db_out=$(timeout 30 "$PY" - 2>&1 <<'PYEOF'
import pathlib
import sqlite3
import tempfile

import sqlite_vec

from ai_chats.config import EMBEDDING_DIM, MODEL_NAME, Paths


def check(conn: sqlite3.Connection) -> None:
    conn.row_factory = sqlite3.Row
    tables = {
        row["name"]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    if not {"files", "chunks", "meta"} <= tables:
        raise RuntimeError(f"tablas faltantes: {sorted({'files', 'chunks', 'meta'} - tables)}")
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    meta = dict(conn.execute("SELECT key, value FROM meta").fetchall())
    if meta.get("model") != MODEL_NAME or meta.get("dim") != str(EMBEDDING_DIM):
        raise RuntimeError(f"meta incompatible: {meta}")
    zero = b"\x00" * (4 * EMBEDDING_DIM)
    conn.execute(
        "SELECT chunk_id FROM chunks WHERE embedding MATCH ? AND k = 1",
        (zero,),
    ).fetchall()


real = Paths.default().db_path
if real.exists():
    conn = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
else:
    tmp = tempfile.mkdtemp(prefix="ai-chats-verify-")
    conn = sqlite3.connect(pathlib.Path(tmp) / "chats.sqlite")
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(
        "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
    )
    conn.execute(
        "CREATE TABLE files (path TEXT PRIMARY KEY, sha256 TEXT NOT NULL,"
        " mtime REAL NOT NULL, platform TEXT NOT NULL, embedded_sha256 TEXT)"
    )
    conn.execute(
        "CREATE VIRTUAL TABLE chunks USING vec0(embedding float[384] distance_metric=cosine,"
        " source_path TEXT, chunk_index INTEGER, platform TEXT, chunk_text TEXT)"
    )
    conn.execute(
        "INSERT INTO meta (key, value) VALUES ('model', ?), ('dim', ?)",
        (MODEL_NAME, str(EMBEDDING_DIM)),
    )
try:
    check(conn)
finally:
    conn.close()
print("ok")
PYEOF
); then
  ok "db:schema" "esquema + vec0 + meta ok"
else
  fail "db:schema" "$(printf '%s' "$db_out" | tail -n3 | tr '\n' ' ')"
fi

if mcp_out=$(timeout 30 "$PY" - 2>&1 <<'PYEOF'
import json
import pathlib
import shutil
import sys

config = pathlib.Path.home() / ".config/opencode/opencode.json"
try:
    data = json.loads(config.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"BROKEN:opencode.json ilegible: {exc}")
    sys.exit(0)
for name, entry in (data.get("mcp") or {}).items():
    if not isinstance(entry, dict):
        continue
    command = entry.get("command") or []
    if not any("ai-chats" in str(part) for part in command):
        continue
    if shutil.which(command[0]):
        print(f"REGISTERED:{name}")
    else:
        print(f"BROKEN:{command[0]} no resuelve en PATH")
    sys.exit(0)
print("MISSING")
PYEOF
); then
  case "$mcp_out" in
    REGISTERED:*)
      ok "mcp:registered" "${mcp_out#REGISTERED:}"
      ;;
    BROKEN:*)
      fail "mcp:registered" "${mcp_out#BROKEN:}"
      ;;
    *)
      skip "mcp:registered" "registrar en opencode.json: {\"ai-chats\": {\"type\": \"local\", \"command\": [\"ai-chats-mcp\"], \"enabled\": true}}"
      ;;
  esac
else
  fail "mcp:registered" "$(printf '%s' "$mcp_out" | tail -n2 | tr '\n' ' ')"
fi

if command -v ai-chats-mcp >/dev/null 2>&1; then
  ok "mcp:command" "$(command -v ai-chats-mcp)"
else
  fail "mcp:command" "ai-chats-mcp no esta en PATH"
fi

exit "$rc"
