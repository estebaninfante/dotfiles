#!/usr/bin/env bash
# verificar-animaciones.sh — auditor determinista de animaciones QML.
#
# Uso:  ./verificar-animaciones.sh [carpeta-o-archivo]   (default: .)
#
# No juzga si la animación es linda: detecta los errores que sí se pueden
# comprobar sin mirar la pantalla.
#
#   - Duración literal en un archivo que usa el motor (debería usar
#     Tokens.fast / base / morph). El verificador canónico del motor es
#     ~/dotfiles/scripts/verify/motion.sh.
#   - Behavior + Transition/NumberAnimation sobre la MISMA propiedad (doble
#     animación: el tiempo se duplica o se pelean).
#   - Behavior sobre width/height/implicit* (relayout: solo válido en un morph
#     de contenedor explícito).
#   - Bucles infinitos sin `running:` (siguen gastando GPU con el ítem oculto).
#   - Duraciones > 340 ms en UI (se sienten lentas).
#
# Sale 0 si no hay errores; 1 si hay al menos uno. Los avisos no fallan.
set -uo pipefail

objetivo="${1:-.}"
if [ ! -e "$objetivo" ]; then
  echo "No existe: $objetivo" >&2
  exit 2
fi
if [ -d "$objetivo" ]; then
  archivos="$(find "$objetivo" -name '*.qml' -not -path '*/node_modules/*' | sort)"
else
  archivos="$objetivo"
fi
if [ -z "$archivos" ]; then
  echo "Sin archivos .qml en $objetivo"
  exit 0
fi

errores=0
avisos=0

error() { errores=$((errores + 1)); printf '  ✗ %s\n' "$1"; }
aviso() { avisos=$((avisos + 1)); printf '  ! %s\n' "$1"; }

contar_lineas() { # archivo patrón extendido
  grep -E -c "$2" "$1" 2>/dev/null || true
}

for f in $archivos; do
  problemas=""

  # --- 1. Doble animación sobre la misma propiedad -------------------------
  beh="$(grep -oE 'Behavior on [A-Za-z_.]+' "$f" 2>/dev/null | awk '{print $3}' | sort -u)"
  if [ -n "$beh" ]; then
    anim="$(grep -oE '(properties|property):[[:space:]]*"[^"]+"' "$f" 2>/dev/null \
      | sed -E 's/^[^"]*"//; s/"$//' | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sort -u)"
    for p in $beh; do
      if printf '%s\n' "$anim" | grep -qx -- "$p"; then
        problemas="${problemas}Doble animación en '$p' (Behavior + animation en el mismo archivo).\n"
      fi
    done
  fi

  # --- 2. Behavior sobre layout -------------------------------------------
  layout="$(grep -oE 'Behavior on (width|height|implicitWidth|implicitHeight|contentHeight|contentWidth)' "$f" 2>/dev/null | sort -u)"
  if [ -n "$layout" ]; then
    while IFS= read -r linea; do
      [ -n "$linea" ] || continue
      aviso "$f: ${linea#Behavior on } anima layout; confirmá que es un morph de contenedor y no un gesto chico."
    done <<EOF
$layout
EOF
  fi

  # --- 3. Bucles infinitos sin guard --------------------------------------
  if [ "$(contar_lineas "$f" 'loops:[[:space:]]*Animation\.Infinite')" -gt 0 ] \
     && [ "$(contar_lineas "$f" 'running:')" -eq 0 ]; then
    problemas="${problemas}Bucle infinito sin 'running:' (sigue animando aunque el ítem esté oculto).\n"
  fi

  # --- 4. Duraciones largas ------------------------------------------------
  # Las líneas marcadas con `// pulso` son latidos a propósito (no transiciones
  # de UI) y quedan exentas.
  largas="$(grep -nE 'duration:[[:space:]]*(3[5-9][0-9]|[4-9][0-9]{2}|[0-9]{4,})' "$f" 2>/dev/null | grep -v '// pulso')"
  if [ -n "$largas" ]; then
    while IFS= read -r linea; do
      [ -n "$linea" ] || continue
      aviso "$f:${linea%%:*} duración larga (>340 ms): ${linea#*: }"
    done <<EOF
$largas
EOF
  fi

  # --- 5. Duraciones literales conviviendo con Motion ----------------------
  if grep -qE 'Tokens\.|import "motion"|Motion[[:space:]]*\{' "$f" 2>/dev/null; then
    literales="$(grep -nE 'duration:[[:space:]]*[0-9]+' "$f" 2>/dev/null | grep -v '// pulso')"
    if [ -n "$literales" ]; then
      while IFS= read -r linea; do
        [ -n "$linea" ] || continue
        problemas="${problemas}Duración literal con el motor disponible (${linea#*: }). Usá Tokens.\n"
      done <<EOF
$literales
EOF
    fi
  fi

  if [ -n "$problemas" ]; then
    printf '%s\n' "$f"
    printf '%b' "$problemas"
  fi
done

echo
if [ "$errores" -gt 0 ]; then
  echo "Animaciones: $errores error(es), $avisos aviso(s)."
  exit 1
fi
echo "Animaciones: sin errores, $avisos aviso(s)."
exit 0
