#!/usr/bin/env bash
# ── refind-check.sh ──
# Verifica integridad de /boot/EFI/refind/refind.conf despues de cada rebuild.
# Chequea: existencia de archivos, integridad de options (init=), coherencia
# con el perfil del sistema activo.
#
# Uso:
#   bash refind-check.sh          # verificacion completa (requiere sudo para /boot)
#   bash refind-check.sh --quiet  # solo errores (exit 1 si hay problemas)
#
# Ejecutado automaticamente por rebuild.sh tras cada nixos-rebuild.
# Tambien ejecutable manualmente para diagnostico.
set -uo pipefail

CONF="/boot/EFI/refind/refind.conf"
KERNELS_DIR="/boot/EFI/refind/kernels"
QUIET=false
ERRORS=0
WARNINGS=0

[[ "${1:-}" == "--quiet" ]] && QUIET=true

# Helper: leer archivos de /boot via sudo
cat_boot() { sudo cat "$1" 2>/dev/null; }
test_boot() { sudo test "$1" 2>/dev/null; }
ls_boot() { sudo ls "$1" 2>/dev/null; }

log_ok()   { $QUIET || echo "  ✓ $1"; }
log_warn() { echo "  ⚠ WARN: $1" >&2; ((WARNINGS++)); }
log_fail() { echo "  ✗ FAIL: $1" >&2; ((ERRORS++)); }

echo "── refind-check: verificando integridad ──"

# ── 1. Verificar que refind.conf existe ──
if ! test_boot "$CONF"; then
  log_fail "refind.conf no existe en $CONF"
  echo "Resultado: FAIL ($ERRORS errores, $WARNINGS warnings)"
  exit 1
fi
log_ok "refind.conf existe"

# ── 2. Leer el perfil del sistema activo ──
SYSTEM_PROFILE="$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)"
if [ -z "$SYSTEM_PROFILE" ]; then
  log_warn "No se pudo leer perfil del sistema (/nix/var/nix/profiles/system)"
  EXPECTED_INIT=""
else
  EXPECTED_INIT="${SYSTEM_PROFILE}/init"
  log_ok "Perfil activo: $SYSTEM_PROFILE"
fi

# ── 3. Parsear refind.conf y verificar cada entrada ──
# Variables de contexto para el menuentry actual
CURRENT_ENTRY=""
IN_MENUENTRY=false

while IFS= read -r line || [ -n "$line" ]; do
  # Detectar inicio de menuentry
  if [[ "$line" =~ ^menuentry[[:space:]]+\"([^\"]+)\" ]]; then
    CURRENT_ENTRY="${BASH_REMATCH[1]}"
    IN_MENUENTRY=true
    continue
  fi

  # Detectar submenuentry
  if [[ "$line" =~ ^[[:space:]]*submenuentry[[:space:]]+\"([^\"]+)\" ]]; then
    CURRENT_ENTRY="${CURRENT_ENTRY} > ${BASH_REMATCH[1]}"
    continue
  fi

  # Fin de bloque (linea vacia fuera de menuentry)
  if $IN_MENUENTRY && [[ -z "${line// /}" ]]; then
    CURRENT_ENTRY=""
    IN_MENUENTRY=false
    continue
  fi

  # ── Verificar loader ──
  if [[ "$line" =~ ^[[:space:]]*loader[[:space:]]+(.+)$ ]]; then
    loader_path="${BASH_REMATCH[1]}"
    loader_path="${loader_path%"${loader_path##*[![:space:]]}"}"  # trim trailing
    # Convertir a ruta absoluta en el ESP
    if [[ "$loader_path" == /* ]]; then
      full_path="/boot${loader_path}"
    else
      full_path="/boot/EFI/${loader_path}"
    fi
    if test_boot "$full_path"; then
      log_ok "[$CURRENT_ENTRY] loader existe: $(basename "$full_path")"
    else
      log_fail "[$CURRENT_ENTRY] loader NO existe: $full_path"
    fi
  fi

  # ── Verificar initrd ──
  if [[ "$line" =~ ^[[:space:]]*initrd[[:space:]]+(.+)$ ]]; then
    initrd_path="${BASH_REMATCH[1]}"
    initrd_path="${initrd_path%"${initrd_path##*[![:space:]]}"}"
    if [[ "$initrd_path" == /* ]]; then
      full_path="/boot${initrd_path}"
    else
      full_path="/boot/EFI/${initrd_path}"
    fi
    if test_boot "$full_path"; then
      log_ok "[$CURRENT_ENTRY] initrd existe: $(basename "$full_path")"
    else
      log_fail "[$CURRENT_ENTRY] initrd NO existe: $full_path"
    fi
  fi

  # ── Verificar options (init=) ──
  if [[ "$line" =~ ^[[:space:]]*options[[:space:]]+(.+)$ ]]; then
    options_raw="${BASH_REMATCH[1]}"
    # Limpiar comillas
    options_clean="${options_raw//\"/}"
    options_clean="${options_clean//\'/}"

    # Check for corruption: > char in options
    if [[ "$options_clean" == *">"* ]]; then
      log_fail "[$CURRENT_ENTRY] '>' corrupto en options: $options_clean"
    fi

    # Extract init= path
    if [[ "$options_clean" =~ init=([^[:space:]]+) ]]; then
      init_path="${BASH_REMATCH[1]}"
      # Verify init path length (Nix store paths are ~60+ chars)
      if [ ${#init_path} -lt 40 ]; then
        log_fail "[$CURRENT_ENTRY] init= path muy corto (${#init_path} chars, posible truncamiento): $init_path"
      elif [[ "$init_path" != /nix/store/* ]]; then
        log_fail "[$CURRENT_ENTRY] init= no apunta a /nix/store/: $init_path"
      else
        # Verify it matches the active system profile
        if [ -n "$EXPECTED_INIT" ] && [ "$init_path" != "$EXPECTED_INIT" ]; then
          log_warn "[$CURRENT_ENTRY] init= ($init_path) no coincide con perfil activo"
        else
          log_ok "[$CURRENT_ENTRY] init= path valido (${#init_path} chars)"
        fi
      fi
    else
      log_fail "[$CURRENT_ENTRY] options sin init=: $options_clean"
    fi
  fi

done < <(cat_boot "$CONF")

# ── 4. Verificar que no hay archivos huérfanos en kernels/ ──
if ls_boot "$KERNELS_DIR" >/dev/null 2>&1; then
  orphan_count=0
  for f in $(ls_boot "$KERNELS_DIR"); do
    fname="$(basename "$f")"
    if ! sudo grep -q "$fname" "$CONF" 2>/dev/null; then
      log_warn "Archivo huérfano en kernels/: $fname"
      ((orphan_count++))
    fi
  done
  [ $orphan_count -eq 0 ] && log_ok "Sin archivos huérfanos en kernels/"
fi

# ── Resultado ──
echo ""
if [ $ERRORS -gt 0 ]; then
  echo "Resultado: FAIL ($ERRORS errores, $WARNINGS warnings)"
  echo "⚠ refind.conf tiene problemas que pueden impedir el boot."
  echo "Corregir ANTES de reiniciar. Usar un live USB si el sistema no arranca."
  exit 1
elif [ $WARNINGS -gt 0 ]; then
  echo "Resultado: PASS con warnings ($WARNINGS warnings)"
  exit 0
else
  echo "Resultado: PASS"
  exit 0
fi
