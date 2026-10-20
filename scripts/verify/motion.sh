#!/usr/bin/env bash
# Verificador del motor de movimiento.
#
#   scripts/verify/motion.sh [carpeta ...]
#
# Sin argumentos revisa bar/modules y plugins (los consumidores reales).
# Comprueba:
#   1. motion.json válido y con los tokens que el motor usa.
#   2. Las copias vendorizadas (plugins/*/motion, bar/modules/motion) son
#      idénticas a la fuente ~/.config/omarchy/motion.
#   3. Lint de consumidores: duraciones literales, Math.random en animación,
#      `visible: false` a mano, animar width/height, latidos sin guard.
#   4. Test determinista de la línea de tiempo (Morph.advance, sin render).
#
# Sale 1 si hay errores. Los avisos no fallan.
set -uo pipefail

HOME_DIR="${HOME}"
ENGINE="$HOME_DIR/.config/omarchy/motion"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
err=0 warn=0
E() { echo "ERROR $*"; err=$((err + 1)); }
W() { echo "aviso $*"; warn=$((warn + 1)); }

# 1. tokens -----------------------------------------------------------------
if [[ ! -f "$ENGINE/motion.json" ]]; then
  E "falta $ENGINE/motion.json"
else
  if command -v jq >/dev/null; then
    for key in instant fast base morph slow draw; do
      jq -e ".duration.$key | numbers" "$ENGINE/motion.json" >/dev/null 2>&1 \
        || E "motion.json: falta duration.$key"
    done
    for key in step stepMorph max; do
      jq -e ".stagger.$key | numbers" "$ENGINE/motion.json" >/dev/null 2>&1 \
        || E "motion.json: falta stagger.$key"
    done
    for key in standard enter exit move spring draw; do
      jq -e ".curve.$key | strings" "$ENGINE/motion.json" >/dev/null 2>&1 \
        || E "motion.json: falta curve.$key"
    done
  else
    W "sin jq: no se validó motion.json"
  fi
fi

# 2. copias vendorizadas ----------------------------------------------------
if [[ -d "$ENGINE" ]]; then
  while IFS= read -r dst; do
    for f in motion.json qmldir Tokens.qml Reveal.qml Morph.qml Frames.qml Motion.js; do
      [[ -f "$dst/$f" ]] || { E "copia incompleta: ${dst#$HOME_DIR/}/$f"; continue; }
      cmp -s "$ENGINE/$f" "$dst/$f" || E "copia desviada: ${dst#$HOME_DIR/}/$f (corré scripts/motion-vendor.sh)"
    done
  done < <(find "$HOME_DIR/.config/omarchy" -maxdepth 3 -type d -name motion \
             ! -path "$ENGINE" 2>/dev/null)
fi

# 3. consumidores -----------------------------------------------------------
roots=("$@")
if [[ ${#roots[@]} -eq 0 ]]; then
  roots=("$HOME_DIR/.config/omarchy/bar/modules" "$HOME_DIR/.config/omarchy/plugins")
fi

files=()
for r in "${roots[@]}"; do
  [[ -e "$r" ]] || continue
  while IFS= read -r f; do files+=("$f"); done < <(
    find "$r" -name '*.qml' \
      ! -path '*/motion/*' ! -name 'Tokens.qml' ! -name 'Reveal.qml' \
      ! -name 'Morph.qml' ! -name 'Frames.qml' 2>/dev/null)
done

backlog=0
for f in "${files[@]}"; do
  rel="${f#$HOME_DIR/}"
  # El motor se adopta de a uno. En los archivos que todavía no lo usan, el
  # lint estricto sería ruido: se cuentan como backlog y no se revisan.
  if ! grep -qE 'import "motion"|Tokens\.' "$f" 2>/dev/null; then
    backlog=$((backlog + 1))
    continue
  fi

  # Duración literal: 120, 260… salvo 0 (apagado) y las que salen de Tokens.
  while IFS= read -r l; do
    n=${l%%:*}
    # `property int duration: 1200` no es una animación: es un tiempo de vida.
    # Se pide renombrarlo para que el verificador no lo confunda con movimiento.
    if grep -qE 'property [a-z]+ duration:' <<<"$l"; then
      W "$rel:$n 'duration' como tiempo de vida, no de animación; renombralo (visibleFor/holdFor)"
      continue
    fi
    v=$(grep -oE 'duration:[[:space:]]*[0-9]+' <<<"$l" | grep -oE '[0-9]+' | head -1)
    if (( ${v:-0} <= 140 )); then sug=fast
    elif (( ${v:-0} <= 220 )); then sug=base
    elif (( ${v:-0} <= 300 )); then sug=morph
    else sug=slow; fi
    if (( ${v:-0} <= 140 )); then sug="fast (o Tokens.hover si es hover/presión)"
    elif (( ${v:-0} <= 220 )); then sug="base (o Tokens.state)"
    elif (( ${v:-0} <= 300 )); then sug="morph (o Tokens.page)"
    else sug="slow (o Tokens.surface)"; fi
    E "$rel:$n duración literal ($v); sugerido: Tokens.$sug"
  done < <(grep -nE 'duration:[[:space:]]*[1-9][0-9]*([[:space:]]*[,}]|$)' "$f" 2>/dev/null)

  # Azar sin semilla en código de dibujo/animación.
  while IFS= read -r l; do
    n=${l%%:*}
    E "$rel:$n Math.random() en animación; sembrá con hashStr()+rng()"
  done < <(grep -n 'Math\.random(' "$f" 2>/dev/null)

  # Cortes: `visible: false` a mano en vez de entrar/salir pareado.
  while IFS= read -r l; do
    n=${l%%:*}
    W "$rel:$n visible: false literal; usá Reveal (entra/sale) o un estado pareado"
  done < <(grep -nE 'visible:[[:space:]]*false' "$f" 2>/dev/null)

  # Animar tamaño: reasigna layout/backing image por frame.
  while IFS= read -r l; do
    n=${l%%:*}
    W "$rel:$n Behavior sobre width/height; animá x/y/scale o usá un morph de contenedor"
  done < <(grep -nE 'Behavior on (width|height)' "$f" 2>/dev/null)

  # Latido infinito sin guarda.
  if grep -q 'Animation.Infinite' "$f" && ! grep -qE 'running:' "$f"; then
    W "$rel:1 Animation.Infinite sin running: puede quedar latiendo oculto"
  fi
done

# 4. línea de tiempo --------------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed "s|@ENGINE@|$ENGINE|g" "$REPO/scripts/verify/motion-timeline.qml" > "$tmp/test.qml"
mkdir -p "$tmp/run" && chmod 700 "$tmp/run"
out="$(QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$tmp/run" timeout 60 \
        qs -p "$tmp/test.qml" --no-color 2>&1)"
if grep -q 'MOTION_TEST_OK' <<<"$out"; then
  echo "ok línea de tiempo"
else
  E "test de línea de tiempo: $(grep -E 'FAIL|ERROR|caused' <<<"$out" | head -3 | tr '\n' ' ')"
fi

echo "--- ${#files[@]} consumidores ($backlog sin migrar), $err errores, $warn avisos"
[[ $err -eq 0 ]]
