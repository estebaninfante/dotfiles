# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc
export PATH="$HOME/.local/bin:$PATH"

# Alias para abrir LibreOffice desde la terminal en segundo plano
lo() {
    libreoffice "$@" >/dev/null 2>&1 &
}
alias office='lo'

# Cambiar wallpaper animado (Wallpaper Engine nativo) rápido
alias wall='wallpaper-switch.sh'
alias walls='wallpaper-switch.sh list'


# opencode
export PATH=/home/eztvn/.opencode/bin:$PATH
alias opencode="script -q -c \"opencode\" /dev/null"

# kitty: disable SIGTSTP so ctrl+z reaches opencode as undo
if [[ -n "$KITTY_WINDOW_ID" ]]; then
    stty susp ^-
fi
. "$HOME/.cargo/env"

# zoxide (smarter cd)
eval "$(zoxide init bash)"

# starship prompt
eval "$(starship init bash)"

# nixos-rebuild con flake; detecta laptop/desktop automaticamente
nrb() {
    local machine="$(cat ~/.config/machine-type 2>/dev/null || echo laptop)"
    if [ "$machine" = "desktop" ]; then
        # sunshine cudaSupport recompila desde fuente: paralelismo default
        # (max-jobs=24) OOM sin swap. Controlar max-jobs/cores en desktop.
        sudo env NIX_CONFIG="max-jobs = 2"$'\n'"cores = 8" \
            nixos-rebuild "$@" --flake "$HOME/dotfiles#$machine"
    else
        sudo nixos-rebuild "$@" --flake "$HOME/dotfiles#$machine"
    fi
}
