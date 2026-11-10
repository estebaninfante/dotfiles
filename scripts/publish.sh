#!/usr/bin/env bash
# publish.sh — ÚNICO lugar que escribe en el repo dotfiles (commit + push).
#
#   publish.sh                      flujo humano: export omarchy -> commit -> push (pregunta)
#   publish.sh --yes                igual, sin preguntar (lo usa la skill dotfiles-publish)
#   publish.sh commit [--mensaje T] solo git add -A + commit (lo llama dotfiles-sync.sh)
#   publish.sh push                 solo git push con reintento HTTP/1.1 (idem)
#
# Ningún otro script corre `git add`, `git commit` ni `git push` sobre este repo:
# dotfiles-sync.sh orquesta (cuándo, con qué reintentos) y llama acá.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
CMD="publish"
MENSAJE=""
YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        commit|push) CMD="$1"; shift ;;
        --mensaje)   MENSAJE="${2:?falta el mensaje}"; shift 2 ;;
        --yes|-y)    YES=1; shift ;;
        -h|--help)   sed -n '2,8p' "$0"; exit 0 ;;
        *)           echo "argumento desconocido: $1" >&2; exit 2 ;;
    esac
done

cd "$DOTFILES" || { echo "  [ERROR] no existe $DOTFILES" >&2; exit 1; }
git rev-parse --is-inside-work-tree &>/dev/null || {
    echo "  [ERROR] $DOTFILES no es un repositorio Git." >&2; exit 1
}

hay_cambios() {
    ! git diff --quiet || ! git diff --cached --quiet \
        || [[ -n "$(git ls-files --others --exclude-standard)" ]]
}

commit_all() {
    if ! hay_cambios; then echo "  Nada que commitear."; return 0; fi
    git add -A
    git commit -m "${MENSAJE:-dotfiles: $(date '+%Y-%m-%d %H:%M:%S')}"
    echo "  Commit: $(git log -1 --oneline)"
}

# El HTTP/2 de esta red se cae solo ("Error in the HTTP2 framing layer"); un
# reintento por HTTP/1.1 lo resuelve sin despertar a ningún agente.
push_remote() {
    local branch err
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if ! git remote | grep -q .; then
        echo "  No hay remoto configurado. Solo commit local."
        return 0
    fi
    if err=$(git push origin "$branch" 2>&1); then
        [[ -z "$err" ]] || printf '%s\n' "$err"
        echo "  Push OK ($branch)."
        return 0
    fi
    printf '%s\n' "$err" >&2
    echo "  Reintento con HTTP/1.1..." >&2
    if err=$(git -c http.version=HTTP/1.1 push origin "$branch" 2>&1); then
        echo "  Push OK ($branch, HTTP/1.1)."
        return 0
    fi
    printf '%s\n' "$err" >&2
    return 1
}

case "$CMD" in
    commit) commit_all ;;
    push)   push_remote ;;
    publish)
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║  dotfiles publish.sh                   ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        if [[ -x "$DOTFILES/scripts/omarchy-sync.sh" ]]; then
            echo "  ── Exportando config de Omarchy (~/.config/omarchy -> repo)..."
            "$DOTFILES/scripts/omarchy-sync.sh" export || echo "  [WARN] export Omarchy fallo (sigo)"
            echo ""
        fi
        if ! hay_cambios; then
            echo "  No hay cambios que publicar."
            exit 0
        fi
        echo "  git status:"; echo ""; git status; echo ""
        commit_all
        echo ""
        if [[ "$YES" == 1 ]]; then
            push_remote
        elif git remote -v | grep -q .; then
            git remote -v
            read -r -p "  Ejecutar git push? [y/N] " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then push_remote; else echo "  Push omitido."; fi
        else
            echo "  No hay remoto configurado. Solo commit local."
        fi
        echo "  Hecho."
        ;;
esac
