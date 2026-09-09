#!/usr/bin/env bash
# ── refind-check.sh ──
# Verifica integridad de /boot/EFI/refind/refind.conf despues de cada rebuild.
# Chequea: existencia de archivos, integridad de options (init=), estructura
# de menuentry (loader/initrd/options en raiz, no solo en submenuentry).
#
# Uso:
#   bash refind-check.sh          # verificacion completa
#   bash refind-check.sh --quiet  # solo errores (exit 1 si hay problemas)
#
# Ejecutado automaticamente por rebuild.sh tras cada nixos-rebuild.
# Tambien ejecutable manualmente para diagnostico.
set -uo pipefail

CONF="/boot/EFI/refind/refind.conf"
KERNELS_DIR="/boot/EFI/refind/kernels"

echo "── refind-check: verificando integridad ──"

# Leer refind.conf via sudo (necesario para /boot)
CONF_CONTENT="$(sudo cat "$CONF" 2>/dev/null)"
if [ -z "$CONF_CONTENT" ]; then
  echo "  ✗ FAIL: refind.conf no existe o sin permisos" >&2
  echo "Resultado: FAIL"
  exit 1
fi

echo "$CONF_CONTENT" | python3 -c "
import re, sys, os

conf = sys.argv[1]
kernels_dir = sys.argv[2]
quiet = '--quiet' in sys.argv

errors = 0
warnings = 0

def log_ok(msg):
    if not quiet:
        print(f'  ✓ {msg}')

def log_warn(msg):
    global warnings
    warnings += 1
    print(f'  ⚠ WARN: {msg}', file=sys.stderr)

def log_fail(msg):
    global errors
    errors += 1
    print(f'  ✗ FAIL: {msg}', file=sys.stderr)

def check_file(path):
    return os.path.isfile(path)

# Read system profile
try:
    profile = os.path.realpath('/nix/var/nix/profiles/system')
    log_ok(f'Perfil activo: {profile}')
except Exception:
    log_warn('No se pudo leer perfil del sistema')
    profile = None

with open(conf) as f:
    content = f.read()

# Parse menuentry blocks
lines = content.split('\n')
i = 0
while i < len(lines):
    line = lines[i]

    # Detect menuentry
    m = re.match(r'^menuentry\s+\"([^\"]+)\"', line)
    if m:
        entry_name = m.group(1)
        # Collect entire menuentry block
        block = [line]
        depth = line.count('{') - line.count('}')
        i += 1
        while i < len(lines) and depth > 0:
            block.append(lines[i])
            depth += lines[i].count('{') - lines[i].count('}')
            i += 1

        # Analyze: find root-level loader/initrd/options (before first submenuentry)
        root_loader = None
        root_initrd = None
        root_options = None
        first_submenu = None
        in_submenu = False
        sub_depth = 0

        for j, bline in enumerate(block):
            if j == 0:
                continue

            # Detect submenuentry
            sm = re.match(r'\s*submenuentry\s+\"([^\"]+)\"', bline)
            if sm:
                if first_submenu is None:
                    first_submenu = j
                in_submenu = True
                sub_depth = bline.count('{') - bline.count('}')
                continue

            if in_submenu:
                sub_depth += bline.count('{') - bline.count('}')
                if sub_depth <= 0:
                    in_submenu = False
                continue

            # Root level: check for loader/initrd/options
            lm = re.match(r'\s*loader\s+(.+)', bline)
            if lm:
                root_loader = lm.group(1).strip()
            im = re.match(r'\s*initrd\s+(.+)', bline)
            if im:
                root_initrd = im.group(1).strip()
            om = re.match(r'\s*options\s+(.+)', bline)
            if om:
                root_options = om.group(1).strip()

        # Check root-level directives
        has_root = root_loader and root_initrd and root_options
        if not has_root and first_submenu is not None:
            log_fail(f'[{entry_name}] loader/initrd/options ausentes en raiz del menuentry (solo en submenuentry)')
        elif has_root:
            log_ok(f'[{entry_name}] loader/initrd/options en raiz del menuentry')

        # Collect all loader/initrd/options from root + submenuentries
        all_loaders = []
        all_initrds = []
        all_options_list = []

        if root_loader:
            all_loaders.append(('root', root_loader))
        if root_initrd:
            all_initrds.append(('root', root_initrd))
        if root_options:
            all_options_list.append(('root', root_options))

        # Extract from submenuentries
        in_submenu = False
        sub_depth = 0
        current_sub = None
        for j, bline in enumerate(block):
            if j == 0:
                continue
            sm = re.match(r'\s*submenuentry\s+\"([^\"]+)\"', bline)
            if sm:
                current_sub = sm.group(1)
                in_submenu = True
                sub_depth = bline.count('{') - bline.count('}')
                continue
            if in_submenu:
                sub_depth += bline.count('{') - bline.count('}')
                if sub_depth <= 0:
                    in_submenu = False
                lm = re.match(r'\s*loader\s+(.+)', bline)
                if lm and current_sub:
                    all_loaders.append((current_sub, lm.group(1).strip()))
                im = re.match(r'\s*initrd\s+(.+)', bline)
                if im and current_sub:
                    all_initrds.append((current_sub, im.group(1).strip()))
                om = re.match(r'\s*options\s+(.+)', bline)
                if om and current_sub:
                    all_options_list.append((current_sub, om.group(1).strip()))

        # Check loader/initrd file existence
        for where, path in all_loaders:
            if path.startswith('/'):
                full = '/boot' + path
            else:
                full = '/boot/EFI/' + path
            tag = f'{entry_name} > {where}' if where != 'root' else entry_name
            if check_file(full):
                log_ok(f'[{tag}] loader: {os.path.basename(full)}')
            else:
                log_fail(f'[{tag}] loader NO existe: {full}')

        for where, path in all_initrds:
            if path.startswith('/'):
                full = '/boot' + path
            else:
                full = '/boot/EFI/' + path
            tag = f'{entry_name} > {where}' if where != 'root' else entry_name
            if check_file(full):
                log_ok(f'[{tag}] initrd: {os.path.basename(full)}')
            else:
                log_fail(f'[{tag}] initrd NO existe: {full}')

        # Check options integrity
        for where, opts in all_options_list:
            clean = opts.replace('\"', '').replace(\"'\", '')
            tag = f'{entry_name} > {where}' if where != 'root' else entry_name
            if '>' in clean:
                log_fail(f'[{tag}] > corrupto en options: {clean}')
            if 'init=' in clean:
                init_match = re.search(r'init=(\S+)', clean)
                if init_match:
                    init_path = init_match.group(1)
                    if len(init_path) < 40:
                        log_fail(f'[{tag}] init= muy corto ({len(init_path)} chars): {init_path}')
                    elif not init_path.startswith('/nix/store/'):
                        log_fail(f'[{tag}] init= no es /nix/store/: {init_path}')
                    else:
                        log_ok(f'[{tag}] init= valido ({len(init_path)} chars)')
            else:
                log_fail(f'[{tag}] options sin init=: {clean}')

    i += 1

# Check orphan files in kernels/
if os.path.isdir(kernels_dir):
    orphans = 0
    for fname in os.listdir(kernels_dir):
        if fname.startswith('.'):
            continue
        if fname not in content:
            log_warn(f'Archivo huérfano en kernels/: {fname}')
            orphans += 1
    if orphans == 0:
        log_ok('Sin archivos huérfanos en kernels/')

# Output result
print()
if errors > 0:
    print(f'Resultado: FAIL ({errors} errores, {warnings} warnings)')
    print('⚠ refind.conf tiene problemas que pueden impedir el boot.')
    print('Corregir ANTES de reiniciar. Usar un live USB si el sistema no arranca.')
    sys.exit(1)
elif warnings > 0:
    print(f'Resultado: PASS con warnings ({warnings} warnings)')
    sys.exit(0)
else:
    print('Resultado: PASS')
    sys.exit(0)
" "$CONF" "$KERNELS_DIR" ${1:-}
