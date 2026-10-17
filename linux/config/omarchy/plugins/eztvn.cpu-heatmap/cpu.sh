#!/bin/bash
# Sonda de uso por núcleo para eztvn.cpu-heatmap.
# Muestrea /proc/stat dos veces (separadas unos 200 ms) y calcula el uso de
# cada CPU lógica a partir del delta. Imprime exactamente una línea JSON:
#   {"count":24,"cores":[3,12,45,...]}
# Cada valor es un porcentaje entero 0..100.
LC_ALL=C

snapshot() {
  awk '/^cpu[0-9]+ / {
    total = $2+$3+$4+$5+$6+$7+$8+$9+$10+$11
    idle  = $5+$6
    print total, idle
  }' /proc/stat
}

mapfile -t first < <(snapshot)
sleep 0.2
mapfile -t second < <(snapshot)

n=${#first[@]}
if (( n == 0 )); then
  printf '{"count":0,"cores":[]}\n'
  exit 0
fi

out=""
for ((i = 0; i < n; i++)); do
  read -r ta ia <<<"${first[i]}"
  read -r tb ib <<<"${second[i]}"
  dt=$((tb - ta))
  di=$((ib - ia))
  if (( dt > 0 )); then
    p=$(( (dt - di) * 100 / dt ))
    (( p < 0 )) && p=0
    (( p > 100 )) && p=100
  else
    p=0
  fi
  if (( i > 0 )); then out+=","; fi
  out+="$p"
done

printf '{"count":%d,"cores":[%s]}\n' "$n" "$out"
