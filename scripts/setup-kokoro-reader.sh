#!/usr/bin/env bash
# setup-kokoro-reader.sh — Kokoro local como voces del "Read Aloud" de Zotero.
#
# Idempotente. Instala/actualiza:
#   1. Paquetes: speech-dispatcher, espeak-ng, alsa-utils, poppler, sox y
#      zotero-bin (AUR, si falta).
#   2. venv ~/.local/share/kokoro-venv (uv + Python 3.12): torch CPU, kokoro,
#      misaki[en], soundfile y el modelo spaCy en_core_web_sm.
#   3. Módulo /etc/speech-dispatcher/modules/kokoro.conf (desde el template del
#      repo, con el home real) + AddModule en speechd.conf.
#   4. Unit de usuario kokoro-tts.service (enable --now).
#
# Uso: scripts/setup-kokoro-reader.sh      (SKIP_KOKORO=1 para omitir en setup)
set -uo pipefail

REPO="${HOME}/dotfiles"
VENV="${HOME}/.local/share/kokoro-venv"
PY="${VENV}/bin/python"
MODULE_SRC="${REPO}/linux/system/speech-dispatcher/kokoro.conf"
MODULE_DST="/etc/speech-dispatcher/modules/kokoro.conf"
SPEECHD_CONF="/etc/speech-dispatcher/speechd.conf"
UNIT_SRC="${REPO}/linux/system/systemd-user/kokoro-tts.service"
UNIT_DST="${HOME}/.config/systemd/user/kokoro-tts.service"

log() { echo "setup-kokoro-reader: $*"; }
die() { echo "setup-kokoro-reader: ERROR: $*" >&2; exit 1; }

if [[ "${SKIP_KOKORO:-0}" == "1" ]]; then
    log "SKIP_KOKORO=1, omitido"
    exit 0
fi

[[ -f "$MODULE_SRC" ]] || die "falta $MODULE_SRC (¿corriste link-dotfiles.sh?)"

# 0) Asegurar symlinks de los wrappers (linux/bin -> ~/.local/bin)
if [[ ! -x "${HOME}/.local/bin/kokoro-server" && -x "$REPO/scripts/link-dotfiles.sh" ]]; then
    log "aplicando symlinks (link-dotfiles.sh)"
    bash "$REPO/scripts/link-dotfiles.sh" >/dev/null 2>&1 || true
fi

# 1) Paquetes de repos
PACMAN_PKGS=(speech-dispatcher espeak-ng alsa-utils poppler sox)
MISSING=()
for pkg in "${PACMAN_PKGS[@]}"; do
    pacman -Qi "$pkg" &>/dev/null || MISSING+=("$pkg")
done
if (( ${#MISSING[@]} > 0 )); then
    sudo -n true 2>/dev/null || die "sudo sin contraseña requerido para instalar: ${MISSING[*]}"
    log "instalando paquetes: ${MISSING[*]}"
    sudo pacman -S --needed --noconfirm "${MISSING[@]}" || die "pacman falló"
fi

# 2) Zotero (AUR) si falta
if ! command -v zotero &>/dev/null; then
    HELPER="$(command -v yay || command -v paru || true)"
    if [[ -n "$HELPER" ]]; then
        sudo -n true 2>/dev/null || die "sudo sin contraseña requerido para instalar zotero-bin"
        log "instalando zotero-bin (AUR, puede tardar)"
        "$HELPER" -S --needed --noconfirm zotero-bin || log "WARN: zotero-bin no se pudo instalar"
    else
        log "WARN: no hay yay/paru; omito zotero-bin"
    fi
fi

# 3) venv + dependencias
if [[ ! -x "$PY" ]]; then
    command -v uv >/dev/null || die "falta uv (linux/bin/uv; corré link-dotfiles.sh)"
    log "creando venv (~/.local/share/kokoro-venv, Python 3.12)"
    uv venv --python 3.12 "$VENV" || die "uv venv falló"
fi

if ! "$PY" -c 'import torch, kokoro, misaki, soundfile' 2>/dev/null; then
    log "instalando torch CPU (puede tardar)"
    uv pip install --python "$PY" torch --index-url https://download.pytorch.org/whl/cpu || die "torch falló"
    log "instalando kokoro + misaki[en] + soundfile"
    uv pip install --python "$PY" kokoro 'misaki[en]' soundfile || die "dependencias de Kokoro fallaron"
fi

if ! "$PY" -c 'import spacy; spacy.load("en_core_web_sm")' 2>/dev/null; then
    log "instalando modelo spaCy en_core_web_sm"
    uv pip install --python "$PY" \
        "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl" \
        || die "modelo spaCy falló"
fi

# 4) Módulo de speech-dispatcher (nivel sistema)
sudo -n true 2>/dev/null || die "sudo sin contraseña requerido para configurar speech-dispatcher"
sudo install -d /etc/speech-dispatcher/modules
sed "s|@HOME@|${HOME}|g" "$MODULE_SRC" | sudo tee "$MODULE_DST" >/dev/null \
    || die "no pude instalar $MODULE_DST"
if ! grep -q '^AddModule "kokoro"' "$SPEECHD_CONF" 2>/dev/null; then
    echo 'AddModule "kokoro" "sd_generic" "kokoro.conf"' | sudo tee -a "$SPEECHD_CONF" >/dev/null \
        || die "no pude registrar el módulo en $SPEECHD_CONF"
fi

# 5) Unit de usuario
mkdir -p "$(dirname "$UNIT_DST")"
if [[ ! -f "$UNIT_DST" ]] || ! cmp -s "$UNIT_SRC" "$UNIT_DST"; then
    rm -f "$UNIT_DST"
    install -m 0644 "$UNIT_SRC" "$UNIT_DST"
    systemctl --user daemon-reload
fi
systemctl --user enable kokoro-tts.service >/dev/null 2>&1 || true
systemctl --user restart kokoro-tts.service || die "no pude arrancar kokoro-tts.service"

# 6) Reiniciar speech-dispatcher y verificar voces
systemctl --user restart speech-dispatcher 2>/dev/null || true
found=0
for _ in $(seq 1 40); do
    if timeout 5 spd-say -L 2>/dev/null | grep -q 'Kokoro Liam'; then
        found=1
        break
    fi
    sleep 0.5
done
(( found == 1 )) || die "las voces Kokoro no aparecen en speech-dispatcher"

log "OK: voces Kokoro disponibles (Liam, Puck, Fable, Heart)"
log "en Zotero: Read Aloud → Local → English (United States) → Kokoro Liam"
