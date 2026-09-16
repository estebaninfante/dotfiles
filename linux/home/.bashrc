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

# deeptutor
alias deeptutor='source ~/deeptutor-env/bin/activate && deeptutor'

# Alias para abrir LibreOffice desde la terminal en segundo plano
lo() {
    libreoffice "$@" >/dev/null 2>&1 &
}
alias office='lo'

# Cambiar wallpaper animado (Wallpaper Engine nativo) rápido
alias wall='wallpaper-switch.sh'
alias walls='wallpaper-switch.sh list'


# TTS rápido: tts "hola mundo" | tts -en "hello world"
tts() {
    local lang="es"
    if [ "$1" = "-en" ]; then lang="en"; shift; fi
    voice lang "$lang" >/dev/null 2>&1
    voice speak "$@"
}

# Secrets locales (fuera del repo): API keys, tokens.
# Ver scripts/setup-secrets.sh. NO commitear este archivo.
if [ -f "$HOME/.config/dotfiles-secrets.sh" ]; then
    . "$HOME/.config/dotfiles-secrets.sh"
fi

# opencode
export PATH=/home/eztvn/.opencode/bin:$PATH
alias opencode="script -q -c \"opencode\" /dev/null"

# Arize Phoenix tracing (LLM observability)
export PHOENIX_ENDPOINT="http://localhost:6006"
export PHOENIX_PROJECT="opencode"
export ARIZE_TRACE_ENABLED="true"

# kitty: disable SIGTSTP so ctrl+z reaches opencode as undo
if [[ -n "$KITTY_WINDOW_ID" ]]; then
    stty susp ^-
fi
. "$HOME/.cargo/env"

# zoxide (smarter cd)
eval "$(zoxide init bash)"

# starship prompt
eval "$(starship init bash)"

# Omarchy/Arch: actualizacion y paquetes
alias update='omarchy-update'          # update completo de Omarchy
alias pacup='sudo pacman -Syu'         # pacman upgrade
alias yayup='yay -Syu'                 # AUR + repos
alias pkg='sudo pacman -S'             # instalar
alias y='yay -S'                       # instalar (AUR)
