#!/usr/bin/env bash
# Docker test for setup-ubuntu.sh
# Validates script runs on fresh Ubuntu 24.04 without errors
set -uo pipefail

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="dotfiles-test-$(date +%s)"
RESULTS=()
PASS=0
FAIL=0

log()  { echo -e "\033[1;34m[test]\033[0m $*"; }
ok()   { RESULTS+=("PASS: $1"); PASS=$((PASS + 1)); echo -e "  \033[1;32m✓\033[0m $1"; }
fail() { RESULTS+=("FAIL: $1 — $2"); FAIL=$((FAIL + 1)); echo -e "  \033[1;31m✗\033[0m $1 — $2"; }

cleanup() {
    log "Cleaning up container..."
    docker rm -f "$CONTAINER" &>/dev/null || true
}
trap cleanup EXIT

# Build test image
log "Building test image from ubuntu:24.04..."
docker build -t dotfiles-test - <<'DOCKERFILE'
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    git curl ca-certificates sudo \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
DOCKERFILE

log "Starting container..."
docker run -d \
    --name "$CONTAINER" \
    -v "$DOTFILES:/home/testuser/dotfiles" \
    dotfiles-test \
    sleep 3600

# Helper: run command as testuser
as_user() { docker exec "$CONTAINER" su - testuser -c "$*"; }

run_cmd() {
    local desc="$1"; shift
    if as_user "$*" &>/dev/null; then
        ok "$desc"
    else
        fail "$desc" "command failed"
    fi
}

check_file() {
    local desc="$1" path="$2"
    if docker exec "$CONTAINER" test -e "$path" &>/dev/null; then
        ok "$desc"
    else
        fail "$desc" "not found at $path"
    fi
}

check_link() {
    local desc="$1" path="$2"
    local target
    target=$(docker exec "$CONTAINER" readlink -f "$path" 2>/dev/null || echo "")
    if [[ -z "$target" ]]; then
        fail "$desc" "not a symlink"
    elif [[ "$path" == "$target" ]]; then
        fail "$desc" "symlink not resolved"
    else
        ok "$desc → $(basename "$target")"
    fi
}

# ─── Phase 1: Bootstrap ───
log "Phase 1: Bootstrap check..."
run_cmd "git installed" "git --version"
run_cmd "curl installed" "curl --version"

# ─── Phase 2: Dry-run ───
log "Phase 2: Dry-run..."
as_user "bash /home/testuser/dotfiles/scripts/setup-ubuntu.sh --dry-run --skip-nvidia --skip-builds" 2>&1 | tail -5

# ─── Phase 3: Actual install ───
log "Phase 3: Running setup-ubuntu.sh (--skip-nvidia --skip-builds)..."
as_user "bash /home/testuser/dotfiles/scripts/setup-ubuntu.sh --skip-nvidia --skip-builds" 2>&1 | tee /tmp/setup-output.log | tail -30
SETUP_EXIT=${PIPESTATUS[0]:-0}

if [[ "$SETUP_EXIT" -ne 0 ]]; then
    fail "setup-ubuntu.sh exit code" "$SETUP_EXIT"
else
    ok "setup-ubuntu.sh completed successfully"
fi

# ─── Phase 4: Verify ───
log "Phase 4: Verifying installed components..."

# APT packages — check common binary paths
for pair in \
    "git:/usr/bin/git" "curl:/usr/bin/curl" "wget:/usr/bin/wget" \
    "htop:/usr/bin/htop" "tmux:/usr/bin/tmux" "neovim:/usr/bin/nvim" \
    "batcat:/usr/bin/batcat" "fdfind:/usr/bin/fdfind" "rg:/usr/bin/rg" \
    "eza:/usr/bin/eza" "fzf:/usr/bin/fzf" "jq:/usr/bin/jq" \
    "stow:/usr/bin/stow" "lazygit:/usr/bin/lazygit" \
    "tree:/usr/bin/tree" "unzip:/usr/bin/unzip" \
    "make:/usr/bin/make" "gcc:/usr/bin/gcc" "pkg-config:/usr/bin/pkg-config"; do
    name="${pair%%:*}"; path="${pair#*:}"
    check_file "apt: $name" "$path"
done

# CLI tools via setup script
for bin in starship zoxide gh pnpm uv; do
    check_file "cli: $bin" "/home/testuser/.local/bin/$bin"
done

# Rust
check_file "rust: cargo" "/home/testuser/.cargo/bin/cargo"
check_file "rust: rustc" "/home/testuser/.cargo/bin/rustc"

# Symlinks (config dirs)
for dir in hypr kitty nvim waybar fastfetch btop gh opencode mako; do
    check_link "~/.config/$dir" "/home/testuser/.config/$dir"
done

# Home files
check_link "~/.bashrc" "/home/testuser/.bashrc"
check_link "~/.gitconfig" "/home/testuser/.gitconfig"

# Scripts
for script in theme-toggle.sh rebuild.sh publish.sh bedtime.sh; do
    check_file "script: $script" "/home/testuser/.local/bin/$script"
done

# XDG dirs
for dir in Desktop Downloads Documents Music Pictures Videos Templates Public; do
    check_file "xdg: $dir" "/home/testuser/$dir"
done

# Wallpapers
check_file "wallpapers" "/home/testuser/Pictures/wallpapers/porsche_wallpaper.jpg"

# machine-type
check_file "machine-type" "/home/testuser/.config/machine-type"

# ─── Summary ───
echo ""
echo "═══════════════════════════════════════"
printf "  TEST RESULTS: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════"
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failed checks:"
    for r in "${RESULTS[@]}"; do
        [[ "$r" == FAIL:* ]] && echo "  $r"
    done
    exit 1
fi
echo "All checks passed!"
