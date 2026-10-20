#!/usr/bin/env bash
# verify/skills.sh — las skills cargan de verdad.
#
# Solo lee; no cambia nada. Sale 0 si:
#   - todo SKILL.md tiene frontmatter YAML válido (el caso típico de rotura es
#     una `description` sin comillas con ": " adentro: YAML lo lee como mapa);
#   - tiene `name` y `description` no vacíos, y `name` == nombre de la carpeta;
#   - no hay dos carpetas con el mismo nombre en el mismo directorio de skills
#     (pasa cuando link-dotfiles.sh dejaba backups al lado: x.pre-dotfiles.*);
#   - no quedan restos *.pre-dotfiles.* dentro de un directorio de skills.
#
# Uso:
#   scripts/verify/skills.sh           # texto
#   scripts/verify/skills.sh --quiet   # solo FALLA/AVISO
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }
aviso(){ [ "$QUIET" = 1 ] || printf '  aviso %s\n' "$*"; }

# Directorios que el harness lee como fuentes de skills.
SKILL_DIRS=(
    "$HOME/.pi/agent/skills"
    "$HOME/.agents/skills"
    "$REPO/linux/pi/agent/skills"
)

# --- 1. frontmatter válido + name/description ------------------------------
python3 - "$fails" "${SKILL_DIRS[@]}" <<'PY' || fails=$((fails + $?))
import os, sys, glob, yaml

fails = 0
dirs = [d for d in sys.argv[2:] if os.path.isdir(d)]
seen = {}
checked = 0

for base in dirs:
    # restos de backups dentro del directorio de skills
    for junk in sorted(glob.glob(os.path.join(base, "*.pre-dotfiles.*"))):
        print(f"  FALLA resto de backup dentro de skills: {junk}")
        fails += 1

    for entry in sorted(os.listdir(base)):
        path = os.path.join(base, entry)
        skill = os.path.join(path, "SKILL.md")
        if not os.path.isdir(path):
            continue
        if entry.startswith(".") or ".pre-dotfiles." in entry:
            continue
        if not os.path.isfile(skill):
            print(f"  FALLA {path}: carpeta sin SKILL.md")
            fails += 1
            continue
        checked += 1
        txt = open(skill, encoding="utf-8").read()
        if not txt.startswith("---"):
            print(f"  FALLA {skill}: no abre con frontmatter ---")
            fails += 1
            continue
        parts = txt.split("---", 2)
        try:
            fm = yaml.safe_load(parts[1])
        except Exception as e:
            print(f"  FALLA {skill}: YAML roto ({str(e).splitlines()[0]})")
            fails += 1
            continue
        if not isinstance(fm, dict):
            print(f"  FALLA {skill}: frontmatter no es un mapa")
            fails += 1
            continue
        name = (fm.get("name") or "").strip()
        desc = (fm.get("description") or "").strip()
        if not name:
            print(f"  FALLA {skill}: falta name")
            fails += 1
        elif name != entry:
            print(f"  FALLA {skill}: name '{name}' != carpeta '{entry}'")
            fails += 1
        if not desc:
            print(f"  FALLA {skill}: falta description")
            fails += 1
        key = (base, name or entry)
        if key in seen:
            print(f"  FALLA nombre duplicado '{name or entry}' en {base}: {seen[key]} y {skill}")
            fails += 1
        else:
            seen[key] = skill

if not fails:
    print(f"  ok    {checked} skills cargan bien")
sys.exit(1 if fails else 0)
PY

[ "$fails" -eq 0 ] && [ "$QUIET" = 0 ] && printf 'skills: OK\n'
[ "$fails" -eq 0 ] && exit 0
exit 1
