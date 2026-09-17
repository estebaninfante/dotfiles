#!/usr/bin/env bash
# link-dotfiles.sh — Crea/actualiza los symlinks del repo hacia $HOME.
#
# Idempotente: se puede correr las veces que haga falta. Unico comando que
# aplica el inventario de configs/scripts del repo a la maquina.
#
# Uso:
#   bash ~/dotfiles/scripts/link-dotfiles.sh          # aplica
#   bash ~/dotfiles/scripts/link-dotfiles.sh --dry    # solo muestra
#
# El repo (~/dotfiles) es la fuente de verdad. Los destinos en ~/.config,
# ~/.local/bin y ~/ son symlinks al repo (salvo excepciones marcadas).
set -uo pipefail

REPO="${HOME}/dotfiles"
CONFIG_SRC="${REPO}/linux/config"
BIN_SRC="${REPO}/linux/bin"
HOME_SRC="${REPO}/linux/home"

DRY=false
[ "${1:-}" = "--dry" ] && DRY=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC}  $1"; }
header(){ echo -e "\n\033[1m═══ $1 ═══\033[0m"; }

# ── Inventario ─────────────────────────────────────────────────
# Directorios de config -> ~/.config/<name> (symlink)
CONFIG_DIRS=(
    hypr waybar kitty nvim kanata fastfetch
    mako swaync swayosd avizo btop gh opencode quickshell tmux
    gesturecontrol voice
)
# Archivos sueltos -> ~/.config/<name> (symlink)
CONFIG_FILES=(
    libinput-gestures.conf mimeapps.list user-dirs.dirs user-dirs.locale
)
# Archivos de home -> ~/<name> (symlink)
HOME_FILES=( .bashrc .gitconfig )
# Directorios copiados (no symlink): apps que reescriben su config
COPY_DIRS=( input-remapper-2 )
# Machine-specific: se copia config.<machine>.toml -> ~/.config/lan-mouse/config.toml
LANMOUSE_SRC="${CONFIG_SRC}/lan-mouse"
# VS Code: solo settings.json y keybindings.json dentro de ~/.config/Code/User
# (el resto del dir User lo reescribe el editor; no se symlinkea entero)
VSCODE_SRC="${CONFIG_SRC}/vscode/User"
VSCODE_DST="${HOME}/.config/Code/User"

LINKED=0; SKIPPED=0; BACKED=0

# link_path <src> <dst> <clobber:true|false>
link_path() {
    local src="$1" dst="$2" clobber="${3:-true}"
    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        warn "origen no existe: $src"
        SKIPPED=$((SKIPPED+1)); return
    fi
    if [ -L "$dst" ]; then
        if [ "$(readlink "$dst")" = "$src" ]; then
            ok "$dst"; return
        fi
        $DRY && { info "(dry) repoint $dst -> $src"; LINKED=$((LINKED+1)); return; }
        rm -f "$dst"; ln -s "$src" "$dst"
        ok "reapuntado $dst"; LINKED=$((LINKED+1)); return
    fi
    if [ -e "$dst" ]; then
        if [ "$clobber" = true ]; then
            local bak="${dst}.pre-dotfiles.$(date +%Y%m%d%H%M%S)"
            $DRY && { info "(dry) backup $dst -> $bak + symlink"; BACKED=$((BACKED+1)); return; }
            mv "$dst" "$bak"; ln -s "$src" "$dst"
            warn "backup $dst -> $(basename "$bak"); symlink creado"; LINKED=$((LINKED+1)); BACKED=$((BACKED+1)); return
        fi
        warn "existe y no es symlink, no toco: $dst"
        SKIPPED=$((SKIPPED+1)); return
    fi
    $DRY && { info "(dry) crear $dst -> $src"; LINKED=$((LINKED+1)); return; }
    ln -s "$src" "$dst"
    ok "creado $dst"; LINKED=$((LINKED+1))
}

[ -d "$REPO/linux" ] || { err "No existe $REPO/linux — clona el repo primero."; exit 1; }

header "machine-type"
if [ ! -f "${HOME}/.config/machine-type" ]; then
    if [ -x "${REPO}/scripts/detect-machine.sh" ]; then
        mt="$(bash "${REPO}/scripts/detect-machine.sh")"
        [ -d "${HOME}/.config" ] || mkdir -p "${HOME}/.config"
        $DRY || echo "$mt" > "${HOME}/.config/machine-type"
        ok "machine-type = $mt"
    else
        warn "falta detect-machine.sh — no puedo escribir machine-type"
    fi
else
    ok "machine-type = $(cat "${HOME}/.config/machine-type")"
fi
MACHINE="$(cat "${HOME}/.config/machine-type" 2>/dev/null || echo desktop)"

mkdir -p "${HOME}/.config" "${HOME}/.local/bin"

header "Config dirs (~/.config)"
for name in "${CONFIG_DIRS[@]}"; do
    link_path "${CONFIG_SRC}/${name}" "${HOME}/.config/${name}" true
done

header "Config files (~/.config)"
for name in "${CONFIG_FILES[@]}"; do
    link_path "${CONFIG_SRC}/${name}" "${HOME}/.config/${name}" true
done

header "Home files"
for name in "${HOME_FILES[@]}"; do
    link_path "${HOME_SRC}/${name}" "${HOME}/${name}" true
done

header "VS Code User (~/.config/Code/User)"
if [ -d "$VSCODE_SRC" ]; then
    mkdir -p "$VSCODE_DST"
    for f in "$VSCODE_SRC"/*.json; do
        [ -e "$f" ] || continue
        link_path "$f" "${VSCODE_DST}/$(basename "$f")" true
    done
else
    warn "no existe $VSCODE_SRC"
fi

header "Scripts (~/.local/bin)"
if [ -d "$BIN_SRC" ]; then
    for f in "$BIN_SRC"/*; do
        [ -e "$f" ] || continue
        link_path "$f" "${HOME}/.local/bin/$(basename "$f")" false
    done
fi

header "Copias (no symlink)"
for name in "${COPY_DIRS[@]}"; do
    src="${CONFIG_SRC}/${name}"
    dst="${HOME}/.config/${name}"
    [ -d "$src" ] || { warn "origen no existe: $src"; continue; }
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        $DRY || cp -ru "$src/." "$dst/"
        ok "$dst (copiado)"
    else
        $DRY && { info "(dry) copiar $src -> $dst"; continue; }
        rm -rf "$dst"; mkdir -p "$dst"; cp -r "$src/." "$dst/"
        ok "creado $dst (copiado)"
    fi
done

header "lan-mouse (machine: $MACHINE)"
if [ -f "${LANMOUSE_SRC}/config.${MACHINE}.toml" ]; then
    mkdir -p "${HOME}/.config/lan-mouse"
    if [ -f "${LANMOUSE_SRC}/lan-mouse.pem" ] && [ ! -f "${HOME}/.config/lan-mouse/lan-mouse.pem" ]; then
        $DRY || cp -n "${LANMOUSE_SRC}/lan-mouse.pem" "${HOME}/.config/lan-mouse/" 2>/dev/null || true
    fi
    if [ ! -f "${HOME}/.config/lan-mouse/config.toml" ] || ! $DRY; then
        $DRY || cp "${LANMOUSE_SRC}/config.${MACHINE}.toml" "${HOME}/.config/lan-mouse/config.toml"
        ok "~/.config/lan-mouse/config.toml (desde config.${MACHINE}.toml)"
    else
        ok "~/.config/lan-mouse/config.toml (ya existe)"
    fi
else
    warn "no existe ${LANMOUSE_SRC}/config.${MACHINE}.toml"
fi

header "Resumen"
echo "  symlinks aplicados: $LINKED"
echo "  backups creados:    $BACKED"
echo "  omitidos:           $SKIPPED"
$DRY && echo "  (modo --dry: nada se modifico)"
echo ""

# ── Verificacion: symlinks rotos que apunten al repo ───────────
header "Verificacion"
broken=0
while IFS= read -r l; do
    tgt="$(readlink "$l")"
    case "$tgt" in
        "$HOME/dotfiles"/*) err "symlink roto: $l -> $tgt"; broken=$((broken+1)) ;;
    esac
done < <(find "${HOME}/.config" "${HOME}/.local/bin" "${HOME}/.config/Code/User" -maxdepth 1 -xtype l 2>/dev/null)
[ "$broken" -eq 0 ] && ok "Sin symlinks rotos hacia el repo." || err "$broken symlink(s) roto(s)."
exit 0
