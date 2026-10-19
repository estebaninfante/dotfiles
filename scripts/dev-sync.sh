#!/usr/bin/env bash
# dev-sync.sh — mantiene los proyectos de desarrollo iguales en laptop y desktop.
#
# Modos:
#   dev-sync.sh                 (default) MIEDE: no escribe nada. Dice qué
#                               cambiaría en cada repo y cuánto tarda.
#   dev-sync.sh --sync          commitea el WIP, rebasea contra el remoto y
#                               pushea. Al final imprime el resumen medido.
#   dev-sync.sh --auto          como --sync pero sólo si está enchufado a la
#                               corriente Y en el wifi de casa (lo usa el timer).
#   dev-sync.sh --publicar      da de alta el repo privado en GitHub si falta
#                               (cuenta propia), le pone origin y sube todo.
#   dev-sync.sh --apps          converge aplicaciones con la otra máquina
#                               (mide por defecto; --aplicar instala/actualiza).
#   dev-sync.sh --paquetes      sólo lista las diferencias de paquetes.
#
# Regla del proyecto: todo repo de desarrollo vive en un repo PRIVADO de
# GitHub de la cuenta propia, y los agentes trabajan contra ese origin para
# que cualquier máquina pueda seguir. `--sync` crea el repo si no existe.
#
# Seguridad (por qué no es un simple `git add -A && push`):
#   - Antes de tocar nada deja un ref `refs/devsync/<host>/<fecha>` apuntando al
#     HEAD, para poder volver atrás.
#   - Si hay una operación de git a medias (rebase/merge/index.lock) saltea el
#     repo: puede haber un agente trabajando ahí.
#   - Si el pull --rebase falla, aborta y deja el repo como estaba: NO resuelve
#     conflictos solo. Queda anotado en el log y en el resumen.
#   - Nunca hace `git clean`: lo que no está versionado y está ignorado
#     (node_modules, .venv, builds) no se toca ni se sincroniza.
#
# Variables: DEV_SYNC_ROOTS (raíces a recorrer), DEV_SYNC_PEER (máquina par).
set -uo pipefail
# ~/bin tapa ps/grep/sed/awk con busybox: usar los del sistema.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOTS="${DEV_SYNC_ROOTS:-$HOME/developing $HOME/proyectos}"
PEER="${DEV_SYNC_PEER:-desktop-lan}"
CUENTA="${DEV_SYNC_CUENTA:-estebaninfante}"
HOST="$(hostname -s 2>/dev/null || hostname)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG="$STATE/dev-sync.log"
mkdir -p "$STATE"

MODO="medir"
FILTRO=""
AUTO=0
case "${1:-}" in
  ""|--medir|--dry-run) MODO="medir" ;;
  --sync)               MODO="sync" ;;
  --auto)               MODO="sync"; AUTO=1 ;;
  --publicar)           MODO="publicar" ;;
  --apps)               MODO="apps" ;;
  --paquetes)           MODO="apps" ;;
  -h|--help)            sed -n '2,32p' "$0"; exit 0 ;;
  *) echo "dev-sync: modo desconocido: $1" >&2; exit 2 ;;
esac
[ $# -gt 1 ] && FILTRO="$2"   # dev-sync --publicar vision-hub
SSID="${DEV_SYNC_SSID:-Familia_Infante}"

# Sólo con corriente y en el wifi de casa (lo que pidió el usuario).
enchufado() { grep -qx 1 /sys/class/power_supply/*/online 2>/dev/null; }
en_casa() {
  local red
  red=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
        | awk -F: '$2=="802-11-wireless"{print $1; exit}')
  [ -n "$red" ] && printf '%s' "$red" | grep -qiE "$SSID"
}
saltar_por_entorno() {
  if ! enchufado; then log "auto: sin corriente, no sincronizo"; return 0; fi
  if ! en_casa; then log "auto: fuera del wifi de casa, no sincronizo"; return 0; fi
  return 1
}
if [ "$AUTO" = 1 ] && saltar_por_entorno; then exit 0; fi

log() { echo "$(date '+%F %T') [$MODO] $*" >>"$LOG"; }
ms()  { echo $(( $(date +%s%N) / 1000000 )); }

# ---------------------------------------------------------------- paquetes

if [ "$MODO" = "paquetes" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  pacman -Qe | awk '{print $1}' | sort >"$tmp/repo.local"
  pacman -Qm | awk '{print $1}' | sort >"$tmp/aur.local"
  if ! ssh -o ConnectTimeout=8 "$PEER" \
      'pacman -Qe | awk "{print \$1}" | sort; echo __AUR__; pacman -Qm | awk "{print \$1}" | sort' \
      >"$tmp/peer.raw" 2>"$tmp/peer.err"; then
    echo "no pude hablar con $PEER:"; cat "$tmp/peer.err"; exit 1
  fi
  sed -n '1,/__AUR__/p' "$tmp/peer.raw" | sed '$d' >"$tmp/repo.peer"
  sed -n '/__AUR__/,$p' "$tmp/peer.raw" | sed '1d' >"$tmp/aur.peer"
  echo "== esta máquina: $(wc -l <"$tmp/repo.local") de repo + $(wc -l <"$tmp/aur.local") AUR"
  echo "== $PEER:        $(wc -l <"$tmp/repo.peer") de repo + $(wc -l <"$tmp/aur.peer") AUR"
  lfaltan=$(comm -23 "$tmp/repo.local" "$tmp/repo.peer" | grep -v '^-' || true)
  pfaltan=$(comm -13 "$tmp/repo.local" "$tmp/repo.peer" | grep -v '^-' || true)
  alfalta=$(comm -23 "$tmp/aur.local" "$tmp/aur.peer" | grep -v '^-' || true)
  apfalta=$(comm -13 "$tmp/aur.local" "$tmp/aur.peer" | grep -v '^-' || true)
  echo; echo "== sólo acá (repo):";  [ -n "$lfaltan" ] && echo "$lfaltan" | tr '\n' ' ' && echo
  echo "== sólo en $PEER (repo):";   [ -n "$pfaltan" ] && echo "$pfaltan" | tr '\n' ' ' && echo
  echo "== sólo acá (AUR):";         [ -n "$alfalta" ] && echo "$alfalta" | tr '\n' ' ' && echo
  echo "== sólo en $PEER (AUR):";    [ -n "$apfalta" ] && echo "$apfalta" | tr '\n' ' ' && echo
  log "paquetes: acá $(wc -l <"$tmp/repo.local")+$(wc -l <"$tmp/aur.local"), $PEER $(wc -l <"$tmp/repo.peer")+$(wc -l <"$tmp/aur.peer")"
  exit 0
fi

# ------------------------------------------------------------------ repos

# ¿Hay un agente (pi/claude/codex/opencode) con su cwd dentro del repo?
# Si sí, NO se toca el árbol de trabajo: se commitea/pushea y se saltea el pull.
agente_en() {
  local repo="$1" p cwd cmd
  for p in /proc/[0-9]*; do
    cmd=$(tr '\0' ' ' <"$p/cmdline" 2>/dev/null) || continue
    case "$cmd" in
      *pi\ *|*/pi\ *|*claude*|*codex*|*opencode*) ;;
      *) continue ;;
    esac
    cwd=$(readlink "$p/cwd" 2>/dev/null) || continue
    case "$cwd" in "$repo"|"$repo"/*) return 0 ;; esac
  done
  return 1
}

en_curso() {  # true si hay una operación de git a medias en el repo
  local g="$1/.git"
  [ -e "$g/index.lock" ] && return 0
  [ -d "$g/rebase-merge" ] || [ -d "$g/rebase-apply" ] || [ -e "$g/MERGE_HEAD" ] \
    || [ -e "$g/CHERRY_PICK_HEAD" ] || [ -e "$g/BISECT_LOG" ] && return 0
  return 1
}

# Archivos que NO se suben ni con `add -A`: secretos de verdad (los .example sí).
secretos() {
  local repo="$1"
  (cd "$repo" && { git ls-files; git ls-files -o --exclude-standard; }) 2>/dev/null \
    | grep -Ei '(^|/)(\.env|\.env\.[^e].*|id_rsa|id_ed25519|.*\.(pem|key|p12|pfx|keystore)|credentials[^/]*)$' \
    | grep -v '\.example$' || true
}

asegurar_origin() {  # crea el repo privado en GitHub si falta y deja origin
  local repo="$1" nombre="$2"
  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi
  local url="https://github.com/$CUENTA/$nombre.git"
  if ! gh repo view "$CUENTA/$nombre" >/dev/null 2>&1; then
    gh repo create "$CUENTA/$nombre" --private \
      --description "$nombre (privado)" >/dev/null 2>&1 || {
        echo "  ! no pude crear $CUENTA/$nombre" >&2; return 1; }
  fi
  git -C "$repo" remote add origin "$url" 2>/dev/null || true
  echo "  + origin -> $url"
}

printf '\n%-22s %6s %6s %7s %8s %6s %6s %7s\n' REPO SUCIO NUEVOS WIP_KB A_PUSHEAR A_TRAER RAMA TIEMPO
total_ms=0
n_repos=0
errores=()

for root in $ROOTS; do
  [ -d "$root" ] || continue
  for repo in "$root"/*; do
    [ -d "$repo/.git" ] || continue
    nombre="$(basename "$repo")"
    [ -n "$FILTRO" ] && [ "$nombre" != "$FILTRO" ] && continue
    t0=$(ms)

    if en_curso "$repo"; then
      printf '%-22s %6s %s\n' "$nombre" "-" "SALTADO: operación de git en curso"
      log "$nombre: salteado (operación en curso)"; continue
    fi
    if ! git -C "$repo" rev-parse --verify -q HEAD >/dev/null; then
      printf '%-22s %6s %s\n' "$nombre" "-" "sin commits"; continue
    fi

    sucio=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)
    nuevos=$(git -C "$repo" ls-files -o --exclude-standard 2>/dev/null | wc -l)
    wip_kb=$(cd "$repo" && git ls-files -o --exclude-standard -z 2>/dev/null \
             | xargs -0 -r du -ck 2>/dev/null | tail -1 | cut -f1)
    wip_kb=${wip_kb:-0}
    rama=$(git -C "$repo" symbolic-ref --short -q HEAD || echo "detached")
    upstream=$(git -C "$repo" rev-parse --abbrev-ref -q '@{u}' 2>/dev/null || true)
    if [ -n "$upstream" ]; then
      a_pushear=$(git -C "$repo" rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)
      a_traer=$(git -C "$repo" rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)
    else
      a_pushear="-"; a_traer="-"
    fi

    if [ "$MODO" != "medir" ]; then
      # 0) secretos: si hay, no se commitea nada en este repo
      peligrosos=$(secretos "$repo")
      if [ -n "$peligrosos" ]; then
        errores+=("$nombre: posibles secretos, no se tocó ($(echo "$peligrosos" | head -3 | tr '\n' ' '))")
        log "$nombre: salteado por posibles secretos"
        continue
      fi
      # 0b) origin: sólo se pushea a la cuenta propia (nunca a un repo ajeno)
      origen=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
      if [ -n "$origen" ] && ! echo "$origen" | grep -q "github.com/$CUENTA/"; then
        errores+=("$nombre: origin ajeno ($origen), no se pushea")
        log "$nombre: origin ajeno, salteado"; continue
      fi
      # 0c) repo privado en GitHub (regla del proyecto)
      if [ "$MODO" = "publicar" ] || [ -z "$(git -C "$repo" remote get-url origin 2>/dev/null)" ]; then
        asegurar_origin "$repo" "$nombre" || { errores+=("$nombre: sin repo en GitHub"); continue; }
      fi
      # 1) ref de seguridad
      git -C "$repo" update-ref "refs/devsync/$HOST/$(date +%Y%m%d-%H%M%S)" HEAD 2>/dev/null
      # 2) WIP -> commit (lo que el usuario pidió: todo exacto, aunque esté a medias)
      if [ "$sucio" -gt 0 ]; then
        git -C "$repo" add -A 2>/dev/null
        if ! git -C "$repo" -c user.name="${GIT_AUTHOR_NAME:-$(id -un)}" \
              -c user.email="${GIT_AUTHOR_EMAIL:-$(id -un)@$HOST}" \
              commit -q -m "autosync($HOST): $(date '+%F %T') [dev-sync]" 2>>"$LOG"; then
          errores+=("$nombre: no pude commitear"); log "$nombre: commit falló"
        fi
      fi
      # 3) integrar y publicar (el pull CAMBIA archivos: no se hace si hay un
      #    agente trabajando en el repo, para no pisarle lo que está haciendo)
      if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
        saltar_pull=0
        agente_en "$repo" && saltar_pull=1
        # Con un repo recién creado el remoto está vacío: no hay nada que traer.
        if [ "$saltar_pull" = 0 ] && [ -n "$(git -C "$repo" ls-remote --heads origin 2>/dev/null)" ]; then
          if ! git -C "$repo" pull --rebase --autostash -q 2>>"$LOG"; then
            git -C "$repo" rebase --abort 2>/dev/null
            errores+=("$nombre: conflicto al rebase (revisar)")
            log "$nombre: pull --rebase falló; abortado"
            continue
          fi
        fi
        [ "$saltar_pull" = 1 ] && errores+=("$nombre: agente trabajando, no traje cambios")
        if ! git -C "$repo" push -q -u origin HEAD 2>>"$LOG"; then
          errores+=("$nombre: no pude pushear"); log "$nombre: push falló"
        fi
      else
        errores+=("$nombre: sin remoto (no hay por dónde viajar)")
      fi
    fi

    t=$(( $(ms) - t0 )); total_ms=$((total_ms + t)); n_repos=$((n_repos + 1))
    printf '%-22s %6s %6s %7s %8s %6s %6s %6sms\n' \
      "$nombre" "$sucio" "$nuevos" "$wip_kb" "$a_pushear" "$a_traer" "$rama" "$t"
  done
done

echo
echo "─── $n_repos repos en ${total_ms}ms ($(( total_ms / 1000 ))s) — $(date '+%F %T')"
if [ ${#errores[@]} -gt 0 ]; then
  echo "avisos:"
  printf '  ! %s\n' "${errores[@]}"
fi
[ "$MODO" = "medir" ] && echo "(medición: no se escribió nada; usá --sync o --publicar para aplicar)"
log "resumen: $n_repos repos, ${total_ms}ms, ${#errores[@]} avisos"
