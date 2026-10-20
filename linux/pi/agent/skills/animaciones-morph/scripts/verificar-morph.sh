#!/bin/bash
# Chequeos estáticos de un morph dibujado en Canvas (Quickshell/QML).
# Uso: verificar-morph.sh <carpeta o archivos .qml/.js>
# Sale 1 si hay errores. Los avisos no fallan la corrida.
set -uo pipefail

files=()
for arg in "$@"; do
  if [[ -d $arg ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$arg" -maxdepth 3 \( -name '*.qml' -o -name '*.js' \) ! -name '*.mjs')
  else
    files+=("$arg")
  fi
done
[[ ${#files[@]} -gt 0 ]] || { echo "nada que revisar"; exit 1; }

err=0 warn=0
E() { echo "ERROR $1:$2  $3"; err=$((err + 1)); }
W() { echo "aviso $1:$2  $3"; warn=$((warn + 1)); }
# Imprime "línea:texto" de las líneas que matchean, para un archivo.
hits() { grep -nE "$2" "$1" 2>/dev/null; }
in_block() { # archivo, desde, hasta, patrón: ¿el patrón aparece dentro del rango?
  awk -v a="$2" -v b="$3" -v p="$4" 'NR>=a && NR<=b && $0 ~ p {found=1} END{exit !found}' "$1"
}

for f in "${files[@]}"; do
  [[ -f $f ]] || { echo "no existe: $f"; err=$((err + 1)); continue; }

  # 1. Nada de azar sin semilla: la forma tiene que ser la misma en cada frame.
  while IFS= read -r l; do
    n=${l%%:*}; E "$f" "$n" "Math.random() en dibujo/animación: sembrá con hashStr()+rng() (assets/Puntos.js)"
  done < <(hits "$f" 'Math\.random\(')

  # 2. Texto en el canvas: no se puede seleccionar, no escala con el sistema y
  #    se pierde al cambiar de motor. El texto va en items QML.
  while IFS= read -r l; do
    n=${l%%:*}; W "$f" "$n" "fillText() en el canvas: mejor Text de QML posicionado (ver textPos)"
  done < <(hits "$f" 'fillText\(')

  # 3. Un paint no puede pedir otro paint: es un bucle que se come el frame.
  while IFS= read -r n; do
    [[ -n $n ]] && W "$f" "$n" "requestPaint() dentro de onPaint: pedilo desde un Timer/Frames"
  done < <(awk '
    /onPaint/ { depth = 0; inside = 1 }
    inside {
      o = gsub(/\{/, "{"); c = gsub(/\}/, "}")
      depth += o - c
      if (/requestPaint\(\)/) print NR
      if (depth <= 0 && o + c > 0) inside = 0
    }' "$f")

  # 4. Canvas cuyo tamaño se anima: cada frame reasigna la imagen de fondo.
  while IFS= read -r l; do
    n=${l%%:*}; E "$f" "$n" "Behavior sobre width/height de un Canvas: reasigna el backing image por frame"
  done < <(grep -nE 'Behavior on (width|height)' "$f" 2>/dev/null)

  # 5. Frames a mano: si hay FrameAnimation propio, tiene que compensar el
  #    frame que viene (+ms) y no retroceder. Con assets/Frames.qml esto sobra.
  if grep -q 'FrameAnimation' "$f" && ! grep -q 'frames\.tick\|Frames {' "$f"; then
    if ! grep -q 'frameTime' "$f"; then
      W "$f" 1 "FrameAnimation sin frameTime: el reloj no sigue al display; usá assets/Frames.qml"
    elif ! grep -q 'Math.max' "$f"; then
      W "$f" 1 "FrameAnimation sin Math.max(clock+ms, lastT): un frame largo hace retroceder el reloj"
    fi
  fi

  # 6. Pacing: un timer que repinta un canvas de morph a frecuencia fija no
  #    sincroniza con el display en 120/144 Hz.
  if grep -qE 'requestPaint' "$f" && grep -q 'interval: [0-9]' "$f" \
     && ! grep -qE 'Canvas\.Immediate|Frames \{|FrameAnimation' "$f"; then
    W "$f" 1 "repintado por Timer sin Frames: usá assets/Frames.qml para caer en los refrescos reales"
  fi

  # 7. Reduced motion: si hay morph en una vista, tiene que haber salida
  #    instantánea. (Las librerías de dibujo no manejan duraciones: se saltean.)
  if grep -qE 'NumberAnimation|duration:' "$f"; then
    if ! grep -qE 'animations-enabled|animation|motion|Motion|reduced|instant' "$f"; then
      W "$f" 1 "sin rastro de reduced motion: leé el interruptor y bajá las duraciones a 0"
    fi
  fi

  # 8. Asignar color/alfa por punto dentro del bucle de dibujo: agrupar por
  #    apariencia antes de dibujar (drawBeads ya lo hace).
  if grep -q 'fillStyle' "$f" && ! grep -q 'sameBead\|drawBeads' "$f"; then
    W "$f" 1 "fillStyle por punto: cambiarlo dentro del bucle duplica el costo; agrupá por apariencia"
  fi
done

echo "--- ${#files[@]} archivos, $err errores, $warn avisos"
[[ $err -eq 0 ]]
