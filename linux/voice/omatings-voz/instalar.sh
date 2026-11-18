#!/bin/bash
# instalar.sh — pone la página "Voz" dentro del plugin omatings.
#
# omatings se instala desde git (omarchy plugin add), así que sus archivos no
# viven en dotfiles: esta carpeta guarda SOLO lo nuestro (la página, su fila y
# su test) y este script lo copia adentro, parcheando lo mínimo:
#
#   1. Core/Pages.js  — agrega la entrada del sidebar `voice` si falta.
#   2. Settings.qml   — cambia la regla de ventana de `o.window(...)` a
#                       `hl.window_rule(...)`: Omarchy 4.0.4 no expone los
#                       helpers `o.*` dentro de `hyprctl eval`, y la ventana
#                       nacía mosaico (sin flotar ni centrar).
#
# Es idempotente: correrlo de nuevo tras `omarchy plugin update` reinstala la
# página. Después de un update grande, revisar con:
#
#   cd ~/.config/omarchy/plugins/omatings
#   tools/check.sh pages/VoicePage.qml pages/voice/CaptureRow.qml \
#     tools/tests/VoicePageTest.qml Settings.qml
#   omarchy restart shell   # Quickshell cachea los componentes QML
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINO="${OMATINGS_DIR:-$HOME/.config/omarchy/plugins/omatings}"

if [[ ! -f "$DESTINO/manifest.json" ]]; then
  echo "falta el plugin omatings en $DESTINO" >&2
  echo "instalalo con: omarchy plugin add https://github.com/parda21/omatings --enable --yes" >&2
  exit 1
fi

install -Dm644 "$AQUI/VoicePage.qml"     "$DESTINO/pages/VoicePage.qml"
install -Dm644 "$AQUI/CaptureRow.qml"    "$DESTINO/pages/voice/CaptureRow.qml"
install -Dm644 "$AQUI/VoicePageTest.qml" "$DESTINO/tools/tests/VoicePageTest.qml"

python3 - "$DESTINO" <<'PY'
import pathlib
import re
import sys

destino = pathlib.Path(sys.argv[1])

# 1) Entrada del sidebar. Va después de "sound" (van juntas en el menú).
pages = destino / "Core" / "Pages.js"
texto = pages.read_text()
if 'id: "voice"' not in texto:
    ancla = '  { id: "network",'
    entrada = (
        '  { id: "voice",      title: "Voice",           icon: 0xF036C, source: "pages/VoicePage.qml",\n'
        '    keywords: "voice dictation speech whisper microphone captured audio transcript listen hear" },\n'
    )
    if ancla not in texto:
        sys.exit("Pages.js no tiene la entrada de network: revisá el formato nuevo")
    pages.write_text(texto.replace(ancla, entrada + ancla, 1))

# 2) Regla de ventana compatible con Omarchy 4.0.4 (hyprctl eval sin `o.*`).
ajustes = destino / "Settings.qml"
texto = ajustes.read_text()
if "hl.window_rule" not in texto:
    patron = re.compile(r"  readonly property string windowRule: 'o\.window\(.*?\n.*?\)'", re.S)
    nuevo = (
        '  // Omarchy 4.0.4: `hyprctl eval` no carga los helpers `o.*`, así que la\n'
        '  // regla se escribe con el DSL `hl.window_rule` (claves snake_case).\n'
        "  readonly property string windowRule: 'hl.window_rule({ match = { class = \"org.quickshell\", '\n"
        "    + 'title = \"^Omarchy Settings$\" }, float = true, center = true, '\n"
        "    + 'size = { 1100, 760 }, opacity = \"1.0 1.0\" })'\n"
    )
    texto, n = patron.subn(nuevo, texto, count=1)
    if n != 1:
        sys.exit("no encontré la regla o.window en Settings.qml: revisá el archivo nuevo")
    ajustes.write_text(texto)
PY

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "Página Voz instalada en $DESTINO"
echo "Abrila con: omarchy-shell shell toggle omatings '{\"page\":\"voice\"}'"
