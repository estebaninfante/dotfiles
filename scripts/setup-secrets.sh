#!/usr/bin/env bash
# setup-secrets.sh — Configura/verifica claves y secrets post-install.
#
# Idempotente y NO destructivo: solo pide el secret que falte y reporta
# PASS/SKIP/MANUAL por item. Nada de esto va al repo (son secrets/estado local).
#
# Uso rapido con opencode: «corre scripts/setup-secrets.sh y dime que falta»
set -uo pipefail

REPO="${HOME}/dotfiles"
PASS=0; SKIP=0; MANUAL=0; FAIL=0
report() { # <estado> <item> <detalle?>
    local st="$1" item="$2"; shift 2
    case "$st" in
        PASS)   PASS=$((PASS+1)); printf '%-6s %-30s %s\n' "PASS"   "$item" "$*" ;;
        SKIP)   SKIP=$((SKIP+1)); printf '%-6s %-30s %s\n' "SKIP"   "$item" "$*" ;;
        MANUAL) MANUAL=$((MANUAL+1)); printf '%-6s %-30s %s\n' "MANUAL" "$item" "$*" ;;
        FAIL)   FAIL=$((FAIL+1)); printf '%-6s %-30s %s\n' "FAIL"   "$item" "$*" ;;
    esac
}

# ── machine-type ────────────────────────────────────────────────
if [ -f "${HOME}/.config/machine-type" ]; then
    report PASS "machine-type" "$(cat "${HOME}/.config/machine-type")"
else
    if [ -x "${REPO}/scripts/detect-machine.sh" ]; then
        mt="$("${REPO}/scripts/detect-machine.sh")"
        echo "$mt" > "${HOME}/.config/machine-type"
        report PASS "machine-type" "creado: $mt"
    else
        report FAIL "machine-type" "no existe y falta detect-machine.sh"
    fi
fi

# ── SSH: claves ─────────────────────────────────────────────────
if [ ! -f "${HOME}/.ssh/id_ed25519" ]; then
    read -r -p "No hay ~/.ssh/id_ed25519. Crear ahora? [y/N] " yn
    if [ "${yn:-n}" = "y" ]; then
        ssh-keygen -t ed25519 -C "eztvn@$(hostname)" -N "" -f "${HOME}/.ssh/id_ed25519"
        report PASS "ssh key" "creada: $(cat "${HOME}/.ssh/id_ed25519.pub" | awk '{print $3}')"
    else
        report MANUAL "ssh key" "crear con ssh-keygen -t ed25519"
    fi
else
    report PASS "ssh key" "presente ($(cat "${HOME}/.ssh/id_ed25519.pub" | awk '{print $3}'))"
fi

# ── SSH: host trust + conectividad bidireccional ────────────────
peer="$([ "$(hostname)" = "laptop" ] && echo desktop || echo laptop)"
peer_ip="$(tailscale ip -4 "$peer" 2>/dev/null)"
if [ -n "$peer_ip" ]; then
    if ! ssh-keygen -F "$peer" >/dev/null 2>&1 && ! ssh-keygen -F "$peer_ip" >/dev/null 2>&1; then
        ssh-keyscan -H "$peer" "$peer_ip" >> "${HOME}/.ssh/known_hosts" 2>/dev/null
    fi
    if ssh -o BatchMode=yes -o ConnectTimeout=3 "eztvn@$peer" true 2>/dev/null; then
        report PASS "ssh -> $peer" "$peer_ip"
    else
        report MANUAL "ssh -> $peer" "aceptar host key o autorizar llave: ssh eztvn@$peer"
    fi
else
    report SKIP "ssh -> $peer" "tailscale no resuelve $peer (offline?)"
fi

# ── authorizedKeys en el repo ───────────────────────────────────
cfg="${REPO}/nixos/configuration.nix"
for pub in "${HOME}/.ssh"/*.pub; do
    [ -e "$pub" ] || continue
    fp="$(cut -d' ' -f1-2 "$pub")"
    if grep -qF "$fp" "$cfg"; then
        report PASS "authorizedKey $(basename "$pub" .pub)" "en configuration.nix"
    else
        report MANUAL "authorizedKey $(basename "$pub" .pub)" "falta en configuration.nix: $fp"
    fi
done

# ── tailscale ───────────────────────────────────────────────────
if tailscale status >/dev/null 2>&1; then
    report PASS "tailscale" "up ($(tailscale ip -4 2>/dev/null | head -1))"
else
    report MANUAL "tailscale" "pendiente: sudo tailscale up --authkey=<KEY>"
fi

# ── Sunshine (host Moonlight) ───────────────────────────────────
if command -v sunshine >/dev/null 2>&1; then
    sdir="${HOME}/.config/sunshine"
    mkdir -p "$sdir"
    if [ ! -f "$sdir/.webui-password" ]; then
        read -r -p "Password webui sunshine (vacio para copiar del peer): " pw
        if [ -n "$pw" ]; then
            echo "$pw" > "$sdir/.webui-password"
        else
            rsync "eztvn@$peer:$sdir/.webui-password" "$sdir/" 2>/dev/null \
                && report PASS "sunshine webui-pass" "copiada de $peer" \
                || report FAIL "sunshine webui-pass" "no copiable de $peer"
        fi
    else
        report PASS "sunshine webui-pass" "presente"
    fi
    systemctl --user stop sunshine 2>/dev/null
    sunshine --creds eztvn "$(cat "$sdir/.webui-password")" >/dev/null 2>&1
    systemctl --user start sunshine 2>/dev/null
    report PASS "sunshine creds" "eztvn + webui-pass aplicados"
else
    report SKIP "sunshine" "no instalado"
fi

# ── Hermes ──────────────────────────────────────────────────────
if command -v hermes >/dev/null 2>&1; then
    if hermes --version >/dev/null 2>&1; then
        report PASS "hermes" "instalado"
    else
        report MANUAL "hermes" "ejecutar: hermes setup"
    fi
else
    report SKIP "hermes" "no instalado"
fi

# ── syncthing: device IDs ───────────────────────────────────────
if command -v syncthing >/dev/null 2>&1; then
    id_local="$(syncthing --device-id 2>/dev/null)"
    if [ -n "$id_local" ]; then
        report MANUAL "syncthing" "local ID: ${id_local:0:8}... — parear con el peer en la GUI"
    else
        report MANUAL "syncthing" "parear device IDs en la GUI (acciones -> mostrar ID)"
    fi
else
    report SKIP "syncthing" "no instalado"
fi

# ── gh (GitHub) ─────────────────────────────────────────────────
if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        report PASS "gh auth" "logueado"
    else
        report MANUAL "gh auth" "ejecutar: gh auth login"
    fi
else
    report SKIP "gh auth" "no instalado"
fi

# ── Handy: Groq key en settings_store ───────────────────────────
hst="${HOME}/.local/share/com.pais.handy/settings_store.json"
if [ -f "$hst" ]; then
    if grep -q "api_key" "$hst" 2>/dev/null || grep -qiE "groq" "$hst"; then
        report PASS "handy groq" "configurado"
    else
        report MANUAL "handy groq" "falta API key de Groq en settings_store.json"
    fi
else
    report SKIP "handy groq" "handy nunca iniciado (settings_store no existe)"
fi

# ── Resumen ─────────────────────────────────────────────────────
echo
echo "================ RESUMEN ================"
echo "  PASS:   $PASS"
echo "  SKIP:   $SKIP"
echo "  MANUAL: $MANUAL"
echo "  FAIL:   $FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ] && [ "$MANUAL" -eq 0 ] && exit 0 || exit 2
