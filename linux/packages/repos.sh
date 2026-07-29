#!/usr/bin/env bash
# ── Repositorios adicionales para Fedora ──
# Ejecutar: sudo bash repos.sh
set -euo pipefail

echo "=== Agregando repositorios ==="

# ── RPM Fusion (free + nonfree) ──
if ! dnf repolist --enabled 2>/dev/null | grep -q rpmfusion-free; then
  sudo dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
  echo "  ✓ RPM Fusion instalado"
else
  echo "  ✓ RPM Fusion ya presente"
fi

# ── COPR: Hyprland (lionheartp) ──
if ! dnf repolist --enabled 2>/dev/null | grep -q copr.*lionheartp.*Hyprland; then
  sudo dnf copr enable -y lionheartp/Hyprland
  echo "  ✓ COPR Hyprland activado"
else
  echo "  ✓ COPR Hyprland ya presente"
fi

# ── COPR: keyd (alternateved) ──
if ! dnf repolist --enabled 2>/dev/null | grep -q copr.*alternateved.*keyd; then
  sudo dnf copr enable -y alternateved/keyd
  echo "  ✓ COPR keyd activado"
else
  echo "  ✓ COPR keyd ya presente"
fi

# ── Brave Browser ──
if [ ! -f /etc/yum.repos.d/brave-browser.repo ]; then
  sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
  echo "  ✓ Brave repo añadido"
else
  echo "  ✓ Brave repo ya presente"
fi

# ── Google Chrome ──
if [ ! -f /etc/yum.repos.d/google-chrome.repo ]; then
  sudo dnf config-manager --add-repo https://dl.google.com/linux/chrome/rpm/stable/x86_64
  echo "  ✓ Google Chrome repo añadido"
else
  echo "  ✓ Google Chrome repo ya presente"
fi

# ── Flathub (flatpak) ──
if ! flatpak remotes 2>/dev/null | grep -q flathub; then
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  echo "  ✓ Flathub añadido"
else
  echo "  ✓ Flathub ya presente"
fi

echo ""
echo "=== Repositorios listos ==="