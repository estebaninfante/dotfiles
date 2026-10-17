#!/bin/bash
# Sonda de uso por núcleo para eztvn.cpu-heatmap.
#
# Antes muestreaba /proc/stat dos veces con `sleep 0.2` en medio: cada refresco
# costaba ~207 ms de reloj, o sea ~21 % de un núcleo todo el tiempo, sólo
# durmiendo (medido 2026-10-17). Ahora no duerme: compara contra el snapshot
# anterior guardado en $XDG_RUNTIME_DIR y calcula el uso en ese intervalo.
#
# Imprime exactamente una línea JSON:
#   {"count":16,"cores":[3,12,45,...]}
# Cada valor es un porcentaje entero 0..100. La primera invocación (sin estado
# previo) devuelve count 0 y el widget muestra "CPU calentando…".
LC_ALL=C

STATE="${XDG_RUNTIME_DIR:-/tmp}/omarchy-cpu-heatmap.state"

snapshot() {
  awk '/^cpu[0-9]+ / {
    printf "%d %d\n", $2+$3+$4+$5+$6+$7+$8+$9+$10+$11, $5+$6
  }' /proc/stat
}

cur="$(snapshot)"
prev="$(cat "$STATE" 2>/dev/null || true)"
printf '%s\n' "$cur" >"$STATE" 2>/dev/null || true

if [ -z "$prev" ] || [ -z "$cur" ]; then
  printf '{"count":0,"cores":[]}\n'
  exit 0
fi

printf '%s\n===\n%s\n' "$prev" "$cur" | awk '
  /^===$/ { mode = 1; next }
  {
    if (mode == 0) { pt[++np] = $1; pi[np] = $2 }
    else           { ct[++nc] = $1; ci[nc] = $2 }
  }
  END {
    if (nc == 0) { print "{\"count\":0,\"cores\":[]}"; exit }
    out = ""
    for (i = 1; i <= nc; i++) {
      p = 0
      if (i <= np && ct[i] > pt[i]) {
        dt = ct[i] - pt[i]
        di = ci[i] - pi[i]
        p = int((dt - di) * 100 / dt)
        if (p < 0) p = 0
        if (p > 100) p = 100
      }
      out = out (i > 1 ? "," : "") p
    }
    printf "{\"count\":%d,\"cores\":[%s]}\n", nc, out
  }'
