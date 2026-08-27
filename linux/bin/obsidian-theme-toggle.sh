#!/usr/bin/env bash
# Toggle Obsidian dark↔light (legibilidad día/noche).
# Modifica appearance.json del vault; Obsidian recarga en vivo.
set -euo pipefail

VAULT="${OBSIDIAN_VAULT:-$HOME/alicia}"
APPEARANCE="$VAULT/.obsidian/appearance.json"

if [[ ! -f "$APPEARANCE" ]]; then
    echo "error: $APPEARANCE no existe" >&2
    exit 1
fi

current=$(python3 -c "import json; print(json.load(open('$APPEARANCE')).get('base','dark'))")

case "${1:-toggle}" in
    light)  target=light ;;
    dark)   target=dark ;;
    toggle) [[ "$current" == "dark" ]] && target=light || target=dark ;;
    *)      echo "uso: obsidian-theme-toggle.sh [light|dark|toggle]" >&2; exit 1 ;;
esac

python3 -c "
import json
p = '$APPEARANCE'
d = json.load(open(p))
d['base'] = '$target'
json.dump(d, open(p, 'w'), indent=2)
"
echo "obsidian theme: $target"
