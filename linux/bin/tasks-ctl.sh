#!/usr/bin/env bash
# tasks-ctl.sh — CRUD de tareas sobre la nota diaria del vault Obsidian
# Fuente de verdad: ~/alicia/Dia/YYYY-MM-DD.md (checkboxes "- [ ]"/"- [x]").
# La nota se crea desde la plantilla Mental/Plantillas/nota-dia.md si falta.
# Uso: tasks-ctl.sh {list|add <texto>|toggle <idx>|del <idx>|ensure|path}

set -euo pipefail

VAULT="$HOME/alicia"
DIA_DIR="$VAULT/Dia"
PLANTILLA="$VAULT/Mental/Plantillas/nota-dia.md"
HOY="$(date +%F)"
NOTA="$DIA_DIR/$HOY.md"

ensure_note() {
    [ -f "$NOTA" ] && return 0
    mkdir -p "$DIA_DIR"
    if [ -f "$PLANTILLA" ]; then
        local dias=(domingo lunes martes miércoles jueves viernes sábado)
        local meses=(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
        local titulo="${dias[$(date +%w)]^}, $(date +%-d) ${meses[$((10#$(date +%m)-1))]^} $(date +%Y)"
        sed -e "s/{{date:dddd, D MMMM YYYY}}/$titulo/" \
            -e "s/{{date:YYYY-MM-DD}}/$HOY/g" \
            -e "s/{{date}}/$HOY/g" "$PLANTILLA" > "$NOTA"
    else
        cat > "$NOTA" <<EOF
---
fecha: $HOY
---

# $(date +%F)

## Tareas nuevas de hoy
- [ ]

## Notas del día
<!-- reflexiones, eventos, contexto -->

## Cierre del día
- **Hecho:**
- **Aprendido:**
- **Pendiente para mañana:**
EOF
    fi
}

list_tasks() {
    awk '
        {
            line = $0
            if      (line ~ /^- \[[xX]\] /) { d = 1; t = substr(line, 7) }
            else if (line ~ /^- \[ \] /)    { d = 0; t = substr(line, 7) }
            else next
            if (t == "") next
            print NR "\t" d "\t" t
        }
    ' "$NOTA"
}

add_task() {
    local txt="$1"
    [ -z "$txt" ] && return 0
    local tmp="$NOTA.tmp"
    awk -v t="$txt" '
        { L[NR] = $0
          if ($0 == "## Tareas nuevas de hoy" && sec1 == 0) sec1 = NR
          if ($0 == "## Agenda" && sec2 == 0) sec2 = NR }
        END {
            sec = (sec1 ? sec1 : (sec2 ? sec2 : 0)); ins = 0
            if (sec) {
                ins = sec
                for (i = sec + 1; i <= NR; i++) {
                    if (L[i] ~ /^## /) break
                    if (L[i] ~ /^- \[.\] /) ins = i
                }
            }
            for (i = 1; i <= NR; i++) { print L[i]; if (i == ins) print "- [ ] " t }
            if (ins == 0) print "- [ ] " t
        }
    ' "$NOTA" > "$tmp" && mv "$tmp" "$NOTA"
}

toggle_task() {
    local n="$1"
    if sed -n "${n}p" "$NOTA" | grep -qE '^- \[[xX]\]'; then
        sed -i "${n}s/^- \[[xX]\]/- [ ]/" "$NOTA"
    else
        sed -i "${n}s/^- \[ \]/- [x]/" "$NOTA"
    fi
}

del_task() {
    local n="$1"
    local tmp="$NOTA.tmp"
    awk -v n="$n" 'NR != n' "$NOTA" > "$tmp" && mv "$tmp" "$NOTA"
}

[ -d "$VAULT" ] || { echo "NOVAULT"; exit 1; }

case "${1:-}" in
    list)    ensure_note; list_tasks ;;
    add)     ensure_note; add_task "${2:-}" ;;
    toggle)  toggle_task "${2:-}" ;;
    del)     del_task "${2:-}" ;;
    ensure)  ensure_note ;;
    path)    echo "$NOTA" ;;
    *)       echo "uso: tasks-ctl.sh {list|add <texto>|toggle <idx>|del <idx>|ensure|path}"; exit 1 ;;
esac
