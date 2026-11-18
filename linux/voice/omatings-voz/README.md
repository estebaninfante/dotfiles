# omatings-voz — la página Voz de los Ajustes

omatings es la app de ajustes del escritorio (plugin `panel` dentro de
`omarchy-shell`): pantallas, sonido, red, bluetooth, apariencia, teclado,
atajos, energía, apps y sistema. Se abre con `SUPER + ,` o desde el menú
(`Ajustes`).

Esta carpeta agrega lo que a omatings le faltaba: la página **Voz**.

## Qué muestra

Los últimos 60 audios que el asistente siempre-escuchando mandó a Whisper, cada
uno con la hora, la duración y el texto que el modelo entendió. Un clic
reproduce el audio capturado: sirve para comparar lo que se oyó contra lo que
se transcribió, y para encontrar audios que no se entienden (micrófono bajo,
ruido de fondo, otra fuente sonando).

Los archivos son los que deja `~/Proyectos/asistente` (`src/asistente/oido.py`)
en `~/.local/state/asistente/audios`: un `.wav` + un `.txt` por enunciado. La
página es de solo lectura.

El dictado de tecla (`SUPER + I`) no guarda su audio: solo existe mientras
transcribe, así que no aparece en la lista.

## Instalar / reinstalar

```bash
omarchy plugin add https://github.com/parda21/omatings --enable --yes   # una vez
~/dotfiles/linux/voice/omatings-voz/instalar.sh                        # cada vez
omarchy restart shell                                                  # Quickshell cachea QML
```

`instalar.sh` es idempotente: copia la página a
`~/.config/omarchy/plugins/omatings/`, registra `voice` en `Core/Pages.js` y
cambia la regla de ventana de `Settings.qml` (`o.window` → `hl.window_rule`:
Omarchy 4.0.4 no tiene los helpers `o.*` en `hyprctl eval` y la ventana nacía
en mosaico).

Prueba headless (no toca la sesión):

```bash
cd ~/.config/omarchy/plugins/omatings
tools/check.sh pages/VoicePage.qml pages/voice/CaptureRow.qml tools/tests/VoicePageTest.qml Settings.qml
```

## Desinstalar

```bash
omarchy plugin remove omatings
```

Se van también los cambios: el plugin vuelve a instalarse limpio desde git.

## Cuidado al escuchar

Con parlantes, el asistente siempre-escuchando oye el clip y lo transcribe
como si fuera una orden. Con auriculares la comparación es limpia.
