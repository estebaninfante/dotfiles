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
MACHINE="$(cat "${HOME}/.config/machine-type" 2>/dev/null || echo desktop)"

FILES=(shell.json shell.toml)
DIRS=(bar branding extensions backgrounds hooks)
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
        [[ -f "$LIVE/$f" ]] || continue
        if [[ "$f" = "shell.json" && -f "$SRC/shell.${MACHINE}.json" ]]; then
            cp -f "$LIVE/$f" "$SRC/shell.${MACHINE}.json"
        else
            cp -f "$LIVE/$f" "$SRC/$f"
        fi
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
    # Temas: los locales (sin .git) se copian; los git se restauran por url.
    : > "$SRC/themes-git.txt"
    rm -rf "$SRC/themes"
    for p in "$LIVE"/themes/*/; do
        [[ -d "$p" ]] || continue
        id="$(basename "$p")"
        if [[ -d "$p/.git" ]]; then
            url="$(git -C "$p" remote get-url origin 2>/dev/null || true)"
            [[ -n "$url" ]] && printf '%s %s\n' "$id" "$url" >> "$SRC/themes-git.txt"
        else
            copy_tree "$p" "$SRC/themes/$id"
        fi
    done

    # Tema activo (para que la laptop aplique el mismo al importar)
    cat "$HOME/.local/state/omarchy/current/theme.name" > "$SRC/theme-current.txt" 2>/dev/null || true

    ok "Config Omarchy exportada a linux/config/omarchy"
}

import_config() {
    [[ -d "$SRC" ]] || { warn "No existe $SRC en el repo"; return 1; }
    mkdir -p "$LIVE"
    local f d id url

    for f in "${FILES[@]}"; do
        [[ -f "$SRC/$f" ]] || continue
        if [[ "$f" = "shell.json" ]]; then
            local cand="$SRC/$f"
            [[ -f "$SRC/shell.${MACHINE}.json" ]] && cand="$SRC/shell.${MACHINE}.json"
            if ! jq -e . "$cand" >/dev/null 2>&1; then
                warn "shell.json invalido, omitido: $cand"
                continue
            fi
            cp -f "$cand" "$LIVE/$f"
        else
            cp -f "$SRC/$f" "$LIVE/$f"
        fi
    done

    for d in "${DIRS[@]}"; do
        [[ -d "$SRC/$d" ]] || continue
        mkdir -p "$LIVE/$d"
        copy_tree "$SRC/$d" "$LIVE/$d"
    done

    [[ -d "$SRC/plugins" ]] && copy_tree "$SRC/plugins" "$LIVE/plugins"
    [[ -d "$SRC/themes" ]]  && copy_tree "$SRC/themes"  "$LIVE/themes"

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

        # Aplicar el tema activo del export, solo si difiere del actual (asi no
        # resetea el fondo elegido en la maquina ya configurada).
        if [[ -f "$SRC/theme-current.txt" ]]; then
            tname="$(cat "$SRC/theme-current.txt")"
            if [[ -n "$tname" && -d "$LIVE/themes/$tname" ]]; then
                cur="$(basename "$(readlink -f "$HOME/.local/state/omarchy/current/theme" 2>/dev/null)" 2>/dev/null)"
                if [[ "$cur" != "$tname" ]]; then
                    omarchy theme set "$tname" >/dev/null 2>&1 \
                        && ok "Tema aplicado: $tname" || warn "No se pudo aplicar el tema: $tname"
                fi
            fi
        fi

        command -v omarchy-restart-shell >/dev/null 2>&1 && omarchy-restart-shell >/dev/null 2>&1 || true
    fi

    ok "Config Omarchy importada a ~/.config/omarchy"
}

status_config() {
    local drift=0 f d rel
    for f in "${FILES[@]}"; do
        local base="$SRC/$f"
        [[ "$f" = "shell.json" && -f "$SRC/shell.${MACHINE}.json" ]] && base="$SRC/shell.${MACHINE}.json"
        if [[ -f "$base" ]] && ! cmp -s "$base" "$LIVE/$f"; then
            echo "DRIFT $f"
            drift=$((drift+1))
        fi
    done
    for d in "${DIRS[@]}"; do
        [[ -d "$SRC/$d" ]] || continue
        while IFS= read -r -d '' rel; do
            case "$rel" in "./$EXCLUDE_HOOK") continue ;; esac
            if ! cmp -s "$SRC/$d/$rel" "$LIVE/$d/$rel"; then
                echo "DRIFT $d/$rel"
                drift=$((drift+1))
            fi
        done < <(cd "$SRC/$d" && find . -type f ! -name '*.sample' -print0)
    done
    if [[ -d "$SRC/plugins" ]]; then
        while IFS= read -r -d '' rel; do
            if ! cmp -s "$SRC/plugins/$rel" "$LIVE/plugins/$rel"; then
                echo "DRIFT plugins/$rel"
                drift=$((drift+1))
            fi
        done < <(cd "$SRC/plugins" && find . -type f -print0)
    fi
    if [[ -d "$SRC/themes" ]]; then
        while IFS= read -r -d '' rel; do
            if ! cmp -s "$SRC/themes/$rel" "$LIVE/themes/$rel"; then
                echo "DRIFT themes/$rel"
                drift=$((drift+1))
            fi
        done < <(cd "$SRC/themes" && find . -type f -print0)
    fi
    if [[ "$drift" -eq 0 ]]; then
        ok "sin drift (live == repo)"
    else
        warn "$drift archivo(s) con drift; corre: omarchy-sync.sh import"
        return 1
    fi
}

case "${1:-}" in
    export) export_config ;;
    import) import_config ;;
    status) status_config ;;
    *) echo "Uso: $(basename "$0") export|import|status"; exit 1 ;;
esac
