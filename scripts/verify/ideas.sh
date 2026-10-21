#!/usr/bin/env bash
# verify/ideas.sh — la fábrica de ideas funciona de punta a punta.
#
# Comprueba, sin criterio humano, sobre un directorio temporal (no toca las
# ideas reales del usuario):
#   1. `ideas nueva` crea el archivo y regenera index.md.
#   2. `ideas listar` muestra la idea abierta.
#   3. `ideas anotar` agrega la entrada con fecha y agente a la conversación.
#   4. `ideas descartar` la saca del listado abierto pero no borra el archivo.
#   5. `ideas reabrir` la vuelve a poner abierta.
#   6. La extensión de pi declara la tool `idea` y el comando `/ideas`.
#   7. La skill fabrica-de-ideas existe y tiene frontmatter con name/description.
#
# Uso:
#   scripts/verify/ideas.sh           # texto
#   scripts/verify/ideas.sh --quiet   # solo FALLA/AVISO
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$REPO/linux/bin/ideas"
EXT="$REPO/linux/pi/agent/extensions/ideas.ts"
SKILL="$REPO/linux/pi/agent/skills/fabrica-de-ideas/SKILL.md"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PI_IDEAS_DIR="$TMP/ideas"
export PI_RIG_AGENTE=verificador

# --- 0. existe y es ejecutable ---------------------------------------------
if [ -x "$CLI" ]; then ok "CLI ideas ejecutable"; else fail "falta o no es ejecutable: $CLI"; fi

# --- 1. nueva --------------------------------------------------------------
salida="$("$CLI" nueva "Prueba de la fábrica" -t "Texto de prueba." -e "test" 2>&1)"
if printf '%s' "$salida" | grep -q "Idea guardada: IDEA-"; then ok "nueva crea la idea"; else fail "nueva no creó la idea: $salida"; fi
archivo="$(find "$PI_IDEAS_DIR" -maxdepth 1 -name 'IDEA-*.md' | head -1)"
[ -n "$archivo" ] && ok "archivo IDEA-XXXX.md creado" || fail "no hay archivo de idea"
[ -f "$PI_IDEAS_DIR/index.md" ] && ok "index.md generado" || fail "no se generó index.md"
grep -q "Prueba de la fábrica" "$PI_IDEAS_DIR/index.md" 2>/dev/null \
    && ok "index.md lista la idea" || fail "index.md no menciona la idea"

# --- 2. listar -------------------------------------------------------------
salida="$("$CLI" listar 2>&1)"
printf '%s' "$salida" | grep -q "Prueba de la fábrica" && ok "listar muestra la idea" || fail "listar no la muestra"

# --- 3. anotar -------------------------------------------------------------
ID="$(basename "$archivo" .md)"
"$CLI" anotar "$ID" "Conclusión de prueba." -r "riesgo de prueba" >/dev/null 2>&1
grep -q "Conclusión de prueba." "$archivo" 2>/dev/null && ok "anotar escribe en la conversación" || fail "anotar no escribió"
grep -q "verificador" "$archivo" 2>/dev/null && ok "la entrada lleva el agente" || fail "la entrada no lleva agente"

# --- 4. descartar ----------------------------------------------------------
"$CLI" descartar "$ID" "motivo de prueba" >/dev/null 2>&1
[ -f "$archivo" ] && ok "descartar no borra el archivo" || fail "descartar borró el archivo"
"$CLI" listar 2>&1 | grep -q "Prueba de la fábrica" && fail "descartar la dejó en el listado abierto" || ok "descartar la saca del listado abierto"
"$CLI" listar --todas 2>&1 | grep -q "Prueba de la fábrica" && ok "listar --todas la muestra" || fail "listar --todas no la muestra"
grep -q "descartada" "$archivo" 2>/dev/null && ok "el estado quedó en el archivo" || fail "el estado no quedó en el archivo"
grep -q "motivo de prueba" "$archivo" 2>/dev/null && ok "el motivo quedó escrito" || fail "el motivo no quedó escrito"

# --- 5. reabrir ------------------------------------------------------------
"$CLI" reabrir "$ID" >/dev/null 2>&1
"$CLI" listar 2>&1 | grep -q "Prueba de la fábrica" && ok "reabrir la devuelve al listado" || fail "reabrir no la devolvió"

# --- 6. extensión ----------------------------------------------------------
if [ -f "$EXT" ]; then
    ok "existe la extensión ideas.ts"
    grep -q 'registerTool({' "$EXT" && grep -q 'name: "idea"' "$EXT" \
        && ok "declara la tool idea" || fail "no declara la tool idea"
    grep -q 'registerCommand("ideas"' "$EXT" && ok "declara el comando /ideas" || fail "no declara /ideas"
    grep -q 'registerCommand("idea"' "$EXT" && ok "declara el comando /idea" || fail "no declara /idea"
    grep -q 'fabrica_de_ideas' "$EXT" && ok "inyecta la regla de captura" || fail "no inyecta la regla"
else
    fail "falta la extensión: $EXT"
fi

# --- 7. skill --------------------------------------------------------------
if [ -f "$SKILL" ]; then
    head -5 "$SKILL" | grep -q '^name: fabrica-de-ideas' && ok "skill con name" || fail "skill sin name"
    head -5 "$SKILL" | grep -q '^description:' && ok "skill con description" || fail "skill sin description"
else
    fail "falta la skill: $SKILL"
fi

if [ "$fails" -eq 0 ]; then
    [ "$QUIET" = 1 ] || printf '\nideas: OK\n'
    exit 0
fi
printf '\nideas: %s falla(s)\n' "$fails"
exit 1
