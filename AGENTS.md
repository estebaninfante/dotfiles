# Dotfiles

`~/dotfiles` es la fuente de verdad. Todo lo gestionado vive acá; `~/.config`,
`~/.local/bin`, etc. son symlinks a este repo. Se edita acá, nunca en el destino.

Omarchy (Arch). Paquetes con `pacman`/`yay`.

## Dónde va cada cosa

| Ruta | Qué |
|------|-----|
| `linux/config/` | `~/.config/`: hypr, waybar, kitty, nvim, quickshell, opencode, … |
| `linux/home/` | `~/.bashrc`, `~/.gitconfig` |
| `linux/bin/` | scripts propios → `~/.local/bin` (ver su `README.md`) |
| `linux/voice/`, `linux/dictado/` | TTS, dictado, Kokoro |
| `linux/agents/` | reglas globales del harness (`AGENTS.md`) y skills |
| `linux/dsh/plugins/` | plugins del harness: `machine`, `skills`, `bash-guard`, … |
| `linux/system/` | systemd user, keyd, NetworkManager, sysctl, speech-dispatcher |
| `scripts/` | setup, link-dotfiles, publish, doctor, verify |
| `docs/` | notas largas: main-bridge, motion, agentes, … |
| `windows/` | LAN Mouse para Windows |

`~/.config/omarchy/` es **copiado**, no symlink: se exporta/importa con
`scripts/omarchy-sync.sh`.

## Flujo

1. Editar dentro del repo.
2. `scripts/link-dotfiles.sh` si sumaste archivo o script.
3. `scripts/publish.sh --yes` (único dueño de commit + push).
4. `scripts/doctor.sh` si tocaste rutas del filesystem o worktrees.

## Filesystem del usuario

| Ruta | Regla |
|------|-------|
| `~/Proyectos/` | única raíz de código; solo carpetas de proyecto |
| `~/Proyectos/_archivo/` | repos dormidos |
| `~/Archivo/` | datos fríos |
| `~/Descargas/` | única carpeta de descargas (XDG) |
| `~/Imágenes/screenshots/` | capturas nuevas |
| `~/Escritorio/` | bandeja del día; vacía al cerrar |
| `~/alicia/` | notas del usuario, congelado: ninguna IA escribe ahí |

- Nada de archivos sueltos en `$HOME`. Backups en `~/.local/state/dotfiles-backups/`.
- `~/.config/user-dirs.dirs` se genera desde `linux/config/user-dirs.dirs.template`.

## Trampas

- No tocar bloques `if machine == "X"`: son machine-specific. Tipo: `scripts/detect-machine.sh`.
- `~/.dsh/plugins` es symlink; un plugin de host nuevo necesita `dsh-web --restart` (lo corre el usuario).
- Servicios solo por loopback + Tailscale. No habilitar units sin que el usuario lo pida.
- Sunshine: `autoStart=false` obligatorio.
- Las máquinas se apagan solas a las 21:00 (`bedtime.timer`).

## Autonomía

Editar → aplicar → verificar sin pedir permiso. Confirmar solo para borrar datos,
reinstalar paquetes o reiniciar/apagar la máquina.
