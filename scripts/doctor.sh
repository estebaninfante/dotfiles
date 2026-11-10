#!/usr/bin/env bash
# doctor.sh — chequeo de sanidad del filesystem del usuario y de los dotfiles.
#
# Es el "test suite" que evita volver al caos: si algo se desordena (una raíz
# de proyectos duplicada, un backup suelto, un worktree huérfano, un symlink
# roto, un binario shadoweado), esto lo dice.
#
# Uso:  doctor.sh [--quiet]     --quiet: solo problemas
# Sale 0 si está todo bien, 1 si hay al menos un problema.
set -uo pipefail

REPO="${HOME}/dotfiles"
DEV_ROOT="${DEV_ROOT:-$HOME/Proyectos}"
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

FAILED=0; WARNED=0
ok()   { [[ "$QUIET" == 1 ]] || printf '  ok    %s\n' "$*"; }
bad()  { printf '  FALLA %s\n' "$*"; FAILED=$((FAILED+1)); }
warn() { printf '  ojo   %s\n' "$*"; WARNED=$((WARNED+1)); }
head_() { [[ "$QUIET" == 1 ]] || printf '\n%s\n' "$*"; }

# Directorios permitidos en $HOME (todos los demás son sospechosos).
HOME_DIRS_OK=( Archivo Descargas Documentos Escritorio "Imágenes" "Música" Proyectos
               Videos alicia ai-chats books dotfiles go _basura )

head_ "── raíces ──"
[[ -d "$DEV_ROOT" ]] && ok "raíz de proyectos: $DEV_ROOT" || bad "no existe $DEV_ROOT"
# Una sola raíz de código: viejas raíces que hayan vuelto a aparecer.
for viejo in developing Projects proyectos dev Work; do
    [[ -e "$HOME/$viejo" ]] && warn "$HOME/$viejo existe (¿raíz duplicada? la única es $DEV_ROOT)"
done
[[ -e "$HOME/usr" || -e "$HOME/etc" || -e "$HOME/var" ]] && \
    bad "pseudo-root de Arch en \$HOME: sudo rm -rf ~/usr ~/etc ~/var ~/hooks ~/kernel"
[[ -e "$HOME/bin" ]] && warn "\$HOME/bin existe (shadowea /usr/bin si está en PATH)"

head_ "── symlinks ──"
while IFS= read -r l; do
    [[ -e "$l" ]] || bad "symlink roto: ${l#$HOME/} -> $(readlink "$l")"
done < <(find "$HOME/.config" -maxdepth 1 -type l 2>/dev/null)

head_ "── backups fuera de lugar ──"
suelto=$(
    find "$HOME" -maxdepth 1 \( -name '*.pre-dotfiles.*' -o -name '*.bak.[0-9]*' \
        -o -name 'mise.real.*' -o -name '.bash_history-*.tmp' \) -print 2>/dev/null
    find "$HOME/.config" -mindepth 1 -maxdepth 3 \( -name '*.pre-dotfiles.*' -o -name '*.bak.[0-9]*' \) -print 2>/dev/null
)
if [[ -n "$suelto" ]]; then
    printf '%s\n' "$suelto" | while read -r f; do bad "backup suelto: ${f#$HOME/}"; done
else
    ok "sin backups sueltos (los backups viven en ~/.local/state/dotfiles-backups)"
fi

head_ "── user-dirs ──"
tmpl="$REPO/linux/config/user-dirs.dirs.template"
live="$HOME/.config/user-dirs.dirs"
if [[ -f "$tmpl" ]]; then
    if [[ -L "$live" ]]; then
        bad "~/.config/user-dirs.dirs es un symlink (debe generarse, no enlazarse)"
    elif cmp -s "$tmpl" "$live"; then
        ok "user-dirs.dirs == plantilla"
    else
        warn "user-dirs.dirs difiere de la plantilla (correr link-dotfiles.sh)"
    fi
fi

head_ "── PATH ──"
case ":$PATH:" in
    *":$HOME/bin:"*|*":$HOME/usr/bin:"*) bad "PATH contiene una raíz del home que shadowea /usr/bin" ;;
    *) ok "PATH sin raíces del home" ;;
esac

head_ "── proyectos duplicados ──"
if [[ -d "$DEV_ROOT" ]]; then
    dupes=$(for g in $(find "$DEV_ROOT" -maxdepth 3 -name .git -type d -not -path '*/_archivo/*' 2>/dev/null); do
                r=$(git -C "$(dirname "$g")" remote get-url origin 2>/dev/null) && echo "$r"
            done | sort | uniq -d)
    if [[ -n "$dupes" ]]; then
        printf '%s\n' "$dupes" | while read -r r; do warn "más de un checkout de $r"; done
    else
        ok "un checkout por origin"
    fi
fi

head_ "── worktrees ──"
TICKETS="$HOME/.config/opencode/tickets.json"
huerfanos=0; huerf_tam=0
for base in "$DEV_ROOT/.rig-worktrees" "$HOME/.rig-worktrees"; do
    [[ -d "$base" ]] || continue
    while IFS= read -r w; do
        huerfanos=$((huerfanos+1))
        huerf_tam=$((huerf_tam + $(du -sm "$w" 2>/dev/null | cut -f1)))
    done < <(for owner in "$base"/*/; do for w in "$owner"*/; do
                [[ -d "$w" ]] || continue
                if [[ -f "$TICKETS" ]] && grep -q "\"$(basename "$w")\"" "$TICKETS" 2>/dev/null; then
                    continue
                fi
                echo "$w"
             done; done)
done
if (( huerfanos > 0 )); then
    warn "$huerfanos worktree(s) sin ticket abierto (~${huerf_tam} MB): rig ticket done / worktree cerrar"
else
    ok "sin worktrees huérfanos"
fi

head_ "── basura ──"
found=0
for pat in "*.part" "*.crdownload"; do
    while IFS= read -r f; do
        [[ -s "$f" ]] || continue
        warn "descarga interrumpida: ${f#$HOME/} ($(du -h "$f" | cut -f1))"; found=1
    done < <(find "$HOME/Descargas" -maxdepth 1 -name "$pat" 2>/dev/null)
done
while IFS= read -r f; do warn "archivo suelto en \$HOME: ${f#$HOME/}"; found=1; done \
    < <(find "$HOME" -maxdepth 1 -type f \( -name '*.log' -o -name '*.png' -o -name '*.jpg' \) 2>/dev/null)
(( found )) || ok "sin basura evidente en Descargas/\$HOME"

head_ "── carpetas fuera de lugar ──"
for d in "$HOME"/*/; do
    name="$(basename "$d")"
    [[ " ${HOME_DIRS_OK[*]} " == *" $name "* ]] || warn "carpeta inesperada en \$HOME: $name"
done
ok "revisión de \$HOME completa"

head_ "── espacio ──"
df -h / | awk 'NR==2 {printf "  %s usado de %s (%s libre)\n", $3, $2, $4}'

printf '\n'
if (( FAILED > 0 )); then
    printf '%d problema(s), %d aviso(s)\n' "$FAILED" "$WARNED"; exit 1
fi
printf 'sin problemas (%d aviso(s))\n' "$WARNED"; exit 0
