#!/usr/bin/env bash
# omarchy-sync.sh — Versiona la config del shell de Omarchy (barra, widgets,
# branding, hooks y plugins locales) entre el repo y ~/.config/omarchy.
#
# El repo es la fuente de verdad: en el desktop se corre `export` tras
# personalizar la barra; en la laptop `import` la replica (setup-omarchy.sh lo
# llama automaticamente). Los plugins/temas instalados desde git NO se copian
# (tienen .git y peso): se guarda su id+url y se reinstalan con `omarchy plugin
# add` / `omarchy theme install`.
#
#   export : live (~/.config/omarchy) -> repo (linux/config/omarchy)
#   import : repo -> live (+ instala plugins/temas git que falten)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE="${OMARCHY_CONFIG_DIR:-$HOME/.config/omarchy}"
SRC="$REPO/linux/config/omarchy"

# Archivos sueltos gestionados
FILES=(shell.json shell.toml)
# Directorios gestionados (se copian enteros, sin *.sample de Omarchy)
DIRS=(bar branding extensions backgrounds hooks)
# Hook que setup-omarchy.sh instala desde linux/bin/ (no duplicar en el repo)
EXCLUDE_HOOK="theme-set.d/sync-wallpaper.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

copy_tree() { # copy_tree <src> <dst>  (omite *.sample)
    local src="$1" dst="$2" rel
    mkdir -p "$dst"
    while IFS= read -r -d '' rel; do
        case "$rel" in "./$EXCLUDE_HOOK") continue ;; esac
        mkdir -p "$dst/$(dirname "$rel")"
        cp -f "$src/$rel" "$dst/$rel"
    done < <(cd "$src" && find . -type f ! -name '*.sample' -print0)
}

export_config() {
    mkdir -p "$SRC"
    local f d p id url

    for f in "${FILES[@]}"; do
        [[ -f "$LIVE/$f" ]] && cp -f "$LIVE/$f" "$SRC/$f"
    done

    for d in "${DIRS[@]}"; do
        [[ -d "$LIVE/$d" ]] || continue
        rm -rf "$SRC/$d"
        copy_tree "$LIVE/$d" "$SRC/$d"
    done

    # Plugins locales (sin .git) — los git se restauran por url
    rm -rf "$SRC/plugins"
    for p in "$LIVE"/plugins/*/; do
        [[ -d "$p/.git" ]] && continue
        id="$(basename "$p")"
        copy_tree "$p" "$SRC/plugins/$id"
    done

    # Manifests de plugins/temas git: "<id> <url>"
    : > "$SRC/plugins-git.txt"
    for p in "$LIVE"/plugins/*/; do
        [[ -d "$p/.git" ]] || continue
        id="$(basename "$p")"
        url="$(git -C "$p" remote get-url origin 2>/dev/null || true)"
        [[ -n "$url" ]] && printf '%s %s\n' "$id" "$url" >> "$SRC/plugins-git.txt"
    done
    : > "$SRC/themes-git.txt"
    for p in "$LIVE"/themes/*/; do
        [[ -d "$p/.git" ]] || continue
        id="$(basename "$p")"
        url="$(git -C "$p" remote get-url origin 2>/dev/null || true)"
        [[ -n "$url" ]] && printf '%s %s\n' "$id" "$url" >> "$SRC/themes-git.txt"
    done

    ok "Config Omarchy exportada a linux/config/omarchy"
}

import_config() {
    [[ -d "$SRC" ]] || { warn "No existe $SRC en el repo"; return 1; }
    mkdir -p "$LIVE"
    local f d id url

    for f in "${FILES[@]}"; do
        [[ -f "$SRC/$f" ]] && cp -f "$SRC/$f" "$LIVE/$f"
    done

    for d in "${DIRS[@]}"; do
        [[ -d "$SRC/$d" ]] || continue
        mkdir -p "$LIVE/$d"
        copy_tree "$SRC/$d" "$LIVE/$d"
    done

    [[ -d "$SRC/plugins" ]] && copy_tree "$SRC/plugins" "$LIVE/plugins"

    if command -v omarchy &>/dev/null; then
        if [[ -f "$SRC/plugins-git.txt" ]]; then
            while read -r id url; do
                [[ -z "${id:-}" || -z "${url:-}" ]] && continue
                [[ -d "$LIVE/plugins/$id" ]] && continue
                if omarchy plugin add "$url" --enable --yes >/dev/null 2>&1; then
                    ok "Plugin instalado: $id"
                else
                    warn "No se pudo instalar plugin: $id"
                fi
            done < "$SRC/plugins-git.txt"
        fi
        if [[ -f "$SRC/themes-git.txt" ]]; then
            while read -r id url; do
                [[ -z "${id:-}" || -z "${url:-}" ]] && continue
                [[ -d "$LIVE/themes/$id" ]] && continue
                if omarchy theme install "$url" >/dev/null 2>&1; then
                    ok "Tema instalado: $id"
                else
                    warn "No se pudo instalar tema: $id"
                fi
            done < "$SRC/themes-git.txt"
        fi
        omarchy bar use eztvn.bar >/dev/null 2>&1 && ok "Barra activa: eztvn.bar" || true
        command -v omarchy-restart-shell >/dev/null 2>&1 && omarchy-restart-shell >/dev/null 2>&1 || true
    fi

    ok "Config Omarchy importada a ~/.config/omarchy"
}

case "${1:-}" in
    export) export_config ;;
    import) import_config ;;
    *) echo "Uso: $(basename "$0") export|import"; exit 1 ;;
esac
